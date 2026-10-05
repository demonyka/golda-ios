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
            "graceUntil", "reconciledAt", "creditLimitMinor",
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
        // Records that arrived but cannot be shown yet: an operation before its accounts, anything
        // before its profile. [operationId] served postings sent apart, which `v3` ended; unused.
        try db.create(table: "syncInbox") { t in
            t.primaryKey("key", .text)
            t.column("profileId", .blob).notNull().indexed()
            t.column("type", .text).notNull()
            t.column("operationId", .blob)
            t.column("record", .blob).notNull()
        }

        for (table, columns) in syncedColumns {
            // The columns as they were then: a later migration that adds one adds it here too.
            let columns = columns.filter { !(table == "account" && $0 == "creditLimitMinor") }
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

    /// Postings travel inside their operation's record (D58): with records of their own, last
    /// writer won per posting, and two phones editing one operation could leave a transfer with
    /// one leg. So a change of a posting journals its operation, which goes again whole and stamped
    /// now. `OR IGNORE`: when the operation itself is deleted in the same transaction (its postings
    /// go by cascade, before or after its own trigger), the operation's delete stands.
    ///
    /// What the first 5b builds left goes: postings' queue entries, fields and stamps, and inbox
    /// records in the old shape, which this version cannot read. Every operation of a profile sync
    /// knows is sent again in the new shape; the other phones do the same once they update.
    static func v3(_ db: Database) throws {
        let columns = syncedColumns["posting"] ?? []
        let changed = columns.map { "OLD.\"\($0)\" IS NOT NEW.\"\($0)\"" }.joined(separator: " OR ")
        func journal(_ row: String) -> String {
            "INSERT OR IGNORE INTO syncJournal (tableName, id, profileId, deleted) VALUES ('operation', \(row).operationId, \(row).profileId, 0);"
        }
        try db.execute(sql: """
            DROP TRIGGER "syncJournal_posting_insert";
            DROP TRIGGER "syncJournal_posting_update";
            DROP TRIGGER "syncJournal_posting_delete";
            CREATE TRIGGER "syncJournal_posting_insert" AFTER INSERT ON "posting" BEGIN \(journal("NEW")) END;
            CREATE TRIGGER "syncJournal_posting_update" AFTER UPDATE ON "posting" WHEN \(changed) BEGIN \(journal("NEW")) \(journal("OLD")) END;
            CREATE TRIGGER "syncJournal_posting_delete" AFTER DELETE ON "posting" BEGIN \(journal("OLD")) END;
            DELETE FROM syncOutgoing WHERE key LIKE '%|Posting.%';
            DELETE FROM syncSystemFields WHERE key LIKE '%|Posting.%';
            DELETE FROM syncInbox WHERE type IN ('Operation', 'Posting');
            DELETE FROM syncMeta WHERE tableName = 'posting';
            DELETE FROM syncJournal;
            """)
        let operations = try Row.fetchAll(db, sql: """
            SELECT operation.id, operation.profileId FROM operation
            JOIN syncZone ON syncZone.profileId = operation.profileId AND syncZone.removing = 0
            ORDER BY operation.rowid
            """)
        for row in operations {
            let profileId: UUID = row["profileId"]
            guard let zone = try SyncLedger.zoneRow(profileId, db)?.zone else { continue }
            try SyncLedger.enqueue(.save, SyncRecordRef(zone: zone, type: .operation, id: row["id"]), profileId: profileId, now: 0, db)
        }
    }

    /// A credit card's limit (1.0.1, D62): a column of its own, and the account's update trigger
    /// made again with it, so a new limit alone goes to the other phones. Nothing is sent again:
    /// no account has a limit yet.
    static func v4(_ db: Database) throws {
        try db.alter(table: "account") { t in t.add(column: "creditLimitMinor", .integer) }
        let changed = (syncedColumns["account"] ?? []).map { "OLD.\"\($0)\" IS NOT NEW.\"\($0)\"" }.joined(separator: " OR ")
        try db.execute(sql: """
            DROP TRIGGER "syncJournal_account_update";
            CREATE TRIGGER "syncJournal_account_update" AFTER UPDATE ON "account" WHEN \(changed) BEGIN INSERT OR REPLACE INTO syncJournal (tableName, id, profileId, deleted) VALUES ('account', NEW.id, NEW.profileId, 0); END;
            """)
    }
}
