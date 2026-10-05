import Foundation
import GoldaCore
import GRDB
import Testing

@testable import GoldaData

/// The first 5b builds sent postings as records of their own; `v3` makes them part of their
/// operation's record. A file written by those builds must open and send its operations again.
@Suite struct SyncMigrationTests {
    @Test func aFileOfTheFirstSyncBuildsSendsItsOperationsAgainWithTheirPostings() async throws {
        let queue = try DatabaseQueue(configuration: {
            var configuration = Configuration()
            configuration.foreignKeysEnabled = true
            return configuration
        }())
        try Schema.migrator.migrate(queue, upTo: "v2")

        let profile = Profile(name: "Семья")
        let card = Account.card("Карта")
        let operation = GoldaCore.Operation(type: .expense, timestamp: 1)
        let posting = Posting(operationId: operation.id, accountId: card.id, amountMinor: -100, rubMinor: -100)
        let zone = SyncZone.own(profile.id)
        let operationRef = SyncRecordRef(zone: zone, type: .operation, id: operation.id)
        try await queue.write { db in
            let store = Store(db: db)
            try store.save(profile)
            // In the columns of then: the account's record writes the ones later versions added.
            try db.execute(
                sql: "INSERT INTO account (id, profileId, name, currency, type, includeInFree, sort) VALUES (?, ?, ?, ?, ?, ?, 0)",
                arguments: [card.id, profile.id, card.name, card.currency, card.type.rawValue, card.includeInFree]
            )
            try store.save(operation, profileId: profile.id, updatedAt: 1)
            try store.save(posting, profileId: profile.id)
            try db.execute(sql: "DELETE FROM syncJournal")
            try SyncLedger.putZone(zone, db)
            // What those builds left: a posting's own queue entry and fields, records in the
            // inbox in the old shape.
            let entry = String(decoding: try SyncLedger.encoder.encode(OutgoingChange(ref: operationRef, kind: .save, revision: 1, notBefore: 0)), as: UTF8.self)
                .replacingOccurrences(of: "\"Operation\"", with: "\"Posting\"")
            let postingKey = "\(zone.key)|Posting.\(posting.id.uuidString.lowercased())"
            try db.execute(
                sql: "INSERT INTO syncOutgoing (key, profileId, change, revision) VALUES (?, ?, ?, 1)",
                arguments: [postingKey, profile.id, Data(entry.utf8)]
            )
            try db.execute(sql: "INSERT INTO syncSystemFields (key, profileId, data) VALUES (?, ?, ?)", arguments: [postingKey, profile.id, Data([1])])
            for type in ["Operation", "Posting"] {
                try db.execute(
                    sql: "INSERT INTO syncInbox (key, profileId, type, record) VALUES (?, ?, ?, ?)",
                    arguments: ["\(zone.key)|\(type).x", profile.id, type, Data("{\"postingCount\":1}".utf8)]
                )
            }
        }

        let sync = SyncStore(database: try GoldaDatabase(queue, clock: nil))
        #expect(try await sync.outgoing().map(\.ref) == [operationRef])
        #expect(try await sync.waitingCount() == 0)
        guard case .operation(_, let postings)? = try await sync.record(operationRef)?.payload else {
            Issue.record("not an operation")
            return
        }
        #expect(postings == [posting])
        let legacyFields = try await queue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM syncSystemFields") }
        #expect(legacyFields == 0)
    }

    /// 1.0.1 adds a credit card's limit (`v4`, D62): a file of 1.0.0 opens with no limit on its
    /// accounts, and a limit set later goes to the other phones like any other change.
    @Test func aFileOfOneZeroZeroGetsTheLimitColumnAndSendsALimitSetLater() async throws {
        let queue = try DatabaseQueue(configuration: {
            var configuration = Configuration()
            configuration.foreignKeysEnabled = true
            return configuration
        }())
        try Schema.migrator.migrate(queue, upTo: "v3")
        let profile = Profile(name: "Личный")
        let card = Account(name: "Кредитка", currency: "RUB", type: .credit, includeInFree: false)
        try await queue.write { db in
            try db.execute(
                sql: "INSERT INTO profile (id, name, sort, incomeHourly, hourlyRate, monthlySalary, taxPercent, hoursPerWeek, payday, markup) VALUES (?, ?, 0, 0, 0, 0, 0, 40, 1, 0)",
                arguments: [profile.id, profile.name]
            )
            try db.execute(
                sql: "INSERT INTO account (id, profileId, name, currency, type, includeInFree, sort) VALUES (?, ?, ?, 'RUB', 'CREDIT', 0, 0)",
                arguments: [card.id, profile.id, card.name]
            )
            try SyncLedger.putZone(.own(profile.id), db)
            try db.execute(sql: "DELETE FROM syncJournal")
        }

        let database = try GoldaDatabase(queue, clock: nil)
        let sync = SyncStore(database: database)
        #expect(try await database.read { try $0.account(card.id, profileId: profile.id) } == card)
        let limited = Account(id: card.id, name: card.name, currency: "RUB", type: .credit, includeInFree: false, creditLimitMinor: 15_000_000)
        try await database.write { try $0.save(limited, profileId: profile.id) }
        #expect(try await sync.outgoing().map(\.ref) == [SyncRecordRef(zone: .own(profile.id), type: .account, id: card.id)])
        #expect(try await database.read { try $0.account(card.id, profileId: profile.id) } == limited)
    }
}
