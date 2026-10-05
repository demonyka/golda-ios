import Foundation
import GoldaCore
import GoldaData
import Testing

@testable import GoldaSync

/// The two-phone scenario of stage 5 on real books, against the in-memory cloud: Alice owns the
/// profile «Семья» and shares it with Bob, who has his own «Личный». Both write through the
/// repository, as the app does; sync carries the rows (ROADMAP, «Готово, когда»).
@Suite(.timeLimit(.minutes(1))) struct TwoPhonesTests {
    private let clock = TestClock()
    private let cloud = InMemoryCloud()
    private let card = Account.card("Общая карта")
    private let cash = Account.card("Наличные", sort: 1)

    private var now: Int64 { clock.now }

    /// Alice sets «Семья» up (income, payday, two accounts, an expense, a payment, a goal, a wish,
    /// a category of her own)
    /// and shares it; Bob, who has his own profile, joins.
    private func sharedFamily(readOnly: Bool = false) async throws -> (alice: Phone, bob: Phone, family: UUID) {
        let alice = try await Phone("alice", cloud: cloud, clock: clock)
        let bob = try await Phone("bob", cloud: cloud, clock: clock)
        await alice.launch()
        await bob.launch()
        _ = try await bob.repository.createProfile(name: "Личный")

        let family = try await alice.repository.createProfile(name: "Семья").id
        var settings = ProfileSettings()
        settings.monthlySalary = 150_000
        settings.payday = 10
        try await alice.repository.saveProfileSettings(settings, profileId: family)
        try await alice.repository.saveAccount(card, profileId: family, openingMinor: 6_000_000)
        try await alice.repository.saveAccount(cash, profileId: family, openingMinor: 500_000)
        try await alice.repository.save(
            Draft(type: .expense, timestamp: now, accountId: card.id, amountMinor: 250_000, categoryKey: "food", note: "Хинкали"),
            profileId: family
        )
        try await alice.repository.saveObligation(Obligation(name: "Аренда", amountMinor: 3_000_000, currency: "RUB", dayOfMonth: 5), profileId: family)
        try await alice.repository.saveGoal(Goal(name: "Отпуск", targetMinor: 30_000_000, currency: "RUB", isMain: true), profileId: family)
        try await alice.repository.think(Consider(title: "Велосипед", amountMinor: 4_000_000, currency: "RUB"), profileId: family)
        try await alice.repository.saveCategory(CustomCategory(name: "Кот", kind: .expense, hint: "корм"), profileId: family)
        try await alice.sync()

        await cloud.share(family, of: "alice", with: "bob", readOnly: readOnly)
        try await bob.sync()
        return (alice, bob, family)
    }

    private static func byId(_ a: OperationFull, _ b: OperationFull) -> Bool { a.op.id.uuidString < b.op.id.uuidString }

    private func expectSameBooks(_ a: Phone, _ b: Phone, _ profileId: UUID, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        let left = try #require(try await a.books(profileId), sourceLocation: sourceLocation)
        let right = try #require(try await b.books(profileId), sourceLocation: sourceLocation)
        #expect(left.profile.name == right.profile.name, sourceLocation: sourceLocation)
        #expect(left.profile.settings == right.profile.settings, sourceLocation: sourceLocation)
        #expect(left.accounts == right.accounts, sourceLocation: sourceLocation)
        // The order of operations with one timestamp is each phone's order of writing (D58).
        #expect(left.operations.sorted(by: Self.byId) == right.operations.sorted(by: Self.byId), sourceLocation: sourceLocation)
        #expect(left.operations.map(\.op.timestamp) == right.operations.map(\.op.timestamp), sourceLocation: sourceLocation)
        #expect(left.obligations == right.obligations, sourceLocation: sourceLocation)
        #expect(left.goals == right.goals, sourceLocation: sourceLocation)
        #expect(left.wishes == right.wishes, sourceLocation: sourceLocation)
        #expect(left.categories == right.categories, sourceLocation: sourceLocation)
        #expect(try await a.balances(profileId) == b.balances(profileId), sourceLocation: sourceLocation)
        let leftToday = try await a.safeToSpend(profileId, at: now)
        let rightToday = try await b.safeToSpend(profileId, at: now)
        #expect(leftToday == rightToday, "«Можно сегодня» differs", sourceLocation: sourceLocation)
    }

    @Test func theParticipantGetsTheWholeProfileAndTheSameSafeToSpend() async throws {
        let (alice, bob, family) = try await sharedFamily()
        #expect(try await bob.profiles().map(\.name) == ["Личный", "Семья"])
        try await expectSameBooks(alice, bob, family)
        #expect(try await bob.balances(family) == ["Общая карта": 5_750_000, "Наличные": 500_000])
        #expect(try await bob.books(family)?.categories.map(\.name) == ["Кот"])
        // Bob's own profile never left his phone.
        #expect(try await alice.profiles().map(\.name) == ["Семья"])
    }

    @Test func anExpenseOnEitherPhoneReachesTheOther() async throws {
        let (alice, bob, family) = try await sharedFamily()
        clock.advance(60_000)
        try await bob.repository.save(Draft(type: .expense, timestamp: now, accountId: cash.id, amountMinor: 90_000, note: "Такси"), profileId: family)
        try await bob.sync()
        try await alice.sync()
        #expect(try await alice.books(family)?.operations.map(\.op.note).contains("Такси") == true)

        try await alice.repository.save(
            Draft(type: .transfer, timestamp: now, accountId: card.id, amountMinor: 1_000_000, toAccountId: cash.id), profileId: family
        )
        try await alice.sync()
        try await bob.sync()
        try await expectSameBooks(alice, bob, family)
        #expect(try await bob.balances(family) == ["Общая карта": 4_750_000, "Наличные": 1_410_000])
        #expect(try await alice.store.outgoing().isEmpty)
        #expect(try await bob.store.outgoing().isEmpty)
    }

    /// D66: the app asks for changes now and then while it is open; a fetch alone brings them.
    @Test func aFetchAloneBringsTheOthersChange() async throws {
        let (alice, bob, family) = try await sharedFamily()
        clock.advance(60_000)
        try await bob.repository.save(Draft(type: .expense, timestamp: now, accountId: cash.id, amountMinor: 90_000, note: "Такси"), profileId: family)
        try await bob.sync()
        await alice.service.fetch()
        #expect(try await alice.books(family)?.operations.map(\.op.note).contains("Такси") == true)
    }

    @Test func anEditKeepsItsRowsAndReachesTheOther() async throws {
        let (alice, bob, family) = try await sharedFamily()
        let expense = try #require(try await bob.books(family)?.operations.first { $0.op.type == .expense })
        clock.advance(1_000)
        try await bob.repository.save(
            Draft(type: .expense, timestamp: expense.op.timestamp, accountId: cash.id, amountMinor: 300_000, categoryKey: "food", note: "Хинкали и вино", id: expense.op.id),
            profileId: family
        )
        try await bob.sync()
        try await alice.sync()
        let edited = try #require(try await alice.books(family)?.operations.first { $0.op.id == expense.op.id })
        #expect(edited.op.note == "Хинкали и вино")
        #expect(edited.postings.map(\.id) == expense.postings.map(\.id))
        try await expectSameBooks(alice, bob, family)
    }

    @Test func aDeleteLeavesAfterTheUndoWindowAndAnUndoNeverLeaves() async throws {
        let (alice, bob, family) = try await sharedFamily()
        let expense = try #require(try await alice.books(family)?.operations.first { $0.op.type == .expense })

        let deleted = try #require(try await alice.repository.deleteOperation(expense.op.id, profileId: family))
        try await alice.sync()
        try await bob.sync()
        #expect(try await bob.books(family)?.operations.contains { $0.op.id == expense.op.id } == true, "still in the undo window")

        // "Отменить" in time: nothing reaches Bob, even after the window.
        try await alice.repository.restoreOperation(deleted, profileId: family)
        clock.advance(OutgoingQueue.undoWindow + 1)
        try await alice.sync()
        try await bob.sync()
        #expect(try await bob.books(family)?.operations.contains { $0.op.id == expense.op.id } == true)

        // Deleted for good: it goes once the window is over.
        try await alice.repository.deleteOperation(expense.op.id, profileId: family)
        clock.advance(OutgoingQueue.undoWindow)
        try await alice.sync()
        try await bob.sync()
        #expect(try await bob.books(family)?.operations.contains { $0.op.id == expense.op.id } == false)
        try await expectSameBooks(alice, bob, family)
    }

    @Test func offlineEditsOnBothSidesSettleOnTheLaterOneAndBalancesAgree() async throws {
        let (alice, bob, family) = try await sharedFamily()
        let expense = try #require(try await alice.books(family)?.operations.first { $0.op.type == .expense })

        // No network on either phone: both edit the same expense, Bob later; both add their own.
        clock.advance(1_000)
        try await alice.repository.save(
            Draft(type: .expense, timestamp: expense.op.timestamp, accountId: card.id, amountMinor: 260_000, note: "Хинкали (A)", id: expense.op.id),
            profileId: family
        )
        try await alice.repository.save(Draft(type: .expense, timestamp: now, accountId: card.id, amountMinor: 10_000, note: "Кофе"), profileId: family)
        clock.advance(1_000)
        try await bob.repository.save(
            Draft(type: .expense, timestamp: expense.op.timestamp, accountId: card.id, amountMinor: 270_000, note: "Хинкали (B)", id: expense.op.id),
            profileId: family
        )
        try await bob.repository.save(Draft(type: .income, timestamp: now, accountId: cash.id, amountMinor: 50_000, note: "Долг вернули"), profileId: family)

        // Back online, Alice first: Bob's save then conflicts, and his later edit wins.
        try await alice.sync()
        try await bob.sync()
        try await alice.sync()
        let notes = try #require(try await alice.books(family)).operations.map(\.op.note)
        #expect(notes.contains("Хинкали (B)"))
        #expect(notes.contains("Кофе"))
        #expect(notes.contains("Долг вернули"))
        try await expectSameBooks(alice, bob, family)
    }

    /// The review's interleaving: Bob turns a transfer into an expense, Alice, offline, then edits
    /// its note. The operation and its postings are one record, so Alice's later version wins
    /// whole on both phones: never a transfer with one leg, never an entry waiting for good.
    @Test func concurrentEditsOfOneOperationSettleOnOneWholeVersion() async throws {
        let (alice, bob, family) = try await sharedFamily()
        let transfer = try await alice.repository.save(
            Draft(type: .transfer, timestamp: now, accountId: card.id, amountMinor: 1_000_000, toAccountId: cash.id), profileId: family
        )
        try await alice.sync()
        try await bob.sync()

        clock.advance(1_000)
        try await bob.repository.save(Draft(type: .expense, timestamp: now, accountId: card.id, amountMinor: 1_000_000, id: transfer), profileId: family)
        try await bob.sync()
        clock.advance(1_000)
        try await alice.repository.save(
            Draft(type: .transfer, timestamp: now, accountId: card.id, amountMinor: 1_000_000, toAccountId: cash.id, note: "В копилку", id: transfer),
            profileId: family
        )
        for _ in 0..<2 {
            try await alice.sync()
            try await bob.sync()
            clock.advance(OutgoingQueue.undoWindow)
        }

        let operation = try #require(try await bob.books(family)?.operations.first { $0.op.id == transfer })
        #expect(operation.op.type == .transfer)
        #expect(operation.op.note == "В копилку")
        #expect(operation.postings.count == 2)
        try await expectSameBooks(alice, bob, family)
        #expect(try await alice.store.waitingCount() == 0)
        #expect(try await bob.store.waitingCount() == 0)
    }

    /// A participant the owner made read-only cannot change the books on the server; their phone
    /// takes the server's version back instead of keeping a change no one else will see.
    @Test func aReadOnlyParticipantsChangesGiveWayToTheOwnersBooks() async throws {
        let (alice, bob, family) = try await sharedFamily(readOnly: true)
        let expense = try #require(try await bob.books(family)?.operations.first { $0.op.type == .expense })
        clock.advance(1_000)
        try await bob.repository.save(
            Draft(type: .expense, timestamp: expense.op.timestamp, accountId: cash.id, amountMinor: 1, note: "Не моё", id: expense.op.id),
            profileId: family
        )
        try await bob.repository.save(Draft(type: .income, timestamp: now, accountId: cash.id, amountMinor: 9_000_000), profileId: family)
        try await bob.repository.renameProfile(family, to: "Моё")
        try await bob.sync()
        clock.advance(OutgoingQueue.undoWindow)
        try await bob.repository.deleteOperation(expense.op.id, profileId: family)
        clock.advance(OutgoingQueue.undoWindow)
        try await bob.sync()
        try await alice.sync()

        #expect(await bob.transport.lastProblem == .notPermitted)
        #expect(try await bob.books(family)?.profile.name == "Семья")
        try await expectSameBooks(alice, bob, family)
        #expect(try await bob.store.outgoing().isEmpty)
        #expect(try await alice.service.participants(family).first { $0.name == "bob" }?.canWrite == false)
    }

    @Test func profileSettingsAndGoalsGoBothWays() async throws {
        let (alice, bob, family) = try await sharedFamily()
        var settings = try #require(try await bob.books(family)).profile.settings
        settings.payday = 25
        clock.advance(1_000)
        try await bob.repository.saveProfileSettings(settings, profileId: family)
        try await bob.repository.saveGoal(Goal(name: "Машина", targetMinor: 1, currency: "RUB", isMain: true), profileId: family)
        try await bob.sync()
        try await alice.sync()
        #expect(try await alice.books(family)?.profile.settings.payday == 25)
        #expect(try await alice.books(family)?.goals.map(\.name) == ["Машина", "Отпуск"])
        try await expectSameBooks(alice, bob, family)
    }

    @Test func theParticipantLeavesAndTheOwnerKeepsTheProfile() async throws {
        let (alice, bob, family) = try await sharedFamily()
        try await bob.repository.deleteProfile(family)
        try await bob.sync()
        try await alice.sync()
        #expect(try await bob.profiles().map(\.name) == ["Личный"])
        #expect(try await alice.books(family) != nil)
        #expect(await cloud.hasZone(family, of: "alice"))
        // Nothing of it comes back to Bob.
        clock.advance(1_000)
        try await alice.repository.renameProfile(family, to: "Семья 2")
        try await alice.sync()
        try await bob.sync()
        #expect(try await bob.profiles().map(\.name) == ["Личный"])
    }

    @Test func stoppingSharingTakesTheProfileFromTheParticipantOnly() async throws {
        let (alice, bob, family) = try await sharedFamily()
        #expect(try await alice.service.participants(family).map(\.name) == ["alice", "bob"])
        try await alice.service.stopSharing(family)
        try await bob.sync()
        try await alice.sync()
        #expect(try await bob.books(family) == nil)
        #expect(try await bob.profiles().map(\.name) == ["Личный"])
        #expect(try await alice.books(family)?.operations.isEmpty == false)
        #expect(try await alice.service.participants(family).isEmpty)
    }

    @Test func theOwnerDeletingTheProfileTakesItFromEveryone() async throws {
        let (alice, bob, family) = try await sharedFamily()
        _ = try await alice.repository.createProfile(name: "Личный")
        try await alice.repository.deleteProfile(family)
        try await alice.sync()
        try await bob.sync()
        #expect(!(await cloud.hasZone(family, of: "alice")))
        #expect(try await bob.books(family) == nil)
        #expect(try await alice.store.zonesToRemove().isEmpty)
    }

    @Test func aNewProcessResumesFromTheSavedCursorAndQueue() async throws {
        let (alice, bob, family) = try await sharedFamily()
        // Bob writes with no network, then the app is killed.
        try await bob.repository.save(Draft(type: .expense, timestamp: now, accountId: cash.id, amountMinor: 100, note: "Офлайн"), profileId: family)

        let relaunched = try await Phone("bob", cloud: cloud, clock: clock, database: bob.database)
        await relaunched.launch()
        try await relaunched.sync()
        try await alice.sync()
        #expect(try await alice.books(family)?.operations.map(\.op.note).contains("Офлайн") == true)
        try await expectSameBooks(alice, relaunched, family)
    }

    @Test func aRequestToWaitIsHonoured() async throws {
        let (alice, bob, family) = try await sharedFamily()
        clock.advance(1_000)
        try await alice.repository.renameProfile(family, to: "Семья и друзья")
        // The server takes nothing for 330 s, as on 2026-10-04 (D58).
        await cloud.refuseNextSaves(1, retryAfter: 330)
        try await alice.sync()
        #expect(await alice.transport.lastProblem == .retryLater(seconds: 330))
        let taken = await cloud.savesTaken

        clock.advance(329_000)
        try await alice.sync()
        #expect(await cloud.savesTaken == taken, "nothing is sent before the time is up")

        clock.advance(1_000)
        try await alice.sync()
        try await bob.sync()
        #expect(try await bob.books(family)?.profile.name == "Семья и друзья")
    }

    @Test func withoutICloudTheBooksStayLocalAndGoUpOnceItIsThere() async throws {
        let alice = try await Phone("alice", cloud: cloud, clock: clock)
        await alice.transport.setStatus(.noAccount)
        await alice.launch()
        #expect(await alice.service.state == .off(.noAccount))
        let personal = try await alice.repository.createProfile(name: "Личный").id
        try await alice.repository.saveAccount(card, profileId: personal, openingMinor: 100_000)
        try await alice.sync()
        #expect(!(await cloud.hasZone(personal, of: "alice")))

        // Signed in: the profile made before goes to its zone with everything in it.
        await alice.transport.setStatus(.available)
        await alice.launch()
        try await alice.sync()
        #expect(await cloud.hasZone(personal, of: "alice"))
        let otherPhone = try await Phone("alice", cloud: cloud, clock: clock)
        await otherPhone.launch()
        try await otherPhone.sync()
        try await expectSameBooks(alice, otherPhone, personal)
    }
}
