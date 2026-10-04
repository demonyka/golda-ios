import Foundation
import GRDB

/// The sync tables inside one transaction: what `GoldaDatabase.write` and `SyncStore` share.
enum SyncLedger {
    // MARK: Local changes

    /// Turns what the transaction changed in the books (`syncJournal`, filled by triggers) into
    /// queue entries stamped [now], then empties the journal. Runs inside every write of the books,
    /// before it commits.
    ///
    /// A deleted profile is not a list of deleted rows: its zone goes as a whole (or is left, when
    /// it was shared with this person), so its rows leave the queue and the zone is marked for
    /// removal. A delete waits out the undo window; "Отменить" writes the rows again, and the save
    /// replaces the delete before it is sent.
    static func flush(_ db: Database, now: Int64) throws {
        let rows = try Row.fetchAll(db, sql: "SELECT tableName, id, profileId, deleted FROM syncJournal")
        guard !rows.isEmpty else { return }
        let device = try self.device(db)
        var zones: [UUID: SyncZone] = [:]
        func zone(_ profileId: UUID) throws -> SyncZone {
            if let known = zones[profileId] { return known }
            let found = try zoneRow(profileId, db)?.zone ?? .own(profileId)
            zones[profileId] = found
            return found
        }

        let removed = Set(rows.compactMap { row -> UUID? in
            row["tableName"] == "profile" && row["deleted"] == true ? row["id"] : nil
        })
        for profileId in removed {
            let zone = try zone(profileId)
            try db.execute(
                sql: "INSERT OR REPLACE INTO syncZone (profileId, scope, ownerName, removing) VALUES (?, ?, ?, 1)",
                arguments: [profileId, zone.scope.rawValue, zone.ownerName]
            )
            try forget(profileId, db)
        }

        for row in rows {
            let profileId: UUID = row["profileId"]
            guard !removed.contains(profileId), let type = SyncRecordType(tableName: row["tableName"]) else { continue }
            let id: UUID = row["id"]
            let deleted: Bool = row["deleted"]
            let ref = SyncRecordRef(zone: try zone(profileId), type: type, id: id)
            try enqueue(deleted ? .delete : .save, ref, profileId: profileId, now: now, db)
            if deleted {
                try db.execute(sql: "DELETE FROM syncMeta WHERE tableName = ? AND id = ?", arguments: [type.tableName, id])
            } else {
                try putMeta(type, id, profileId: profileId, updatedAt: now, author: device, db)
                // A profile written again (a backup restored over it) is no longer being removed.
                if type == .profile {
                    try db.execute(sql: "UPDATE syncZone SET removing = 0 WHERE profileId = ?", arguments: [profileId])
                }
            }
        }
        try db.execute(sql: "DELETE FROM syncJournal")
    }

    /// Empties the journal without queueing anything: the changes came from the server.
    static func discardJournal(_ db: Database) throws {
        try db.execute(sql: "DELETE FROM syncJournal")
    }

    // MARK: Rows

    static func device(_ db: Database) throws -> String {
        try String.fetchOne(db, sql: "SELECT name FROM syncDevice WHERE id = 1") ?? ""
    }

    static func zoneRow(_ profileId: UUID, _ db: Database) throws -> (zone: SyncZone, removing: Bool)? {
        guard let row = try Row.fetchOne(
            db, sql: "SELECT scope, ownerName, removing FROM syncZone WHERE profileId = ?", arguments: [profileId]
        ), let scope = SyncScope(rawValue: row["scope"]) else { return nil }
        return (SyncZone(profileId: profileId, ownerName: row["ownerName"], scope: scope), row["removing"])
    }

    static func putZone(_ zone: SyncZone, _ db: Database) throws {
        try db.execute(
            sql: "INSERT OR REPLACE INTO syncZone (profileId, scope, ownerName, removing) VALUES (?, ?, ?, 0)",
            arguments: [zone.profileId, zone.scope.rawValue, zone.ownerName]
        )
    }

    /// Drops what sync kept about the profile's rows: the queue, the stamps, the inbox, the
    /// server's fields. Its zone row stays.
    static func forget(_ profileId: UUID, _ db: Database) throws {
        for table in ["syncOutgoing", "syncMeta", "syncInbox", "syncSystemFields"] {
            try db.execute(sql: "DELETE FROM \(table) WHERE profileId = ?", arguments: [profileId])
        }
    }

    static func enqueue(
        _ kind: OutgoingKind, _ ref: SyncRecordRef, profileId: UUID, now: Int64, undoWindow: Int64 = OutgoingQueue.undoWindow,
        _ db: Database
    ) throws {
        let merged = OutgoingQueue.merge(try outgoing(ref.key, db), kind: kind, ref: ref, now: now, undoWindow: undoWindow)
        try putOutgoing(merged, profileId: profileId, db)
    }

    static func outgoing(_ key: String, _ db: Database) throws -> OutgoingChange? {
        try Data.fetchOne(db, sql: "SELECT change FROM syncOutgoing WHERE key = ?", arguments: [key]).map(decodeChange)
    }

    static func allOutgoing(_ db: Database) throws -> [OutgoingChange] {
        try Data.fetchAll(db, sql: "SELECT change FROM syncOutgoing ORDER BY key").map(decodeChange)
    }

    static func putOutgoing(_ change: OutgoingChange, profileId: UUID? = nil, _ db: Database) throws {
        try db.execute(
            sql: "INSERT OR REPLACE INTO syncOutgoing (key, profileId, change, revision) VALUES (?, ?, ?, ?)",
            arguments: [change.ref.key, profileId ?? change.ref.zone.profileId, try encoder.encode(change), change.revision]
        )
    }

    static func meta(_ type: SyncRecordType, _ id: UUID, _ db: Database) throws -> (updatedAt: Int64, author: String)? {
        guard let row = try Row.fetchOne(
            db, sql: "SELECT updatedAt, authorDevice FROM syncMeta WHERE tableName = ? AND id = ?",
            arguments: [type.tableName, id]
        ) else { return nil }
        return (row["updatedAt"], row["authorDevice"])
    }

    static func putMeta(_ type: SyncRecordType, _ id: UUID, profileId: UUID, updatedAt: Int64, author: String, _ db: Database) throws {
        try db.execute(
            sql: """
                INSERT OR REPLACE INTO syncMeta (tableName, id, profileId, updatedAt, authorDevice) VALUES (?, ?, ?, ?, ?)
                """,
            arguments: [type.tableName, id, profileId, updatedAt, author]
        )
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    private static func decodeChange(_ data: Data) throws -> OutgoingChange {
        try JSONDecoder().decode(OutgoingChange.self, from: data)
    }
}
