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
            try store.save(card, profileId: profile.id)
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
}
