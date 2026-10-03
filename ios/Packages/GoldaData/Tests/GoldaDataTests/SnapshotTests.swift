import Foundation
import GoldaCore
import Testing

@testable import GoldaData

/// Snapshots keep Android's orders, and observations follow writes to their own profile only.
@Suite(.timeLimit(.minutes(1))) struct SnapshotTests {
    let personal = StoreFixture.id(1)
    let family = StoreFixture.id(2)

    @Test func snapshotKeepsAndroidOrders() async throws {
        let database = try await StoreFixture.database(profiles: 1)
        try await database.write { store in
            for (n, sort) in [(12, 1), (11, 0), (10, 1)] { try store.save(StoreFixture.account(n, sort: sort), profileId: personal) }

            // Two notes from one voice message share a timestamp; the later one is listed first.
            try store.book(StoreFixture.operation(22, timestamp: 1_000), [], profileId: personal)
            try store.book(StoreFixture.operation(20, timestamp: 2_000), [], profileId: personal)
            try store.book(StoreFixture.operation(21, timestamp: 1_000), [], profileId: personal)
            // A transfer's postings come back in the order the ledger made them, whatever their ids.
            try store.book(
                StoreFixture.operation(23, type: .transfer, timestamp: 500),
                [StoreFixture.posting(39, operation: 23, account: 10, amount: -100), StoreFixture.posting(38, operation: 23, account: 11, amount: 100)],
                profileId: personal
            )

            for (n, day) in [(42, 5), (41, 1), (40, 5)] {
                try store.save(Obligation(id: StoreFixture.id(n), name: "", amountMinor: 1, currency: "RUB", dayOfMonth: day), profileId: personal)
            }
            for (n, isMain) in [(52, false), (51, false), (53, true)] {
                try store.save(Goal(id: StoreFixture.id(n), name: "", targetMinor: 1, currency: "RUB", isMain: isMain), profileId: personal)
            }
            let wishes: [(Int, WishStatus, Int64)] = [(60, .waiting, 1), (61, .bought, 1), (62, .waiting, 2), (63, .skipped, 9)]
            for (n, status, decideAt) in wishes {
                try store.save(
                    Wish(id: StoreFixture.id(n), title: "", amountMinor: 1, currency: "RUB", createdAt: 0, decideAt: decideAt, status: status),
                    profileId: personal
                )
            }
        }

        let snapshot = try #require(try await database.read { try $0.snapshot(profileId: personal) })
        #expect(snapshot.accounts.map(\.id) == [11, 10, 12].map(StoreFixture.id))
        #expect(snapshot.operations.map(\.op.id) == [20, 21, 22, 23].map(StoreFixture.id))
        #expect(snapshot.operations.last?.postings.map(\.id) == [39, 38].map(StoreFixture.id))
        // By day, then payments of one day in the order they were created, whatever their ids (O10).
        #expect(snapshot.obligations.map(\.id) == [41, 42, 40].map(StoreFixture.id))
        // The main goal, then the others in the order they were created, whatever their ids.
        #expect(snapshot.goals.map(\.id) == [53, 52, 51].map(StoreFixture.id))
        // BOUGHT < SKIPPED < WAITING, as Room sorted the enum names.
        #expect(snapshot.wishes.map(\.id) == [61, 63, 62, 60].map(StoreFixture.id))
    }

    @Test func profilesComeBySort() async throws {
        let database = try GoldaDatabase.inMemory()
        try await database.write { store in
            try store.save(StoreFixture.profile(3, name: "Компания", sort: 2))
            try store.save(StoreFixture.profile(1, name: "Личный", sort: 0))
            try store.save(StoreFixture.profile(2, name: "Семья", sort: 1))
        }
        #expect(try await database.read { try $0.profiles() }.map(\.name) == ["Личный", "Семья", "Компания"])
    }

    @Test func snapshotsFollowWrites() async throws {
        let database = try await StoreFixture.database(profiles: 1)
        var snapshots = database.snapshots(profileId: personal).makeAsyncIterator()
        let initial = try #require(await snapshots.next())
        #expect(initial.profile.id == personal)
        #expect(initial.accounts.isEmpty && initial.operations.isEmpty)

        try await database.write { store in
            try store.save(StoreFixture.account(10), profileId: personal)
            try store.book(StoreFixture.operation(20), [StoreFixture.posting(30, operation: 20, account: 10, amount: -500)], profileId: personal)
        }
        let next = try #require(await snapshots.next())
        #expect(next.accounts == [StoreFixture.account(10)])
        #expect(next.operations == [OperationFull(StoreFixture.operation(20), [StoreFixture.posting(30, operation: 20, account: 10, amount: -500)])])
    }

    @Test func anotherProfilesWritesNeverReachTheSnapshot() async throws {
        let database = try await StoreFixture.database(profiles: 1, 2)
        var snapshots = database.snapshots(profileId: personal).makeAsyncIterator()
        let initial = try #require(await snapshots.next())

        try await database.write { store in
            try store.save(StoreFixture.account(12), profileId: family)
            try store.book(StoreFixture.operation(22, type: .income), [StoreFixture.posting(32, operation: 22, account: 12, amount: 700)], profileId: family)
            try store.save(Goal(id: StoreFixture.id(52), name: "", targetMinor: 1, currency: "RUB"), profileId: family)
        }
        try await database.write { try $0.save(StoreFixture.account(10), profileId: personal) }

        // The family write changed nothing here, so the next snapshot is the personal write.
        let next = try #require(await snapshots.next())
        #expect(next.accounts.map(\.id) == [StoreFixture.id(10)])
        #expect(next.operations.isEmpty && next.goals.isEmpty)
        #expect(next.profile == initial.profile)

        let familyBooks = try #require(try await database.read { try $0.snapshot(profileId: family) })
        #expect(familyBooks.accounts.map(\.id) == [StoreFixture.id(12)])
        #expect(familyBooks.operations.map(\.op.id) == [StoreFixture.id(22)])
    }

    @Test func snapshotsEndWhenTheProfileIsDeleted() async throws {
        let database = try await StoreFixture.database(profiles: 1)
        var snapshots = database.snapshots(profileId: personal).makeAsyncIterator()
        _ = try #require(await snapshots.next())
        try await database.write { try $0.deleteProfile(personal) }
        #expect(await snapshots.next() == nil)
    }

    @Test func ratesFollowWrites() async throws {
        let database = try await StoreFixture.database(profiles: 1)
        var rates = database.rates().makeAsyncIterator()
        #expect(await rates.next() == [])

        let usd = RateRecord(code: "USD", rubPerUnit: 83.2454, date: "2026-10-02")
        let gel = RateRecord(code: "GEL", rubPerUnit: 31.9597, date: "2026-10-02")
        try await database.write { try $0.save([usd, gel]) }
        #expect(await rates.next() == [gel, usd])

        // A write to the books leaves the rates as they were, so the next value is the next refresh.
        try await database.write { try $0.save(StoreFixture.account(10), profileId: personal) }
        let fresh = RateRecord(code: "USD", rubPerUnit: 83.4839, date: "2026-10-03")
        try await database.write { try $0.save([fresh]) }
        #expect(await rates.next() == [gel, fresh])
    }

    @Test func profilesFollowWrites() async throws {
        let database = try GoldaDatabase.inMemory()
        var profiles = database.profiles().makeAsyncIterator()
        #expect(await profiles.next() == [])

        try await database.write { try $0.save(StoreFixture.profile(1)) }
        #expect(await profiles.next() == [StoreFixture.profile(1)])

        let renamed = StoreFixture.profile(1, name: "Семья")
        try await database.write { try $0.save(renamed) }
        #expect(await profiles.next() == [renamed])
    }
}
