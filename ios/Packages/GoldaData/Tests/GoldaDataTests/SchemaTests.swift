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
    }
}
