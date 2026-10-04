import Foundation
import GoldaCore
import GRDB

/// The local side of sync, over the books' own database: the engines' state, the outgoing queue,
/// the server's system fields of each record, and the way records from the server get into the
/// books.
///
/// Why the books' file: the queue has to change in the same transaction as the rows it describes,
/// or a crash between the two loses a change or invents one (D57). Local changes reach the queue
/// on their own (`GoldaDatabase.write` → `SyncLedger.flush`); what comes from the server is written
/// here, and is not queued again.
public final class SyncStore: Sendable {
    public let database: GoldaDatabase
    /// The name of the empty profile that takes the place of the last one when sync takes it away
    /// (its owner stopped sharing, another account signed in): the app always has a profile to
    /// show. Nil leaves none, for tests of the store alone.
    let lastProfileName: String?
    private var writer: any DatabaseWriter { database.writer }

    public init(database: GoldaDatabase, lastProfileName: String? = nil) {
        self.database = database
        self.lastProfileName = lastProfileName
    }

    /// After sync took profiles away: a fresh one when none is left, in the same transaction, so
    /// no screen ever sees an empty list. It is an own profile, and sync gives it a zone later.
    private func keepAProfile(_ db: Database) throws {
        guard let lastProfileName, try ProfileRecord.fetchCount(db) == 0 else { return }
        try Store(db: db).save(Profile(name: lastProfileName))
    }

    /// This install as the author of its records.
    public func deviceName() async throws -> String {
        try await writer.read { db in try SyncLedger.device(db) }
    }

    // MARK: Engine state

    public func engineState(_ scope: SyncScope) async throws -> Data? {
        try await writer.read { db in
            try Data.fetchOne(db, sql: "SELECT data FROM syncEngineState WHERE scope = ?", arguments: [scope.rawValue])
        }
    }

    public func setEngineState(_ data: Data, for scope: SyncScope) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO syncEngineState (scope, data) VALUES (?, ?)", arguments: [scope.rawValue, data]
            )
        }
    }

    // MARK: Zones

    /// The zone of every profile on this phone: shared ones under their owner, the rest own.
    public func zones() async throws -> [UUID: SyncZone] {
        try await writer.read { db in
            var zones: [UUID: SyncZone] = [:]
            for id in try UUID.fetchAll(db, sql: "SELECT id FROM profile") {
                zones[id] = try SyncLedger.zoneRow(id, db)?.zone ?? .own(id)
            }
            return zones
        }
    }

    /// The zone of [profileId], nil when there is no such profile.
    public func zone(of profileId: UUID) async throws -> SyncZone? {
        try await zones()[profileId]
    }

    /// Gives sync the own profiles it does not know yet (made before sync, or while iCloud was off)
    /// and queues every row of theirs, so they reach their zones. Returns the zones to create.
    public func registerProfiles(now: Int64) async throws -> [SyncZone] {
        try await writer.write { db in
            let device = try SyncLedger.device(db)
            var created: [SyncZone] = []
            let unknown = try UUID.fetchAll(
                db, sql: "SELECT id FROM profile WHERE id NOT IN (SELECT profileId FROM syncZone) ORDER BY sort"
            )
            for profileId in unknown {
                let zone = SyncZone.own(profileId)
                try SyncLedger.putZone(zone, db)
                for (type, id) in try Self.rows(of: profileId, db) {
                    let ref = SyncRecordRef(zone: zone, type: type, id: id)
                    try SyncLedger.enqueue(.save, ref, profileId: profileId, now: now, db)
                    if try SyncLedger.meta(type, id, db) == nil {
                        try SyncLedger.putMeta(type, id, profileId: profileId, updatedAt: now, author: device, db)
                    }
                }
                created.append(zone)
            }
            return created
        }
    }

    /// Every row of the profile, the profile first, then in the order a receiver can apply them.
    private static func rows(of profileId: UUID, _ db: Database) throws -> [(SyncRecordType, UUID)] {
        var rows: [(SyncRecordType, UUID)] = [(.profile, profileId)]
        for type in SyncRecordType.allCases where type != .profile {
            let ids = try UUID.fetchAll(
                db, sql: "SELECT id FROM \"\(type.tableName)\" WHERE profileId = ? ORDER BY rowid", arguments: [profileId]
            )
            rows += ids.map { (type, $0) }
        }
        return rows
    }

    /// Zones whose profile was deleted or left here and which the server has still to hear of.
    public func zonesToRemove() async throws -> [SyncZone] {
        try await writer.read { db in
            try Row.fetchAll(db, sql: "SELECT profileId, scope, ownerName FROM syncZone WHERE removing = 1").compactMap { row in
                guard let scope = SyncScope(rawValue: row["scope"]) else { return nil }
                return SyncZone(profileId: row["profileId"], ownerName: row["ownerName"], scope: scope)
            }
        }
    }

    /// The server deleted or left [zone] as asked: nothing is left to remember of it.
    public func zoneRemoved(_ zone: SyncZone) async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM syncZone WHERE profileId = ? AND removing = 1", arguments: [zone.profileId])
            try SyncLedger.forget(zone.profileId, db)
        }
    }

    // MARK: The queue

    public func outgoing() async throws -> [OutgoingChange] {
        try await writer.read { db in try SyncLedger.allOutgoing(db) }
    }

    /// What the transport should take at [now], marked as handed over in the same transaction.
    public func takeDue(at now: Int64) async throws -> [OutgoingChange] {
        try await writer.write { db in
            var due: [OutgoingChange] = []
            for var change in try SyncLedger.allOutgoing(db) where change.isDue(at: now) {
                change.handedRevision = change.revision
                try SyncLedger.putOutgoing(change, db)
                due.append(change)
            }
            return due
        }
    }

    /// The earliest moment a waiting entry becomes due (a delete's undo window, a postponed send),
    /// to wake up for it.
    public func nextDue(after now: Int64) async throws -> Int64? {
        try await outgoing().filter { $0.notBefore > now && $0.handedRevision != $0.revision }.map(\.notBefore).min()
    }

    /// Forgets that the entries of [refs] (all, when nil) were handed over, so they are handed
    /// again: a new process starts a new engine, which may not have kept them, and a conflict won
    /// by this phone has to be sent once more. The engine takes a repeat as one change.
    public func rehand(_ refs: [SyncRecordRef]? = nil) async throws {
        let keys = refs.map { Set($0.map(\.key)) }
        try await writer.write { db in
            for var change in try SyncLedger.allOutgoing(db)
            where change.handedRevision != nil && keys?.contains(change.ref.key) != false {
                change.handedRevision = nil
                try SyncLedger.putOutgoing(change, db)
            }
        }
    }

    /// The server asked to wait: [refs] go back to the queue and are not handed over before [until].
    public func postpone(_ refs: [SyncRecordRef], until: Int64) async throws {
        try await writer.write { db in
            for ref in refs {
                guard let entry = try SyncLedger.outgoing(ref.key, db) else { continue }
                try SyncLedger.putOutgoing(OutgoingQueue.postponed(entry, until: until), db)
            }
        }
    }

    /// The server took the [kind] of [ref]: the entry goes unless a newer wish replaced it.
    public func confirm(_ kind: OutgoingKind, of ref: SyncRecordRef) async throws {
        try await writer.write { db in
            guard let entry = try SyncLedger.outgoing(ref.key, db), OutgoingQueue.isSettled(entry, by: kind) else { return }
            try db.execute(sql: "DELETE FROM syncOutgoing WHERE key = ?", arguments: [ref.key])
        }
    }

    /// The record as it is in the books now, to send; nil when its row is gone (deleted since it
    /// was queued) or belongs to another profile.
    public func record(_ ref: SyncRecordRef) async throws -> SyncRecord? {
        try await writer.read { db in
            let store = Store(db: db)
            let profileId = ref.zone.profileId
            let payload: SyncPayload?
            switch ref.type {
            case .profile:
                payload = ref.id == profileId ? try store.profile(profileId).map(SyncPayload.profile) : nil
            case .account:
                payload = try store.account(ref.id, profileId: profileId).map(SyncPayload.account)
            case .operation:
                payload = try store.operation(ref.id, profileId: profileId).map { .operation($0.op, postingCount: $0.postings.count) }
            case .posting:
                payload = try PostingRecord.owned(by: profileId).filter(id: ref.id).fetchOne(db).map { .posting($0.posting) }
            case .obligation:
                payload = try ObligationRecord.owned(by: profileId).filter(id: ref.id).fetchOne(db).map {
                    .obligation($0.obligation, createdAt: $0.createdAt ?? 0)
                }
            case .goal:
                payload = try GoalRecord.owned(by: profileId).filter(id: ref.id).fetchOne(db).map {
                    .goal($0.goal, createdAt: $0.createdAt ?? 0)
                }
            case .wish:
                payload = try store.wish(ref.id, profileId: profileId).map(SyncPayload.wish)
            }
            guard let payload else { return nil }
            let meta = try SyncLedger.meta(ref.type, ref.id, db)
            return SyncRecord(
                zone: ref.zone, payload: payload, updatedAt: meta?.updatedAt ?? 0,
                authorDevice: try meta?.author ?? SyncLedger.device(db)
            )
        }
    }

    // MARK: Incoming

    /// Applies records and deletions from the server, last writer winning (`SyncConflict`), and
    /// returns the refs whose local version won and so must be sent again.
    ///
    /// A local delete still waiting to be sent stands; a remote delete removes the row and any
    /// local wish for it. What wins goes to the inbox first and into the books once it can stand
    /// there: an operation with all its postings (`postingCount`), a posting with its account,
    /// everything with its profile. None of it is queued again.
    @discardableResult
    public func apply(_ incoming: [SyncRecord], deletions: [SyncRecordRef] = []) async throws -> [SyncRecordRef] {
        try await writer.write { db in
            var keptLocal: [SyncRecordRef] = []
            var touched: Set<UUID> = []
            for record in incoming {
                let ref = record.ref, profileId = ref.zone.profileId
                if let row = try SyncLedger.zoneRow(profileId, db) {
                    // Being left or deleted here, or not the zone this phone has the profile in.
                    if row.removing || row.zone != ref.zone { continue }
                } else if try Self.profileExists(profileId, db), ref.zone.scope == .shared {
                    // An own profile of the same id cannot turn into someone else's.
                    continue
                } else {
                    try SyncLedger.putZone(ref.zone, db)
                }
                let entry = try SyncLedger.outgoing(ref.key, db)
                if entry?.kind == .delete {
                    keptLocal.append(ref)
                    continue
                }
                if entry?.kind == .save, let local = try SyncLedger.meta(ref.type, ref.id, db),
                   !SyncConflict.incomingWins(
                       updatedAt: record.updatedAt, author: record.authorDevice, overUpdatedAt: local.updatedAt, author: local.author
                   ) {
                    keptLocal.append(ref)
                    continue
                }
                try SyncInbox.put(record, db)
                try db.execute(sql: "DELETE FROM syncOutgoing WHERE key = ?", arguments: [ref.key])
                touched.insert(profileId)
            }
            for ref in deletions {
                try SyncInbox.delete(ref, db)
                touched.insert(ref.zone.profileId)
            }
            for profileId in touched {
                try SyncInbox.promote(profileId, db)
            }
            try SyncLedger.discardJournal(db)
            return keptLocal
        }
    }

    /// Why the server no longer has a zone for this phone.
    public enum ZoneLoss: Sendable {
        /// Deleted by its owner, unshared, or left: the profile goes from this phone.
        case deleted
        /// The person deleted the app's iCloud data, or reset their encrypted data: the server lost
        /// the zone, not the books. They stay and are uploaded again.
        case lostOnServer
    }

    /// The server no longer has [zone] for this phone. Returns whether a profile went.
    @discardableResult
    public func zoneGone(_ zone: SyncZone, _ loss: ZoneLoss) async throws -> Bool {
        try await writer.write { db in
            let row = try SyncLedger.zoneRow(zone.profileId, db)
            // A zone of the same name this phone does not have the profile in: not ours to drop.
            if let row, row.zone != zone { return false }
            try SyncLedger.forget(zone.profileId, db)
            try db.execute(sql: "DELETE FROM syncZone WHERE profileId = ?", arguments: [zone.profileId])
            guard loss == .deleted || !zone.isOwned, row?.removing != true else { return false }
            let removed = try Store(db: db).deleteProfile(zone.profileId)
            if removed { try keepAProfile(db) }
            try SyncLedger.discardJournal(db)
            return removed
        }
    }

    /// Another iCloud account signed in, or none is: what sync knew belongs to the old account.
    /// Profiles shared with the old account leave this phone (they live on with their owner); the
    /// phone's own books stay, and go to the new account's zones once it signs in.
    public func resetForAccountChange() async throws {
        try await writer.write { db in
            let shared = try UUID.fetchAll(db, sql: "SELECT profileId FROM syncZone WHERE scope = ?", arguments: [SyncScope.shared.rawValue])
            for profileId in shared { try Store(db: db).deleteProfile(profileId) }
            if !shared.isEmpty { try keepAProfile(db) }
            try SyncLedger.discardJournal(db)
            for table in ["syncZone", "syncOutgoing", "syncSystemFields", "syncEngineState", "syncInbox"] {
                try db.execute(sql: "DELETE FROM \(table)")
            }
        }
    }

    /// Records that arrived and wait for the rest of what they need.
    public func waitingCount() async throws -> Int {
        try await writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM syncInbox") ?? 0 }
    }

    // MARK: System fields

    public func systemFields(_ ref: SyncRecordRef) async throws -> Data? {
        try await writer.read { db in
            try Data.fetchOne(db, sql: "SELECT data FROM syncSystemFields WHERE key = ?", arguments: [ref.key])
        }
    }

    /// Keeps the server's fields of [ref], or forgets them with nil (the server no longer has it).
    public func setSystemFields(_ data: Data?, for ref: SyncRecordRef) async throws {
        try await writer.write { db in
            if let data {
                try db.execute(
                    sql: "INSERT OR REPLACE INTO syncSystemFields (key, profileId, data) VALUES (?, ?, ?)",
                    arguments: [ref.key, ref.zone.profileId, data]
                )
            } else {
                try db.execute(sql: "DELETE FROM syncSystemFields WHERE key = ?", arguments: [ref.key])
            }
        }
    }

    // MARK: Observing

    /// A signal after each change sync has to act on: a new wish in the queue, a profile to give
    /// to sync, a zone to remove. The first comes at once.
    public func changes() -> AsyncThrowingStream<Void, any Error> {
        let observation = ValueObservation.tracking { db -> [Int64] in
            [
                try Int64.fetchOne(db, sql: "SELECT COUNT(*) + COALESCE(SUM(revision), 0) FROM syncOutgoing") ?? 0,
                try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM syncZone WHERE removing = 1") ?? 0,
                try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM profile") ?? 0,
            ]
        }
        .removeDuplicates()
        let values = observation.values(in: writer, bufferingPolicy: .bufferingNewest(1))
        return AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                do {
                    for try await _ in values { continuation.yield(()) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func profileExists(_ id: UUID, _ db: Database) throws -> Bool {
        try ProfileRecord.exists(db, id: id)
    }
}
