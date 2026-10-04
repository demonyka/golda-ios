import Foundation
import GRDB

/// The sync's own SQLite file: the engines' state, the outgoing queue, the server's system fields
/// of each record, and the synced records themselves.
///
/// Why GRDB and why the records live here: the queue has to change in the same transaction as the
/// records it describes, or a crash between the two loses a change or invents one; a state file
/// beside the database could not promise that. In stage 5a the records are the spike's own, so
/// they sit in this separate file and the real books are never touched. In 5b these tables join
/// `GoldaDatabase`'s migrations and the record table gives way to the books' own tables.
public final class SyncStore: Sendable {
    private let writer: any DatabaseWriter

    private init(_ writer: any DatabaseWriter) throws {
        try Self.migrator.migrate(writer)
        self.writer = writer
    }

    /// The file at [url], created with its folder when missing.
    public static func open(at url: URL) throws -> SyncStore {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try SyncStore(DatabaseQueue(path: url.path))
    }

    /// A store that lives as long as this value: tests.
    public static func inMemory() throws -> SyncStore {
        try SyncStore(DatabaseQueue())
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            // `CKSyncEngine.State.Serialization` of each database, opaque here.
            try db.create(table: "syncEngineState") { t in
                t.primaryKey("scope", .text)
                t.column("data", .blob).notNull()
            }
            // One entry per record (`OutgoingChange` as JSON), keyed by `SyncRecordRef.key`.
            try db.create(table: "syncOutgoing") { t in
                t.primaryKey("key", .text)
                t.column("change", .blob).notNull()
            }
            // The server's system fields of each record it has seen (change tag included), so the
            // next save of the record is not taken for a conflicting one.
            try db.create(table: "syncSystemFields") { t in
                t.primaryKey("key", .text)
                t.column("data", .blob).notNull()
            }
            try db.create(table: "syncRecord") { t in
                t.primaryKey("key", .text)
                t.column("zoneKey", .text).notNull().indexed()
                t.column("type", .text).notNull()
                t.column("record", .blob).notNull()
            }
        }
        return migrator
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

    // MARK: Local changes

    /// Writes [record] and queues its save, in one transaction.
    public func save(_ record: SyncRecord, now: Int64) async throws {
        try await writer.write { db in
            try Self.put(record, db)
            try Self.enqueue(.save, record.ref, now: now, undoWindow: 0, db)
        }
    }

    /// Removes the record and queues its delete, which waits out [undoWindow] (ms).
    public func delete(_ ref: SyncRecordRef, now: Int64, undoWindow: Int64 = OutgoingQueue.undoWindow) async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM syncRecord WHERE key = ?", arguments: [ref.key])
            try Self.enqueue(.delete, ref, now: now, undoWindow: undoWindow, db)
        }
    }

    public func record(_ ref: SyncRecordRef) async throws -> SyncRecord? {
        try await writer.read { db in try Self.record(ref.key, db) }
    }

    /// The zone's records, profile first, then by time of writing.
    public func records(in zone: SyncZone) async throws -> [SyncRecord] {
        let records = try await writer.read { db in
            try Data.fetchAll(db, sql: "SELECT record FROM syncRecord WHERE zoneKey = ?", arguments: [zone.key])
                .map(Self.decodeRecord)
        }
        return records.sorted(by: Self.inZoneOrder)
    }

    private static func inZoneOrder(_ a: SyncRecord, _ b: SyncRecord) -> Bool {
        let aIsProfile = a.payload.type == .profile, bIsProfile = b.payload.type == .profile
        if aIsProfile != bIsProfile { return aIsProfile }
        if a.updatedAt != b.updatedAt { return a.updatedAt < b.updatedAt }
        if a.payload.type != b.payload.type { return a.payload.type == .operation }
        return a.ref.recordName < b.ref.recordName
    }

    /// The profiles this phone has, own and shared, by name.
    public func profiles() async throws -> [SyncRecord] {
        try await writer.read { db in
            try Data.fetchAll(db, sql: "SELECT record FROM syncRecord WHERE type = ?", arguments: [SyncRecordType.profile.rawValue])
                .map(Self.decodeRecord)
                .sorted { $0.ref.key < $1.ref.key }
        }
    }

    // MARK: The queue

    public func outgoing() async throws -> [OutgoingChange] {
        try await writer.read { db in try Self.allOutgoing(db) }
    }

    /// What the transport should take at [now], marked as handed over in the same transaction.
    public func takeDue(at now: Int64) async throws -> [OutgoingChange] {
        try await writer.write { db in
            var due: [OutgoingChange] = []
            for var change in try Self.allOutgoing(db) where change.isDue(at: now) {
                change.handedRevision = change.revision
                try Self.putOutgoing(change, db)
                due.append(change)
            }
            return due
        }
    }

    /// The earliest moment a waiting delete becomes due, to wake up for it.
    public func nextDue(after now: Int64) async throws -> Int64? {
        try await outgoing().filter { $0.notBefore > now && $0.handedRevision != $0.revision }.map(\.notBefore).min()
    }

    /// Forgets that the entries of [refs] (all, when nil) were handed over, so they are handed
    /// again: a new process starts a new engine, which may not have kept them, and a conflict won
    /// by this phone has to be sent once more. The engine takes a repeat as one change.
    public func rehand(_ refs: [SyncRecordRef]? = nil) async throws {
        let keys = refs.map { Set($0.map(\.key)) }
        try await writer.write { db in
            for var change in try Self.allOutgoing(db)
            where change.handedRevision != nil && keys?.contains(change.ref.key) != false {
                change.handedRevision = nil
                try Self.putOutgoing(change, db)
            }
        }
    }

    /// The server took the [kind] of [ref]: the entry goes unless a newer wish replaced it.
    public func confirm(_ kind: OutgoingKind, of ref: SyncRecordRef) async throws {
        try await writer.write { db in
            guard let entry = try Self.outgoing(ref.key, db), OutgoingQueue.isSettled(entry, by: kind) else { return }
            try db.execute(sql: "DELETE FROM syncOutgoing WHERE key = ?", arguments: [ref.key])
        }
    }

    // MARK: Incoming

    /// Applies records and deletions from the server, last writer winning (`SyncConflict`). A
    /// local delete still waiting to be sent stands; a remote delete removes the record and any
    /// local wish for it. Returns the refs whose local version won and so must be sent again.
    @discardableResult
    public func apply(_ incoming: [SyncRecord], deletions: [SyncRecordRef] = []) async throws -> [SyncRecordRef] {
        try await writer.write { db in
            var keptLocal: [SyncRecordRef] = []
            for record in incoming {
                let key = record.ref.key
                let entry = try Self.outgoing(key, db)
                if entry?.kind == .delete {
                    keptLocal.append(record.ref)
                    continue
                }
                if entry?.kind == .save, let local = try Self.record(key, db), !SyncConflict.incomingWins(record, over: local) {
                    keptLocal.append(record.ref)
                    continue
                }
                try Self.put(record, db)
                try db.execute(sql: "DELETE FROM syncOutgoing WHERE key = ?", arguments: [key])
            }
            for ref in deletions {
                for table in ["syncRecord", "syncOutgoing", "syncSystemFields"] {
                    try db.execute(sql: "DELETE FROM \(table) WHERE key = ?", arguments: [ref.key])
                }
            }
            return keptLocal
        }
    }

    /// Forgets the zone and all it held: the profile was deleted, its share stopped or left.
    public func removeZone(_ zone: SyncZone) async throws {
        try await writer.write { db in
            let prefix = zone.key + "|"
            for table in ["syncRecord", "syncOutgoing", "syncSystemFields"] {
                try db.execute(
                    sql: "DELETE FROM \(table) WHERE substr(key, 1, ?) = ?", arguments: [prefix.count, prefix]
                )
            }
        }
    }

    /// Forgets everything: another iCloud account signed in, whose data is not this one's.
    public func wipe() async throws {
        try await writer.write { db in
            for table in ["syncEngineState", "syncOutgoing", "syncSystemFields", "syncRecord"] {
                try db.execute(sql: "DELETE FROM \(table)")
            }
        }
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
                try db.execute(sql: "INSERT OR REPLACE INTO syncSystemFields (key, data) VALUES (?, ?)", arguments: [ref.key, data])
            } else {
                try db.execute(sql: "DELETE FROM syncSystemFields WHERE key = ?", arguments: [ref.key])
            }
        }
    }

    // MARK: Rows

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    private static func decodeRecord(_ data: Data) throws -> SyncRecord {
        try JSONDecoder().decode(SyncRecord.self, from: data)
    }

    private static func put(_ record: SyncRecord, _ db: Database) throws {
        try db.execute(
            sql: "INSERT OR REPLACE INTO syncRecord (key, zoneKey, type, record) VALUES (?, ?, ?, ?)",
            arguments: [record.ref.key, record.zone.key, record.payload.type.rawValue, try encoder.encode(record)]
        )
    }

    private static func record(_ key: String, _ db: Database) throws -> SyncRecord? {
        try Data.fetchOne(db, sql: "SELECT record FROM syncRecord WHERE key = ?", arguments: [key]).map(decodeRecord)
    }

    private static func enqueue(_ kind: OutgoingKind, _ ref: SyncRecordRef, now: Int64, undoWindow: Int64, _ db: Database) throws {
        let merged = OutgoingQueue.merge(try outgoing(ref.key, db), kind: kind, ref: ref, now: now, undoWindow: undoWindow)
        try putOutgoing(merged, db)
    }

    private static func outgoing(_ key: String, _ db: Database) throws -> OutgoingChange? {
        try Data.fetchOne(db, sql: "SELECT change FROM syncOutgoing WHERE key = ?", arguments: [key])
            .map { try JSONDecoder().decode(OutgoingChange.self, from: $0) }
    }

    private static func allOutgoing(_ db: Database) throws -> [OutgoingChange] {
        try Data.fetchAll(db, sql: "SELECT change FROM syncOutgoing ORDER BY key")
            .map { try JSONDecoder().decode(OutgoingChange.self, from: $0) }
    }

    private static func putOutgoing(_ change: OutgoingChange, _ db: Database) throws {
        try db.execute(
            sql: "INSERT OR REPLACE INTO syncOutgoing (key, change) VALUES (?, ?)",
            arguments: [change.ref.key, try encoder.encode(change)]
        )
    }
}
