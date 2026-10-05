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

    /// D68: the other phone's categories arrive in their order, and go when deleted there.
    @Test func categoriesArriveInTheirOrderAndGo() async throws {
        try await receiveTheProfile()
        let cat = CustomCategory(name: "Кот", kind: .expense, hint: "корм", symbol: "cat")
        let rent = CustomCategory(name: "Аренда", kind: .income)
        try await sync.apply([
            SyncFixture.record(.category(rent, createdAt: 2), zone: shared, at: now),
            SyncFixture.record(.category(cat, createdAt: 1), zone: shared, at: now),
        ])
        #expect(try await books()?.categories == [cat, rent])
        try await sync.apply([], deletions: [SyncRecordRef(zone: shared, type: .category, id: cat.id)])
        #expect(try await books()?.categories == [rent])
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

    @Test func anOperationArrivesWithAllItsPostings() async throws {
        try await receiveTheProfile()
        try await sync.apply([SyncFixture.transfer(5_000, from: card.id, to: cash.id, zone: shared, at: now)])
        let operations = try #require(try await books()).operations
        #expect(operations.count == 1)
        // In the record's order: money out first, as the ledger writes a transfer.
        #expect(operations[0].postings.map(\.amountMinor) == [-5_000, 5_000])
    }

    @Test func anOperationWaitsForItsAccounts() async throws {
        try await sync.apply(SyncFixture.profile("Семья", account: card, zone: shared, at: now))
        try await sync.apply([SyncFixture.transfer(100, from: card.id, to: cash.id, zone: shared, at: now)])
        #expect(try await books()?.operations.isEmpty == true)
        try await sync.apply([SyncFixture.record(.account(cash), zone: shared, at: now)])
        #expect(try await books()?.operations.count == 1)
    }

    @Test func anEditThatDropsALegReplacesThePostingsWhole() async throws {
        try await receiveTheProfile()
        let transfer = SyncFixture.transfer(100, from: card.id, to: cash.id, zone: shared, at: now)
        try await sync.apply([transfer])

        // The transfer became an expense on the other phone: one posting fewer, in the same record.
        let out = SyncFixture.postings(transfer)[0]
        try await sync.apply([SyncFixture.edited(transfer, at: now + 1, type: .expense, postings: [out])])
        let operation = try #require(try await books()?.operations.first)
        #expect(operation.op.type == .expense)
        #expect(operation.postings == [out])
        #expect(try await sync.waitingCount() == 0)
    }

    /// An operation and its postings are one record, so one of them never wins over the rest: here
    /// the other phone turned the transfer into an expense earlier, and this phone's later note
    /// keeps both legs (a transfer with one leg is money from nowhere).
    @Test func aLosingVersionOfAnOperationChangesNoneOfItsPostings() async throws {
        try await receiveTheProfile()
        let transfer = SyncFixture.transfer(100, from: card.id, to: cash.id, zone: shared, at: now)
        try await sync.apply([transfer])
        let id = transfer.payload.id
        harness.clock.set(now + 2_000)
        try await harness.repository.save(
            Draft(type: .transfer, timestamp: now, accountId: card.id, amountMinor: 100, toAccountId: cash.id, note: "Моё", id: id),
            profileId: shared.profileId
        )

        let out = SyncFixture.postings(transfer)[0]
        let expense = SyncFixture.edited(transfer, at: now - 1_000, type: .expense, postings: [out])
        #expect(try await sync.apply([expense]) == [transfer.ref])
        let operation = try #require(try await books()?.operations.first)
        #expect(operation.op.type == .transfer)
        #expect(operation.op.note == "Моё")
        #expect(operation.postings.map(\.id) == SyncFixture.postings(transfer).map(\.id))
        // What goes again carries both legs.
        guard case .operation(_, let postings)? = try await sync.record(transfer.ref)?.payload else {
            Issue.record("not an operation")
            return
        }
        #expect(postings.count == 2)
    }

    /// A record that waited (here for an account) is checked again when it can land: a local edit
    /// made meanwhile is newer and stays.
    @Test func aWaitingRecordDoesNotLandOverANewerLocalEdit() async throws {
        try await receiveTheProfile()
        let transfer = SyncFixture.transfer(100, from: card.id, to: cash.id, zone: shared, at: now)
        try await sync.apply([transfer])
        let later = Account.card("Вклад", sort: 2)
        let posts = SyncFixture.postings(transfer)
        var into = posts[1]
        into.accountId = later.id
        try await sync.apply([SyncFixture.edited(transfer, at: now + 1_000, note: "Чужое", postings: [posts[0], into])])
        #expect(try await sync.waitingCount() == 1)

        harness.clock.set(now + 2_000)
        try await harness.repository.save(
            Draft(type: .transfer, timestamp: now, accountId: card.id, amountMinor: 100, toAccountId: cash.id, note: "Моё", id: transfer.payload.id),
            profileId: shared.profileId
        )
        try await sync.apply([SyncFixture.record(.account(later), zone: shared, at: now)])
        let operation = try #require(try await books()?.operations.first)
        #expect(operation.op.note == "Моё")
        #expect(operation.postings.map(\.accountId) == [card.id, cash.id])
        #expect(try await sync.waitingCount() == 0)
        #expect(try await sync.outgoing().contains { $0.ref == transfer.ref && $0.kind == .save })
    }

    /// As `Repository.deleteAccount` does: an account deleted on another phone takes every
    /// operation touching it, both legs of its transfers, and those deletes reach the server.
    @Test func aRemoteAccountDeleteTakesTheOperationsTouchingIt() async throws {
        try await receiveTheProfile()
        // This phone's transfer the other phone never saw.
        let local = try await harness.repository.save(
            Draft(type: .transfer, timestamp: now, accountId: card.id, amountMinor: 100, toAccountId: cash.id),
            profileId: shared.profileId
        )
        // And one from the server waiting for an account that is still to come.
        let waiting = SyncFixture.transfer(5, from: card.id, to: UUID(), zone: shared, at: now)
        try await sync.apply([waiting])
        #expect(try await sync.waitingCount() == 1)

        try await sync.apply([], deletions: [SyncRecordRef(zone: shared, type: .account, id: card.id)])
        let books = try #require(try await books())
        #expect(books.accounts.map(\.name) == ["Наличные"])
        #expect(books.operations.isEmpty, "no leg is left on Наличные")
        #expect(try await sync.waitingCount() == 0)
        let deletes = Set(try await sync.outgoing().filter { $0.kind == .delete }.map(\.ref.id))
        #expect(deletes == [local, waiting.payload.id])
    }

    /// The owner made the profile read-only, or the server refused the change for good: the
    /// server's version replaces this phone's, so the books never differ from everyone else's.
    @Test func aRefusedChangeGivesWayToTheServersVersion() async throws {
        try await receiveTheProfile()
        let transfer = SyncFixture.transfer(100, from: card.id, to: cash.id, zone: shared, at: now)
        try await sync.apply([transfer])
        harness.clock.set(now + 1_000)
        try await harness.repository.save(
            Draft(type: .expense, timestamp: now, accountId: card.id, amountMinor: 7, note: "Моё", id: transfer.payload.id),
            profileId: shared.profileId
        )
        let added = try await harness.repository.save(
            Draft(type: .expense, timestamp: now, accountId: card.id, amountMinor: 9), profileId: shared.profileId
        )
        try await harness.repository.renameProfile(shared.profileId, to: "Моё")

        try await sync.refused(transfer.ref, serverVersion: transfer)
        try await sync.refused(SyncRecordRef(zone: shared, type: .operation, id: added), serverVersion: nil)
        let profile = SyncRecordRef(zone: shared, type: .profile, id: shared.profileId)
        try await sync.refused(profile, serverVersion: SyncFixture.record(.profile(Profile(id: shared.profileId, name: "Семья")), zone: shared, at: now))

        let books = try #require(try await books())
        #expect(books.profile.name == "Семья")
        #expect(books.operations.map(\.op.id) == [transfer.payload.id])
        #expect(books.operations[0].op.type == .transfer)
        #expect(books.operations[0].postings == SyncFixture.postings(transfer))
        #expect(try await sync.outgoing().isEmpty)

        // A delete refused: the operation comes back.
        try await harness.repository.deleteOperation(transfer.payload.id, profileId: shared.profileId)
        try await sync.refused(transfer.ref, serverVersion: transfer)
        #expect(try await self.books()?.operations.map(\.op.id) == [transfer.payload.id])
        #expect(try await sync.outgoing().isEmpty)
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
        try await sync.apply([first, second])
        try await harness.repository.deleteOperation(first.payload.id, profileId: shared.profileId)

        // The other phone still sends the first; it stays deleted here and the delete goes again.
        let kept = try await sync.apply([first], deletions: [second.ref])
        #expect(kept == [first.ref])
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

    /// Signing out and in again must not bring back what was deleted here and not yet sent: the
    /// deletes and the zones to remove outlive the account change; only the shared ones go.
    @Test func anAccountChangeKeepsTheDeletesItOwes() async throws {
        let own = try await harness.profile(accounts: [card])
        let old = try await harness.profile("Старый")
        _ = try await sync.registerProfiles(now: now)
        let expense = try await harness.repository.save(
            Draft(type: .expense, timestamp: now, accountId: card.id, amountMinor: 100), profileId: own
        )
        _ = try await sync.takeDue(at: now)
        try await harness.repository.deleteOperation(expense, profileId: own)
        _ = try await sync.takeDue(at: now + OutgoingQueue.undoWindow)
        try await harness.repository.deleteProfile(old)
        try await receiveTheProfile()
        try await harness.repository.deleteProfile(shared.profileId)

        try await sync.resetForAccountChange()
        #expect(try await sync.zonesToRemove() == [.own(old)])
        let delete = try #require(try await sync.outgoing().first { $0.ref.id == expense })
        #expect(delete.kind == .delete)
        #expect(delete.handedRevision == nil, "handed again to the new session")
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
