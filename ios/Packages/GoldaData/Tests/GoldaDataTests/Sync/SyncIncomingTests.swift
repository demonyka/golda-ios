import Foundation
import GoldaCore
import GRDB
import Testing

@testable import GoldaData

/// Records from the server go into the books whole, the last writer winning, and are not sent back.
@Suite struct SyncIncomingTests {
    private let harness: RepositoryHarness
    private let sync: SyncStore
    private let shared = SyncZone(profileId: UUID(), ownerName: "_alice", scope: .shared)
    private let card = Account.card("Общая карта")
    private let cash = Account.card("Наличные", sort: 1)

    init() throws {
        harness = try RepositoryHarness()
        sync = SyncStore(database: harness.database)
    }

    private var now: Int64 { harness.clock.now }

    private func books() async throws -> ProfileSnapshot? {
        try await harness.database.read { [shared] in try $0.snapshot(profileId: shared.profileId) }
    }

    private func receiveTheProfile() async throws {
        try await sync.apply(SyncFixture.profile("Семья", account: card, zone: shared, at: now) + [
            SyncFixture.record(.account(cash), zone: shared, at: now),
        ])
    }

    @Test func aSharedProfileArrivesInItsOwnersZoneAndIsNotSentBack() async throws {
        try await receiveTheProfile()
        let books = try #require(try await books())
        #expect(books.profile.name == "Семья")
        #expect(books.accounts.map(\.name) == ["Общая карта", "Наличные"])
        #expect(try await sync.zones()[shared.profileId] == shared)
        #expect(try await sync.outgoing().isEmpty)
    }

    @Test func aNewProfileComesAfterThePhonesOwnInTheList() async throws {
        let own = try await harness.profile()
        try await receiveTheProfile()
        let profiles = try await harness.database.read { try $0.profiles() }
        #expect(profiles.map(\.id) == [own, shared.profileId])
    }

    @Test func nothingStandsBeforeItsProfile() async throws {
        try await sync.apply([SyncFixture.record(.account(card), zone: shared, at: now)])
        #expect(try await books() == nil)
        #expect(try await sync.waitingCount() == 1)
        try await sync.apply([SyncFixture.record(.profile(Profile(id: shared.profileId, name: "Семья")), zone: shared, at: now)])
        #expect(try await books()?.accounts.map(\.name) == ["Общая карта"])
        #expect(try await sync.waitingCount() == 0)
    }

    @Test func anOperationShowsOnlyWithAllItsPostings() async throws {
        try await receiveTheProfile()
        let transfer = SyncFixture.transfer(5_000, from: card.id, to: cash.id, zone: shared, at: now)

        try await sync.apply([transfer.header, transfer.out])
        #expect(try await books()?.operations.isEmpty == true, "half a transfer is not shown")

        try await sync.apply([transfer.into])
        let operations = try #require(try await books()).operations
        #expect(operations.count == 1)
        // Money out first, as the ledger writes a transfer.
        #expect(operations[0].postings.map(\.amountMinor) == [-5_000, 5_000])
    }

    @Test func postingsMayComeBeforeTheirHeader() async throws {
        try await receiveTheProfile()
        let transfer = SyncFixture.transfer(700, from: card.id, to: cash.id, zone: shared, at: now)
        try await sync.apply([transfer.into, transfer.out])
        #expect(try await books()?.operations.isEmpty == true)
        try await sync.apply([transfer.header])
        #expect(try await books()?.operations.first?.postings.count == 2)
    }

    @Test func aPostingWaitsForItsAccount() async throws {
        try await sync.apply(SyncFixture.profile("Семья", account: card, zone: shared, at: now))
        let transfer = SyncFixture.transfer(100, from: card.id, to: cash.id, zone: shared, at: now)
        try await sync.apply([transfer.header, transfer.out, transfer.into])
        #expect(try await books()?.operations.isEmpty == true)
        try await sync.apply([SyncFixture.record(.account(cash), zone: shared, at: now)])
        #expect(try await books()?.operations.count == 1)
    }

    @Test func anEditThatDropsALegWaitsForTheDeletion() async throws {
        try await receiveTheProfile()
        let transfer = SyncFixture.transfer(100, from: card.id, to: cash.id, zone: shared, at: now)
        try await sync.apply([transfer.header, transfer.out, transfer.into])

        // The transfer became an expense on the other phone: one posting fewer.
        var header = transfer.header
        let id = header.payload.id
        header.payload = .operation(GoldaCore.Operation(id: id, type: .expense, timestamp: now), postingCount: 1)
        header.updatedAt = now + 1
        try await sync.apply([header])
        #expect(try await books()?.operations.first?.op.type == .transfer, "not until the leg is gone")
        try await sync.apply([], deletions: [transfer.into.ref])
        let operation = try #require(try await books()?.operations.first)
        #expect(operation.op.type == .expense)
        #expect(operation.postings.count == 1)
    }

    @Test func theLaterWriterWinsOverALocalEditStillWaiting() async throws {
        try await receiveTheProfile()
        harness.clock.set(now + 1_000)
        try await harness.repository.renameProfile(shared.profileId, to: "Моё")
        let ref = SyncRecordRef(zone: shared, type: .profile, id: shared.profileId)

        // Older than the local edit: this phone's version stays and goes again.
        let older = SyncFixture.record(.profile(Profile(id: shared.profileId, name: "Старое")), zone: shared, at: now - 500)
        #expect(try await sync.apply([older]) == [ref])
        #expect(try await books()?.profile.name == "Моё")

        // Newer: it replaces the local edit, which no longer needs sending.
        let newer = SyncFixture.record(.profile(Profile(id: shared.profileId, name: "Новое")), zone: shared, at: now + 500)
        #expect(try await sync.apply([newer]).isEmpty)
        #expect(try await books()?.profile.name == "Новое")
        #expect(try await sync.outgoing().isEmpty)
    }

    @Test func aLocalDeleteStandsAndARemoteDeleteRemoves() async throws {
        try await receiveTheProfile()
        let first = SyncFixture.transfer(100, from: card.id, to: cash.id, zone: shared, at: now)
        let second = SyncFixture.transfer(200, from: card.id, to: cash.id, zone: shared, at: now)
        try await sync.apply([first.header, first.out, first.into, second.header, second.out, second.into])
        try await harness.repository.deleteOperation(first.header.payload.id, profileId: shared.profileId)

        // The other phone still sends the first; it stays deleted here and the delete goes again.
        let kept = try await sync.apply([first.header], deletions: [second.header.ref, second.out.ref, second.into.ref])
        #expect(kept == [first.header.ref])
        #expect(try await books()?.operations.isEmpty == true)
        #expect(Set(try await sync.outgoing().map(\.kind)) == [.delete])
    }

    @Test func aZoneTheOwnerDeletedTakesTheProfileAlong() async throws {
        let own = try await harness.profile()
        try await receiveTheProfile()
        #expect(try await sync.zoneGone(shared, .deleted))
        #expect(try await books() == nil)
        #expect(try await harness.database.read { try $0.profiles() }.map(\.id) == [own])
        // Not a removal this phone asked for: nothing goes back to the server.
        #expect(try await sync.zonesToRemove().isEmpty)
        #expect(try await sync.outgoing().allSatisfy { $0.ref.zone.profileId == own })
    }

    @Test func losingTheOnlyProfileLeavesAFreshOneInItsPlace() async throws {
        let sync = SyncStore(database: harness.database, lastProfileName: "Личный")
        try await sync.apply(SyncFixture.profile("Семья", account: card, zone: shared, at: now))
        #expect(try await sync.zoneGone(shared, .deleted))
        let profiles = try await harness.database.read { try $0.profiles() }
        #expect(profiles.map(\.name) == ["Личный"])
        // An own profile: sync gives it a zone.
        #expect(try await sync.registerProfiles(now: now).map(\.profileId) == profiles.map(\.id))
    }

    @Test func anOwnZoneTheServerLostKeepsTheBooksAndGoesUpAgain() async throws {
        let own = try await harness.profile()
        _ = try await sync.registerProfiles(now: now)
        #expect(!(try await sync.zoneGone(.own(own), .lostOnServer)))
        #expect(try await harness.database.read { try $0.profile(own) } != nil)
        #expect(try await sync.registerProfiles(now: now) == [.own(own)])
    }

    @Test func anotherAccountKeepsTheOwnBooksAndDropsTheShared() async throws {
        let own = try await harness.profile()
        _ = try await sync.registerProfiles(now: now)
        try await receiveTheProfile()
        try await sync.setEngineState(Data([1]), for: .shared)

        try await sync.resetForAccountChange()
        #expect(try await harness.database.read { try $0.profiles() }.map(\.id) == [own])
        #expect(try await sync.engineState(.shared) == nil)
        #expect(try await sync.zonesToRemove().isEmpty, "the old account's shares are not left on its behalf")
        // The new account gets the phone's books.
        #expect(try await sync.registerProfiles(now: now) == [.own(own)])
    }

    @Test func leavingASharedProfileQueuesTheLeaveNotItsRows() async throws {
        _ = try await harness.profile()
        try await receiveTheProfile()
        try await harness.repository.deleteProfile(shared.profileId)
        #expect(try await sync.zonesToRemove() == [shared])
        #expect(try await sync.outgoing().allSatisfy { $0.ref.zone.profileId != shared.profileId })
        // What still arrives for it is not taken in.
        try await sync.apply(SyncFixture.profile("Семья", account: card, zone: shared, at: now + 1))
        #expect(try await books() == nil)
    }
}
