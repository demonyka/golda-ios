import Foundation
import GoldaCore
import GRDB
import Testing

@testable import GoldaData

@Suite struct SchemaTests {
    @Test func migrationCreatesEveryTable() async throws {
        let database = try GoldaDatabase.inMemory()
        let tables = ["profile", "account", "operation", "posting", "obligation", "goal", "wish", "rate"]
        let existing = try await database.writer.read { db in try tables.filter { try db.tableExists($0) } }
        #expect(existing == tables)
        let applied = try await database.writer.read { db in try Schema.migrator.appliedMigrations(db) }
        #expect(applied == ["v1"])
    }

    @Test func foreignKeysAreOn() async throws {
        let database = try GoldaDatabase.inMemory()
        let enabled = try await database.writer.read { db in try Bool.fetchOne(db, sql: "PRAGMA foreign_keys") }
        #expect(enabled == true)
    }

    @Test func everyTableButRateBelongsToAProfile() async throws {
        let database = try GoldaDatabase.inMemory()
        let owners = try await database.writer.read { db in
            try ["account", "operation", "posting", "obligation", "goal", "wish", "rate"].map { table in
                try db.foreignKeys(on: table).contains { $0.destinationTable == "profile" && $0.originColumns == ["profileId"] }
            }
        }
        #expect(owners == [true, true, true, true, true, true, false])
    }

    /// Android's autoincrement ids told the creation order of goals and payments; UUIDs do not, so a
    /// counter is stored, always (D27, O10).
    @Test func goalsAndPaymentsHoldTheirCreationOrder() async throws {
        let database = try await StoreFixture.database(profiles: 1)
        let schema = try await database.writer.read { db in
            try ["obligation", "goal"].map { table in
                try db.columns(in: table).first { $0.name == "createdAt" }.map { "\(table) \($0.type) \($0.isNotNull)" }
            }
        }
        #expect(schema == ["obligation INTEGER true", "goal INTEGER true"])
        // One day's payments are listed in creation order straight from the index.
        let index = try await database.writer.read { db in
            try db.indexes(on: "obligation").first { $0.name == "obligation_on_profileId_dayOfMonth_createdAt" }?.columns
        }
        #expect(index == ["profileId", "dayOfMonth", "createdAt"])

        // A record that skips the store and its counter cannot be written.
        let profileId = StoreFixture.id(1)
        let payment = Obligation(id: StoreFixture.id(40), name: "Аренда", amountMinor: 1, currency: "RUB", dayOfMonth: 1)
        let goal = Goal(id: StoreFixture.id(50), name: "Машина", targetMinor: 1, currency: "RUB")
        await #expect(throws: DatabaseError.self) {
            try await database.writer.write { db in try ObligationRecord(payment, profileId: profileId).insert(db) }
        }
        await #expect(throws: DatabaseError.self) {
            try await database.writer.write { db in try GoalRecord(goal, profileId: profileId).insert(db) }
        }
    }

    @Test func idsAreSixteenByteBlobsAndEnumsTheirAndroidNames() async throws {
        let database = try await StoreFixture.database(profiles: 1)
        let profileId = StoreFixture.id(1)
        try await database.write { store in
            var account = StoreFixture.account(10)
            account.type = .credit
            try store.save(account, profileId: profileId)
            try store.book(StoreFixture.operation(20, type: .transfer), [], profileId: profileId)
            try store.save(
                Wish(id: StoreFixture.id(30), title: "Наушники", amountMinor: 1, currency: "RUB", createdAt: 0, decideAt: 0, status: .skipped),
                profileId: profileId
            )
        }
        let stored = try await database.writer.read { db in
            [
                try String.fetchOne(db, sql: "SELECT typeof(id) || ' ' || length(id) FROM account"),
                try String.fetchOne(db, sql: "SELECT typeof(profileId) || ' ' || length(profileId) FROM operation"),
                try String.fetchOne(db, sql: "SELECT type FROM account"),
                try String.fetchOne(db, sql: "SELECT type FROM operation"),
                try String.fetchOne(db, sql: "SELECT status FROM wish"),
            ]
        }
        #expect(stored == ["blob 16", "blob 16", "CREDIT", "TRANSFER", "SKIPPED"])
    }

    @Test func fileDatabaseUsesWALAndKeepsDataAcrossOpens() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("nested/golda.sqlite")

        let first = try GoldaDatabase.open(at: url)
        try await first.write { try $0.save(StoreFixture.profile(1)) }
        let mode = try await first.writer.read { db in try String.fetchOne(db, sql: "PRAGMA journal_mode") }
        #expect(mode == "wal")

        let reopened = try GoldaDatabase.open(at: url)
        let profiles = try await reopened.read { try $0.profiles() }
        #expect(profiles == [StoreFixture.profile(1)])

        // The development flag erases a changed schema only, never a current one.
        let development = try GoldaDatabase.open(at: url, eraseDatabaseOnSchemaChange: true)
        #expect(try await development.read { try $0.profiles() } == [StoreFixture.profile(1)])
    }

    // MARK: A schema edited in place

    /// A file from a build before v1 gained the payments' `createdAt`: the old shape of the table,
    /// v1 recorded as applied, and a profile in it. Returns its URL once it is closed.
    private func staleDatabase() async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "golda-stale-\(UUID().uuidString)/golda.sqlite")
        let database = try GoldaDatabase.open(at: url)
        try await database.write { try $0.save(StoreFixture.profile(1)) }
        try await database.writer.write { db in
            try db.drop(index: "obligation_on_profileId_dayOfMonth_createdAt")
            try db.alter(table: "obligation") { t in t.drop(column: "createdAt") }
        }
        return url
    }

    /// Without the flag (release builds, and debug builds on a real iPhone) the file is the user's:
    /// nothing is touched, and what no longer fits fails loudly, as a read and as a stream, rather
    /// than leaving the app waiting.
    @Test func aStaleSchemaIsLeftAloneAndFailsLoudly() async throws {
        let url = try await staleDatabase()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let database = try GoldaDatabase.open(at: url)

        #expect(try await database.read { try $0.profiles() } == [StoreFixture.profile(1)])
        let columns = try await database.writer.read { db in try db.columns(in: "obligation").map(\.name) }
        #expect(!columns.contains("createdAt"))
        let error = await #expect(throws: DatabaseError.self) {
            try await database.read { try $0.snapshot(profileId: StoreFixture.id(1)) }
        }
        #expect(error?.message?.contains("createdAt") == true, "\(String(describing: error))")
        var snapshots = database.snapshots(profileId: StoreFixture.id(1)).makeAsyncIterator()
        await #expect(throws: DatabaseError.self) { _ = try await snapshots.next() }
    }

    /// With the flag (debug builds in the simulator) the stale file is wiped and built afresh:
    /// empty, on the current schema, and working.
    @Test func aStaleSchemaIsErasedAndRebuiltWhenAsked() async throws {
        let url = try await staleDatabase()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let database = try GoldaDatabase.open(at: url, eraseDatabaseOnSchemaChange: true)

        #expect(try await database.read { try $0.profiles() }.isEmpty)
        let schema = try await database.writer.read { db in
            (try db.columns(in: "obligation").map(\.name), try Schema.migrator.appliedMigrations(db))
        }
        #expect(schema.0.contains("createdAt"))
        #expect(schema.1 == ["v1"])
        let profileId = StoreFixture.id(1)
        try await database.write { store in
            try store.save(StoreFixture.profile(1))
            try store.save(Obligation(name: "Аренда", amountMinor: 1, currency: "RUB", dayOfMonth: 1), profileId: profileId)
        }
        let snapshot = try #require(try await database.read { try $0.snapshot(profileId: profileId) })
        #expect(snapshot.obligations.map(\.name) == ["Аренда"])
    }
}
