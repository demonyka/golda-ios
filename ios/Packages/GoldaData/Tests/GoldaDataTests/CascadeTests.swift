import Foundation
import GoldaCore
import GRDB
import Testing

@testable import GoldaData

/// What goes away with what, and what never crosses from one profile into another.
@Suite struct CascadeTests {
    let personal = StoreFixture.id(1)
    let family = StoreFixture.id(2)

    /// Profile 1: a ruble card (10), a dollar card (11), an expense (20) on 10 and a transfer (21)
    /// from 10 to 11, an obligation, a goal and a wish. Profile 2: one account (12) with an income (22).
    func books() async throws -> GoldaDatabase {
        let database = try await StoreFixture.database(profiles: 1, 2)
        try await database.write { store in
            try store.save(StoreFixture.account(10), profileId: personal)
            try store.save(StoreFixture.account(11, currency: "USD", sort: 1), profileId: personal)
            try store.book(StoreFixture.operation(20), [StoreFixture.posting(30, operation: 20, account: 10, amount: -500)], profileId: personal)
            try store.book(
                StoreFixture.operation(21, type: .transfer, timestamp: 2_000),
                [
                    StoreFixture.posting(31, operation: 21, account: 10, amount: -9_000),
                    StoreFixture.posting(32, operation: 21, account: 11, amount: 100),
                ],
                profileId: personal
            )
            try store.save(Obligation(id: StoreFixture.id(40), name: "Аренда", amountMinor: 1, currency: "RUB", dayOfMonth: 5), profileId: personal)
            try store.save(Goal(id: StoreFixture.id(50), name: "Отпуск", targetMinor: 1, currency: "RUB"), profileId: personal)
            try store.save(Wish(id: StoreFixture.id(60), title: "Книга", amountMinor: 1, currency: "RUB", createdAt: 0, decideAt: 0), profileId: personal)
            try store.save(CustomCategory(id: StoreFixture.id(70), name: "Кот", kind: .expense), profileId: personal)

            try store.save(StoreFixture.account(12), profileId: family)
            try store.book(StoreFixture.operation(22, type: .income), [StoreFixture.posting(33, operation: 22, account: 12, amount: 700)], profileId: family)
            try store.save([RateRecord(code: "USD", rubPerUnit: 83.2454, date: "2026-10-02")])
        }
        return database
    }

    @Test func deletingAProfileErasesOnlyItsBooks() async throws {
        let database = try await books()
        let familyBefore = try await database.read { try $0.snapshot(profileId: family) }

        let deleted = try await database.write { try $0.deleteProfile(personal) }
        #expect(deleted)

        let rowsLeft = try await database.writer.read { db in
            try ["account", "operation", "posting", "obligation", "goal", "wish", "category"].map { table in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table) WHERE profileId = ?", arguments: [StoreFixture.id(1)])
            }
        }
        #expect(rowsLeft == [0, 0, 0, 0, 0, 0, 0])
        #expect(try await database.read { try $0.snapshot(profileId: personal) } == nil)
        #expect(try await database.read { try $0.snapshot(profileId: family) } == familyBefore)
        #expect(try await database.read { try $0.rates().count } == 1)
    }

    @Test func deletingAnOperationTakesItsPostings() async throws {
        let database = try await books()
        try await database.write { try $0.deleteOperation(StoreFixture.id(21), profileId: personal) }
        let postings = try await database.read { try $0.postings(profileId: personal) }
        #expect(postings.map(\.id) == [StoreFixture.id(30)])
    }

    @Test func deletingAnAccountTakesOnlyItsPostings() async throws {
        let database = try await books()
        try await database.write { try $0.deleteAccount(StoreFixture.id(11), profileId: personal) }
        let operations = try await database.read { try $0.operations(profileId: personal) }
        // The operations stay; the transfer keeps its ruble side.
        #expect(operations.map(\.op.id) == [StoreFixture.id(21), StoreFixture.id(20)])
        #expect(operations.flatMap(\.postings).map(\.id) == [StoreFixture.id(31), StoreFixture.id(30)])
    }

    @Test func deletingOperationsTouchingAnAccountTakesWholeTransfers() async throws {
        let database = try await books()
        let deleted = try await database.write { store in
            try store.deleteOperations(touching: StoreFixture.id(11), profileId: personal)
        }
        #expect(deleted == 1)
        let snapshot = try #require(try await database.read { try $0.snapshot(profileId: personal) })
        #expect(snapshot.operations.map(\.op.id) == [StoreFixture.id(20)])
        #expect(snapshot.accounts.count == 2)

        // Another profile's id finds nothing to delete.
        let foreign = try await database.write { try $0.deleteOperations(touching: StoreFixture.id(10), profileId: family) }
        #expect(foreign == 0)
    }

    @Test func rowsAreInvisibleFromAnotherProfile() async throws {
        let database = try await books()
        let seen = try await database.read { store in
            (
                try store.account(StoreFixture.id(10), profileId: family),
                try store.operation(StoreFixture.id(20), profileId: family),
                try store.obligation(StoreFixture.id(40), profileId: family),
                try store.goal(StoreFixture.id(50), profileId: family),
                try store.wish(StoreFixture.id(60), profileId: family)
            )
        }
        #expect(seen.0 == nil && seen.1 == nil && seen.2 == nil && seen.3 == nil && seen.4 == nil)

        let deleted = try await database.write { store in
            [
                try store.deleteAccount(StoreFixture.id(10), profileId: family),
                try store.deleteOperation(StoreFixture.id(20), profileId: family),
                try store.deletePosting(StoreFixture.id(30), profileId: family),
                try store.deleteObligation(StoreFixture.id(40), profileId: family),
                try store.deleteGoal(StoreFixture.id(50), profileId: family),
                try store.deleteWish(StoreFixture.id(60), profileId: family),
            ]
        }
        #expect(deleted == [false, false, false, false, false, false])
        let snapshot = try #require(try await database.read { try $0.snapshot(profileId: personal) })
        #expect(snapshot.accounts.count == 2 && snapshot.operations.count == 2)
        #expect(snapshot.obligations.count == 1 && snapshot.goals.count == 1 && snapshot.wishes.count == 1)
    }

    @Test func savingARowOfAnotherProfileFailsAndChangesNothing() async throws {
        let database = try await books()
        await #expect(throws: StoreError.belongsToAnotherProfile(StoreFixture.id(10))) {
            try await database.write { store in
                var stolen = StoreFixture.account(10)
                stolen.name = "Чужой"
                try store.save(stolen, profileId: family)
            }
        }
        let account = try await database.read { try $0.account(StoreFixture.id(10), profileId: personal) }
        #expect(account == StoreFixture.account(10))
    }

    @Test func aPostingCannotTouchAnotherProfilesAccountOrOperation() async throws {
        let database = try await books()
        // A transfer into profile 2's account from profile 1's operation.
        await #expect(throws: DatabaseError.self) {
            try await database.write {
                try $0.save(StoreFixture.posting(34, operation: 21, account: 12, amount: 1), profileId: personal)
            }
        }
        // Profile 2 hanging a posting on profile 1's operation.
        await #expect(throws: DatabaseError.self) {
            try await database.write {
                try $0.save(StoreFixture.posting(35, operation: 21, account: 12, amount: 1), profileId: family)
            }
        }
    }

    @Test func aFailedWriteLeavesNothingBehind() async throws {
        let database = try await books()
        await #expect(throws: DatabaseError.self) {
            try await database.write { store in
                try store.book(
                    StoreFixture.operation(23),
                    [StoreFixture.posting(36, operation: 23, account: 99, amount: -1)], // no account 99
                    profileId: personal
                )
            }
        }
        #expect(try await database.read { try $0.operation(StoreFixture.id(23), profileId: personal) } == nil)
    }
}
