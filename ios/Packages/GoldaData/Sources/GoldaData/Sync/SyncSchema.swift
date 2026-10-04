import Foundation
import GRDB

// The sync's tables (migration v2, stage 5b). They live in the books' own file, so a change to the
// books and the queue entry that sends it commit together, or neither does (D57).
enum SyncSchema {
    /// The columns of each table that travel to the other phones. An update that changes none of
    /// them (an operation's place in the order of writing, a profile's place in the list) is this
    /// phone's own business and is not sent. Ids and profile ids never change.
    static let syncedColumns: [String: [String]] = [
        "profile": ["name", "incomeHourly", "hourlyRate", "monthlySalary", "taxPercent", "hoursPerWeek", "payday", "markup"],
        "account": [
            "name", "currency", "type", "groupName", "includeInFree", "sort", "interestRate", "paymentDay", "paymentMinor",
            "graceUntil", "reconciledAt",
        ],
        "operation": [
            "type", "timestamp", "categoryKey", "note", "voiceText", "purchaseAmountMinor", "purchaseCurrency", "isEstimate",
            "cbrFrom", "cbrTo",
        ],
        "posting": ["operationId", "accountId", "amountMinor", "rubMinor"],
        "obligation": ["name", "amountMinor", "currency", "dayOfMonth"],
        "goal": ["name", "targetMinor", "currency", "accountId", "savedMinor", "isMain"],
        "wish": ["title", "amountMinor", "currency", "createdAt", "decideAt", "status", "decidedAt"],
    ]

    static func v2(_ db: Database) throws {
        // Which rows a transaction changed, written by the triggers below and turned into queue
        // entries before the transaction commits (`SyncLedger.flush`), so it is always empty between
        // transactions. Triggers see what no Swift code would: rows a cascade took along.
        try db.create(table: "syncJournal") { t in
            t.column("tableName", .text).notNull()
            t.column("id", .blob).notNull()
            t.column("profileId", .blob).notNull()
            t.column("deleted", .boolean).notNull()
            t.primaryKey(["tableName", "id"])
        }
        // This install as the author of what it writes: a conflict between two equal times still
        // has one winner. Random, so it says nothing about the person or the phone.
        try db.create(table: "syncDevice") { t in
            t.primaryKey("id", .integer).check { $0 == 1 }
            t.column("name", .text).notNull()
        }
        try db.execute(sql: "INSERT INTO syncDevice (id, name) VALUES (1, lower(hex(randomblob(6))))")
        // The zone each profile lives in: own profiles in the private database (a profile with no
        // row is an own one not yet given to sync), shared ones under their owner's name.
        // [removing]: the profile was deleted or left here, and its zone is still to be deleted or
        // left on the server. No foreign key: the row outlives the profile until then.
        try db.create(table: "syncZone") { t in
            t.primaryKey("profileId", .blob)
            t.column("scope", .text).notNull()
            t.column("ownerName", .text).notNull()
            t.column("removing", .boolean).notNull().defaults(to: false)
        }
        // One entry per record (`OutgoingChange`), keyed by `SyncRecordRef.key`.
        try db.create(table: "syncOutgoing") { t in
            t.primaryKey("key", .text)
            t.column("profileId", .blob).notNull().indexed()
            t.column("change", .blob).notNull()
            t.column("revision", .integer).notNull()
        }
        // When each row of the books was last written and by which phone: the last writer wins.
        try db.create(table: "syncMeta") { t in
            t.column("tableName", .text).notNull()
            t.column("id", .blob).notNull()
            t.column("profileId", .blob).notNull().indexed()
            t.column("updatedAt", .integer).notNull()
            t.column("authorDevice", .text).notNull()
            t.primaryKey(["tableName", "id"])
        }
        // The server's system fields of each record it has seen (change tag included), so the
        // next save of the record is not taken for a conflicting one.
        try db.create(table: "syncSystemFields") { t in
            t.primaryKey("key", .text)
            t.column("profileId", .blob).notNull().indexed()
            t.column("data", .blob).notNull()
        }
        // `CKSyncEngine.State.Serialization` of each database, opaque here.
        try db.create(table: "syncEngineState") { t in
            t.primaryKey("scope", .text)
            t.column("data", .blob).notNull()
        }
        // Records that arrived but cannot be shown yet: an operation before all its postings
        // (`postingCount`), a posting before its account, anything before its profile.
        try db.create(table: "syncInbox") { t in
            t.primaryKey("key", .text)
            t.column("profileId", .blob).notNull().indexed()
            t.column("type", .text).notNull()
            t.column("operationId", .blob)
            t.column("record", .blob).notNull()
        }

        for (table, columns) in syncedColumns {
            let profileId = table == "profile" ? "id" : "profileId"
            func journal(_ row: String, deleted: Bool) -> String {
                "INSERT OR REPLACE INTO syncJournal (tableName, id, profileId, deleted) VALUES ('\(table)', \(row).id, \(row).\(profileId), \(deleted ? 1 : 0));"
            }
            let changed = columns.map { "OLD.\"\($0)\" IS NOT NEW.\"\($0)\"" }.joined(separator: " OR ")
            try db.execute(sql: """
                CREATE TRIGGER "syncJournal_\(table)_insert" AFTER INSERT ON "\(table)" BEGIN \(journal("NEW", deleted: false)) END;
                CREATE TRIGGER "syncJournal_\(table)_update" AFTER UPDATE ON "\(table)" WHEN \(changed) BEGIN \(journal("NEW", deleted: false)) END;
                CREATE TRIGGER "syncJournal_\(table)_delete" AFTER DELETE ON "\(table)" BEGIN \(journal("OLD", deleted: true)) END;
                """)
        }
    }
}
