import Foundation
import GRDB

// The tables, one migration per schema version. Ids are UUIDs stored as 16-byte blobs (GRDB's
// default), money is INTEGER minor units, rates are REAL, enums are their GoldaCore raw values.
// Every row except `rate` belongs to a profile and goes away with it.
enum Schema {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1", migrate: v1)
        // Sync (stage 5b): the queue, the journal the triggers fill, the zones, the inbox.
        migrator.registerMigration("v2", migrate: SyncSchema.v2)
        return migrator
    }

    private static func v1(_ db: Database) throws {
        try db.create(table: "profile") { t in
            t.primaryKey("id", .blob)
            t.column("name", .text).notNull()
            t.column("sort", .integer).notNull()
            t.column("incomeHourly", .boolean).notNull()
            t.column("hourlyRate", .double).notNull()
            t.column("monthlySalary", .double).notNull()
            t.column("taxPercent", .double).notNull()
            t.column("hoursPerWeek", .double).notNull()
            t.column("payday", .integer).notNull()
            t.column("markup", .double).notNull()
        }

        try db.create(table: "account") { t in
            t.primaryKey("id", .blob)
            t.column("profileId", .blob).notNull().references("profile", onDelete: .cascade)
            t.column("name", .text).notNull()
            t.column("currency", .text).notNull()
            t.column("type", .text).notNull()
            t.column("groupName", .text)
            t.column("includeInFree", .boolean).notNull()
            t.column("sort", .integer).notNull()
            t.column("interestRate", .double)
            t.column("paymentDay", .integer)
            t.column("paymentMinor", .integer)
            t.column("graceUntil", .integer)
            t.column("reconciledAt", .integer)
        }
        try db.create(index: "account_on_profileId_sort", on: "account", columns: ["profileId", "sort"])
        // The target of postings' (accountId, profileId) key: a posting may only touch an account of
        // its own profile, which is what keeps transfers inside one profile.
        try db.create(index: "account_on_id_profileId", on: "account", columns: ["id", "profileId"], unique: true)

        try db.create(table: "operation") { t in
            t.primaryKey("id", .blob)
            t.column("profileId", .blob).notNull().references("profile", onDelete: .cascade)
            t.column("type", .text).notNull()
            t.column("timestamp", .integer).notNull()
            t.column("categoryKey", .text)
            t.column("note", .text).notNull()
            t.column("voiceText", .text)
            t.column("purchaseAmountMinor", .integer)
            t.column("purchaseCurrency", .text)
            t.column("isEstimate", .boolean).notNull()
            t.column("cbrFrom", .double)
            t.column("cbrTo", .double)
            // Last writer wins when two devices edit the same operation.
            t.column("updatedAt", .integer).notNull()
            // Order of writing within the profile (1, 2, 3…): of operations with one timestamp the
            // last written is listed first, as Android's autoincrement ids did, and an undone delete
            // returns to its place. Unlike the rowid, nothing renumbers it.
            t.column("sequence", .integer).notNull()
        }
        try db.create(index: "operation_on_profileId_timestamp", on: "operation", columns: ["profileId", "timestamp"])
        try db.create(index: "operation_on_profileId_sequence", on: "operation", columns: ["profileId", "sequence"])
        try db.create(index: "operation_on_id_profileId", on: "operation", columns: ["id", "profileId"], unique: true)

        try db.create(table: "posting") { t in
            t.primaryKey("id", .blob)
            t.column("profileId", .blob).notNull().indexed().references("profile", onDelete: .cascade)
            t.column("operationId", .blob).notNull().indexed()
            t.column("accountId", .blob).notNull().indexed()
            t.column("amountMinor", .integer).notNull()
            t.column("rubMinor", .integer).notNull()
            t.foreignKey(["operationId", "profileId"], references: "operation", columns: ["id", "profileId"], onDelete: .cascade)
            t.foreignKey(["accountId", "profileId"], references: "account", columns: ["id", "profileId"], onDelete: .cascade)
        }

        try db.create(table: "obligation") { t in
            t.primaryKey("id", .blob)
            t.column("profileId", .blob).notNull().references("profile", onDelete: .cascade)
            t.column("name", .text).notNull()
            t.column("amountMinor", .integer).notNull()
            t.column("currency", .text).notNull()
            t.column("dayOfMonth", .integer).notNull()
            // Creation order within the profile: payments of one day are listed in it, as Android's
            // autoincrement ids listed them, and UUIDs cannot (O10).
            t.column("createdAt", .integer).notNull()
        }
        try db.create(
            index: "obligation_on_profileId_dayOfMonth_createdAt", on: "obligation",
            columns: ["profileId", "dayOfMonth", "createdAt"]
        )

        try db.create(table: "goal") { t in
            t.primaryKey("id", .blob)
            t.column("profileId", .blob).notNull().indexed().references("profile", onDelete: .cascade)
            t.column("name", .text).notNull()
            t.column("targetMinor", .integer).notNull()
            t.column("currency", .text).notNull()
            // No foreign key, as on Android: a goal outlives its account and simply loses the link.
            t.column("accountId", .blob)
            t.column("savedMinor", .integer).notNull()
            t.column("isMain", .boolean).notNull()
            // Creation order within the profile: Android's autoincrement id told which goal is the
            // oldest (it becomes main when none is), and UUIDs do not (D27).
            t.column("createdAt", .integer).notNull()
        }

        try db.create(table: "wish") { t in
            t.primaryKey("id", .blob)
            t.column("profileId", .blob).notNull().references("profile", onDelete: .cascade)
            t.column("title", .text).notNull()
            t.column("amountMinor", .integer).notNull()
            t.column("currency", .text).notNull()
            t.column("createdAt", .integer).notNull()
            t.column("decideAt", .integer).notNull()
            t.column("status", .text).notNull()
            t.column("decidedAt", .integer)
        }
        try db.create(index: "wish_on_profileId_status_decideAt", on: "wish", columns: ["profileId", "status", "decideAt"])

        // Official CBR rates are the same for everyone, so they belong to no profile and never sync.
        try db.create(table: "rate") { t in
            t.primaryKey("code", .text)
            t.column("rubPerUnit", .double).notNull()
            t.column("date", .text).notNull()
        }
    }
}
