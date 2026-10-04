import Foundation
import GoldaCore
import GRDB

/// Records from the server on their way into the books. CloudKit delivers a zone's records in no
/// particular order and in batches, while the books only take an operation after the accounts of
/// its postings, and anything after its profile. So records wait here until what they need is in.
/// An operation brings all its postings in its own record, so it is never seen with half of them.
enum SyncInbox {
    static func put(_ record: SyncRecord, _ db: Database) throws {
        try db.execute(
            sql: "INSERT OR REPLACE INTO syncInbox (key, profileId, type, record) VALUES (?, ?, ?, ?)",
            arguments: [record.ref.key, record.zone.profileId, record.payload.type.rawValue, try SyncLedger.encoder.encode(record)]
        )
    }

    /// A deletion from the server: the row goes from the books (an operation with its postings) and
    /// from the inbox, and so does all sync knew of it. A profile is never deleted one record at a
    /// time; its zone goes (`SyncStore.zoneGone`).
    ///
    /// An account goes as `Repository.deleteAccount` takes it: with every operation touching it,
    /// both legs of its transfers, so no leg is left on another account. Those are deleted on the
    /// server too when [propagate] (the other phone could not delete what it never saw), and so
    /// are operations waiting here for it, which could otherwise never land.
    static func delete(_ ref: SyncRecordRef, propagate: Bool = true, _ db: Database) throws {
        let profileId = ref.zone.profileId
        guard try SyncLedger.zoneRow(profileId, db)?.zone ?? .own(profileId) == ref.zone else { return }
        let store = Store(db: db)
        switch ref.type {
        case .profile: return
        case .account:
            var touching = Set(
                try store.operations(profileId: profileId)
                    .filter { $0.postings.contains { $0.accountId == ref.id } }
                    .map(\.op.id)
            )
            for record in try waiting(profileId, db) {
                guard case .operation(_, let postings) = record.payload, postings.contains(where: { $0.accountId == ref.id }) else { continue }
                touching.insert(record.payload.id)
            }
            for id in touching {
                let operation = SyncRecordRef(zone: ref.zone, type: .operation, id: id)
                try store.deleteOperation(id, profileId: profileId)
                try forget(operation, db)
                if propagate { try SyncLedger.enqueue(.delete, operation, profileId: profileId, now: 0, undoWindow: 0, db) }
            }
            try store.deleteAccount(ref.id, profileId: profileId)
        case .operation: try store.deleteOperation(ref.id, profileId: profileId)
        case .obligation: try store.deleteObligation(ref.id, profileId: profileId)
        case .goal: try store.deleteGoal(ref.id, profileId: profileId)
        case .wish: try store.deleteWish(ref.id, profileId: profileId)
        }
        try forget(ref, db)
        try db.execute(sql: "DELETE FROM syncOutgoing WHERE key = ?", arguments: [ref.key])
    }

    /// Drops what sync knew of [ref] apart from its queue entry: the inbox, the server's fields,
    /// the stamp.
    private static func forget(_ ref: SyncRecordRef, _ db: Database) throws {
        try db.execute(sql: "DELETE FROM syncInbox WHERE key = ?", arguments: [ref.key])
        try db.execute(sql: "DELETE FROM syncSystemFields WHERE key = ?", arguments: [ref.key])
        try db.execute(sql: "DELETE FROM syncMeta WHERE tableName = ? AND id = ?", arguments: [ref.type.tableName, ref.id])
    }

    private static func waiting(_ profileId: UUID, _ db: Database) throws -> [SyncRecord] {
        try Data.fetchAll(db, sql: "SELECT record FROM syncInbox WHERE profileId = ?", arguments: [profileId])
            .map { try JSONDecoder().decode(SyncRecord.self, from: $0) }
    }

    /// Whether [record] still wins over this phone's version. It was checked when it arrived
    /// (`SyncStore.apply`), but while it waited here the person may have changed the same row;
    /// that later edit is queued and must not be overwritten (it would then go out carrying the
    /// older values). A local delete waiting to be sent stands, as on arrival.
    private static func stillWins(_ record: SyncRecord, _ db: Database) throws -> Bool {
        let ref = record.ref
        guard let entry = try SyncLedger.outgoing(ref.key, db) else { return true }
        if entry.kind == .delete { return false }
        guard let local = try SyncLedger.meta(ref.type, ref.id, db) else { return true }
        return SyncConflict.incomingWins(
            updatedAt: record.updatedAt, author: record.authorDevice, overUpdatedAt: local.updatedAt, author: local.author
        )
    }

    /// Moves into the books what of the profile's waiting records can stand there now.
    static func promote(_ profileId: UUID, _ db: Database) throws {
        let waiting = try waiting(profileId, db)
        guard !waiting.isEmpty else { return }
        let store = Store(db: db)

        func landed(_ record: SyncRecord) throws {
            try db.execute(sql: "DELETE FROM syncInbox WHERE key = ?", arguments: [record.ref.key])
            try SyncLedger.putMeta(
                record.payload.type, record.payload.id, profileId: profileId, updatedAt: record.updatedAt,
                author: record.authorDevice, db
            )
        }

        /// Drops [record] when a local change overtook it; true when it may land.
        func mayLand(_ record: SyncRecord) throws -> Bool {
            if try stillWins(record, db) { return true }
            try db.execute(sql: "DELETE FROM syncInbox WHERE key = ?", arguments: [record.ref.key])
            return false
        }

        // The profile first: nothing else can stand without it. Its place in the list is this
        // phone's own: a new profile comes after the others, a known one keeps its place.
        for record in waiting {
            guard case .profile(var profile) = record.payload, try mayLand(record) else { continue }
            let profiles = try store.profiles()
            profile.sort = profiles.first { $0.id == profile.id }?.sort ?? ((profiles.map(\.sort).max() ?? -1) + 1)
            try store.save(profile)
            try landed(record)
        }
        guard try store.profile(profileId) != nil else { return }

        // Rows that stand on their own; a row of another profile's id is refused and left waiting.
        for record in waiting {
            switch record.payload {
            case .profile, .operation: continue
            default: break
            }
            guard try mayLand(record) else { continue }
            do {
                switch record.payload {
                case .account(let account):
                    try store.save(account, profileId: profileId)
                case .obligation(let obligation, let createdAt):
                    try store.save(obligation, profileId: profileId, createdAt: createdAt)
                case .goal(let goal, let createdAt):
                    try store.save(goal, profileId: profileId, createdAt: createdAt)
                case .wish(let wish):
                    try store.save(wish, profileId: profileId)
                case .profile, .operation:
                    continue
                }
                try landed(record)
            } catch StoreError.belongsToAnotherProfile {
                continue
            }
        }

        // Operations once every account they touch is here, and whole: the postings the record
        // lists replace the ones stored, in its order.
        let accountIds = Set(try store.accounts(profileId: profileId).map(\.id))
        for record in waiting {
            guard case .operation(let operation, let postings) = record.payload,
                  postings.allSatisfy({ $0.operationId == operation.id && accountIds.contains($0.accountId) }),
                  try mayLand(record)
            else { continue }
            do {
                // All of it or none: a posting of another profile's id must not leave half an edit.
                try db.inSavepoint {
                    try store.save(operation, profileId: profileId, updatedAt: record.updatedAt)
                    let listed = Set(postings.map(\.id))
                    for stored in try store.operation(operation.id, profileId: profileId)?.postings ?? [] where !listed.contains(stored.id) {
                        try store.deletePosting(stored.id, profileId: profileId)
                    }
                    for posting in postings {
                        try store.save(posting, profileId: profileId)
                    }
                    return .commit
                }
                try landed(record)
            } catch StoreError.belongsToAnotherProfile {
                continue
            }
        }
    }
}
