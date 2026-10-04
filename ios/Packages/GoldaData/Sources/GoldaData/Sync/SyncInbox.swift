import Foundation
import GoldaCore
import GRDB

/// Records from the server on their way into the books. CloudKit delivers a zone's records in no
/// particular order and in batches, while the books only take a posting after its operation and
/// account, and anything after its profile; and an operation must never be seen with half its
/// postings (a transfer with one leg is money appearing from nowhere). So records wait here until
/// what they need is in, and go in together.
enum SyncInbox {
    static func put(_ record: SyncRecord, _ db: Database) throws {
        var operationId: UUID?
        if case .posting(let posting) = record.payload { operationId = posting.operationId }
        try db.execute(
            sql: "INSERT OR REPLACE INTO syncInbox (key, profileId, type, operationId, record) VALUES (?, ?, ?, ?, ?)",
            arguments: [
                record.ref.key, record.zone.profileId, record.payload.type.rawValue, operationId,
                try SyncLedger.encoder.encode(record),
            ]
        )
    }

    /// A deletion from the server: the row goes from the books (an operation with its postings, an
    /// account with its postings) and from the inbox, and so does all sync knew of it. A profile
    /// is never deleted one record at a time; its zone goes (`SyncStore.zoneGone`).
    static func delete(_ ref: SyncRecordRef, _ db: Database) throws {
        let profileId = ref.zone.profileId
        guard try SyncLedger.zoneRow(profileId, db)?.zone ?? .own(profileId) == ref.zone else { return }
        let store = Store(db: db)
        switch ref.type {
        case .profile: return
        case .account: try store.deleteAccount(ref.id, profileId: profileId)
        case .operation:
            try store.deleteOperation(ref.id, profileId: profileId)
            try db.execute(sql: "DELETE FROM syncInbox WHERE operationId = ?", arguments: [ref.id])
        case .posting: try store.deletePosting(ref.id, profileId: profileId)
        case .obligation: try store.deleteObligation(ref.id, profileId: profileId)
        case .goal: try store.deleteGoal(ref.id, profileId: profileId)
        case .wish: try store.deleteWish(ref.id, profileId: profileId)
        }
        try db.execute(sql: "DELETE FROM syncInbox WHERE key = ?", arguments: [ref.key])
        try db.execute(sql: "DELETE FROM syncOutgoing WHERE key = ?", arguments: [ref.key])
        try db.execute(sql: "DELETE FROM syncSystemFields WHERE key = ?", arguments: [ref.key])
        try db.execute(sql: "DELETE FROM syncMeta WHERE tableName = ? AND id = ?", arguments: [ref.type.tableName, ref.id])
    }

    /// Moves into the books what of the profile's waiting records can stand there now.
    static func promote(_ profileId: UUID, _ db: Database) throws {
        let waiting = try Data.fetchAll(db, sql: "SELECT record FROM syncInbox WHERE profileId = ?", arguments: [profileId])
            .map { try JSONDecoder().decode(SyncRecord.self, from: $0) }
        guard !waiting.isEmpty else { return }
        let store = Store(db: db)

        func landed(_ record: SyncRecord) throws {
            try db.execute(sql: "DELETE FROM syncInbox WHERE key = ?", arguments: [record.ref.key])
            try SyncLedger.putMeta(
                record.payload.type, record.payload.id, profileId: profileId, updatedAt: record.updatedAt,
                author: record.authorDevice, db
            )
        }

        // The profile first: nothing else can stand without it. Its place in the list is this
        // phone's own: a new profile comes after the others, a known one keeps its place.
        for record in waiting {
            guard case .profile(var profile) = record.payload else { continue }
            let profiles = try store.profiles()
            profile.sort = profiles.first { $0.id == profile.id }?.sort ?? ((profiles.map(\.sort).max() ?? -1) + 1)
            try store.save(profile)
            try landed(record)
        }
        guard try store.profile(profileId) != nil else { return }

        // Rows that stand on their own; a row of another profile's id is refused and left waiting.
        for record in waiting {
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
                case .profile, .operation, .posting:
                    continue
                }
                try landed(record)
            } catch StoreError.belongsToAnotherProfile {
                continue
            }
        }

        // Operations go in whole: the header and exactly as many postings as it says.
        var headers: [UUID: SyncRecord] = [:]
        var postings: [UUID: [SyncRecord]] = [:]
        for record in waiting {
            switch record.payload {
            case .operation(let operation, _): headers[operation.id] = record
            case .posting(let posting): postings[posting.operationId, default: []].append(record)
            default: break
            }
        }
        let accountIds = Set(try store.accounts(profileId: profileId).map(\.id))
        for operationId in Set(headers.keys).union(postings.keys) {
            let stored = try store.operation(operationId, profileId: profileId)
            let arriving = postings[operationId] ?? []
            let expected: Int
            if let header = headers[operationId], case .operation(_, let count) = header.payload {
                expected = count
            } else if let stored {
                // No new header: the postings may only change what the operation already has.
                expected = stored.postings.count
            } else {
                continue
            }
            let storedIds = Set(stored?.postings.map(\.id) ?? [])
            let arrivingPostings = arriving.compactMap { record -> Posting? in
                if case .posting(let posting) = record.payload { return posting }
                return nil
            }
            guard storedIds.union(arrivingPostings.map(\.id)).count == expected,
                  arrivingPostings.allSatisfy({ accountIds.contains($0.accountId) })
            else { continue }

            if let header = headers[operationId], case .operation(let operation, _) = header.payload {
                try store.save(operation, profileId: profileId, updatedAt: header.updatedAt)
                try landed(header)
            }
            // New postings in the order the ledger makes them, money out before money in, so a
            // transfer's legs are read (and later edited) as the author's.
            let ordered = zip(arriving, arrivingPostings).sorted { a, b in
                let aNew = !storedIds.contains(a.1.id), bNew = !storedIds.contains(b.1.id)
                if aNew != bNew { return !aNew }
                return a.1.amountMinor < b.1.amountMinor
            }
            for (record, posting) in ordered {
                try store.save(posting, profileId: profileId)
                try landed(record)
            }
        }
    }
}
