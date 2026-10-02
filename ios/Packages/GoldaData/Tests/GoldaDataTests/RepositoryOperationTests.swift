import Foundation
import GoldaCore
import Testing

@testable import GoldaData

/// Saving, editing, deleting and restoring operations; accounts, reconciling and rates.
@Suite final class RepositoryOperationTests {
    let harness: RepositoryHarness
    let profileId: UUID
    let rub = RepositoryLedgerTests.rubCard
    let usd = RepositoryLedgerTests.multiUsd
    let gel = RepositoryLedgerTests.cash
    var repository: Repository { harness.repository }

    init() async throws {
        harness = try RepositoryHarness()
        profileId = try await harness.profile(accounts: [rub, usd, gel])
    }

    // MARK: Editing

    @Test func editingKeepsPostingIdsAndValuesWithoutItself() async throws {
        try await repository.save(Draft(type: .transfer, timestamp: 1, accountId: rub.id, amountMinor: 900_000, toAccountId: usd.id, toAmountMinor: 10_000), profileId: profileId)
        var draft = Draft(type: .expense, timestamp: 2, accountId: usd.id, amountMinor: 5_000)
        let id = try await repository.save(draft, profileId: profileId)
        let before = try #require(try await harness.operation(id, profileId))
        #expect(before.postings.map(\.rubMinor) == [-450_000])
        #expect(try await harness.updatedAt(id) == RepositoryHarness.start)

        // All 100 $ at 90 ₽: valued as if the old 50 $ had never left, not half at the display rate.
        harness.clock.set(RepositoryHarness.start + 60_000)
        draft.id = id
        draft.amountMinor = 10_000
        draft.note = "  ужин "
        #expect(try await repository.save(draft, profileId: profileId) == id)
        let after = try #require(try await harness.operation(id, profileId))
        #expect(after.postings.map(\.id) == before.postings.map(\.id))
        #expect(after.postings.map(\.rubMinor) == [-900_000])
        #expect(after.op.note == "ужин")
        #expect(try await harness.updatedAt(id) == RepositoryHarness.start + 60_000)
        #expect(try await harness.snapshot(profileId).operations.count == 2)
    }

    @Test func editingATransferIntoAnExpenseAndBackKeepsTheOutLeg() async throws {
        var draft = Draft(type: .transfer, timestamp: 1, accountId: rub.id, amountMinor: 900_000, toAccountId: usd.id, toAmountMinor: 10_000)
        let id = try await repository.save(draft, profileId: profileId)
        draft.id = id
        let transfer = try #require(try await harness.operation(id, profileId)).postings
        #expect(transfer.count == 2)

        draft.type = .expense
        draft.toAccountId = nil
        draft.toAmountMinor = nil
        try await repository.save(draft, profileId: profileId)
        let expense = try #require(try await harness.operation(id, profileId)).postings
        #expect(expense.map(\.id) == [transfer[0].id])
        #expect(expense.map(\.amountMinor) == [-900_000])

        draft.type = .transfer
        draft.toAccountId = gel.id
        draft.toAmountMinor = 26_500
        try await repository.save(draft, profileId: profileId)
        let again = try #require(try await harness.operation(id, profileId)).postings
        #expect(again.count == 2)
        #expect(again[0].id == transfer[0].id)
        #expect(again[1].id != transfer[1].id)
        #expect(again.map(\.accountId) == [rub.id, gel.id])
        #expect(try await harness.state(usd.id, profileId).balanceMinor == 0)
    }

    @Test func exchangesKeepTheCbrRatesOfBothSides() async throws {
        let exchange = try await repository.save(Draft(type: .transfer, timestamp: 1, accountId: rub.id, amountMinor: 900_000, toAccountId: usd.id, toAmountMinor: 10_000), profileId: profileId)
        let op = try #require(try await harness.operation(exchange, profileId)).op
        #expect(op.cbrFrom == 1.0 && op.cbrTo == 83.2454)

        try await repository.saveAccount(Account(id: StoreFixture.id(5), name: "Ещё карта", currency: "RUB", type: .card, includeInFree: true), profileId: profileId)
        let sameCurrency = try await repository.save(Draft(type: .transfer, timestamp: 2, accountId: rub.id, amountMinor: 100, toAccountId: StoreFixture.id(5)), profileId: profileId)
        let plain = try #require(try await harness.operation(sameCurrency, profileId)).op
        #expect(plain.cbrFrom == nil && plain.cbrTo == nil)
    }

    @Test func expensesMakeTheirAccountThisPhonesDefaultInTheProfile() async throws {
        try await repository.save(Draft(type: .income, timestamp: 1, accountId: usd.id, amountMinor: 100), profileId: profileId)
        #expect(harness.device.current.lastAccountId[profileId] == nil)
        try await repository.save(Draft(type: .expense, timestamp: 2, accountId: gel.id, amountMinor: 100), profileId: profileId)
        #expect(harness.device.current.lastAccountId == [profileId: gel.id])
        #expect(try await repository.settings(profileId: profileId).lastAccountId == gel.id)
    }

    // MARK: Delete and undo

    @Test func undoOfADeleteBringsBackTheSameIds() async throws {
        try await repository.save(Draft(type: .opening, timestamp: 0, accountId: rub.id, amountMinor: 1_000_000), profileId: profileId)
        let id = try await repository.save(Draft(type: .transfer, timestamp: 1, accountId: rub.id, amountMinor: 900_000, toAccountId: usd.id, toAmountMinor: 10_000), profileId: profileId)
        let original = try #require(try await harness.operation(id, profileId))

        let deleted = try #require(try await repository.deleteOperation(id, profileId: profileId))
        #expect(deleted == original)
        #expect(try await harness.operation(id, profileId) == nil)
        #expect(try await harness.state(rub.id, profileId).balanceMinor == 1_000_000)
        #expect(try await repository.deleteOperation(id, profileId: profileId) == nil)

        try await repository.restoreOperation(deleted, profileId: profileId)
        #expect(try await harness.operation(id, profileId) == original)
        #expect(try await harness.state(rub.id, profileId).balanceMinor == 100_000)
        #expect(try await harness.state(usd.id, profileId).balanceMinor == 10_000)
    }

    // MARK: Accounts

    @Test func aNewAccountBooksItsOpeningBalanceAndAnEditDoesNot() async throws {
        let savings = Account(id: StoreFixture.id(6), name: "Вклад", currency: "USD", type: .savings, includeInFree: false, sort: 3)
        try await repository.saveAccount(savings, profileId: profileId, openingMinor: 10_000)
        let opening = try #require(try await harness.snapshot(profileId).operations.first)
        #expect(opening.op.type == .opening)
        #expect(opening.op.timestamp == RepositoryHarness.start)
        // An opening in dollars is valued at the display rate: 100 × 83.2454 × 1.1.
        #expect(opening.postings.map(\.rubMinor) == [915_699])

        var renamed = savings
        renamed.name = "Вклад в долларах"
        try await repository.saveAccount(renamed, profileId: profileId, openingMinor: 50_000)
        let books = try await harness.snapshot(profileId)
        #expect(books.operations.count == 1)
        #expect(books.accounts.last == renamed)

        // Zero is no opening at all.
        try await repository.saveAccount(Account(id: StoreFixture.id(7), name: "Пусто", currency: "RUB", type: .cash, includeInFree: true), profileId: profileId, openingMinor: 0)
        #expect(try await harness.snapshot(profileId).operations.count == 1)
    }

    @Test func deletingAnAccountTakesEveryOperationThatTouchesIt() async throws {
        try await repository.saveAccount(Account(id: StoreFixture.id(8), name: "Старая", currency: "RUB", type: .card, includeInFree: true), profileId: profileId, openingMinor: 500_000)
        try await repository.save(Draft(type: .opening, timestamp: 0, accountId: rub.id, amountMinor: 1_000_000), profileId: profileId)
        try await repository.save(Draft(type: .transfer, timestamp: 1, accountId: StoreFixture.id(8), amountMinor: 200_000, toAccountId: rub.id), profileId: profileId)

        try await repository.deleteAccount(StoreFixture.id(8), profileId: profileId)
        let books = try await harness.snapshot(profileId)
        #expect(!books.accounts.contains { $0.id == StoreFixture.id(8) })
        #expect(books.operations.map(\.op.type) == [.opening])
        // No half of the transfer is left on the other side.
        #expect(try await harness.state(rub.id, profileId).balanceMinor == 1_000_000)
    }

    // MARK: Reconcile

    @Test func reconcilingBooksTheDifferenceAndStampsTheAccount() async throws {
        try await repository.save(Draft(type: .opening, timestamp: 0, accountId: rub.id, amountMinor: 1_000_000), profileId: profileId)
        let adjustment = try #require(try await repository.reconcile(accountId: rub.id, actualMinor: 950_000, profileId: profileId))
        let full = try #require(try await harness.operation(adjustment, profileId))
        #expect(full.op.type == .adjustment)
        #expect(full.op.timestamp == RepositoryHarness.start)
        #expect(full.postings.map(\.amountMinor) == [-50_000])
        #expect(try await harness.state(rub.id, profileId).balanceMinor == 950_000)
        #expect(try await harness.snapshot(profileId).accounts.first?.reconciledAt == RepositoryHarness.start)
    }

    @Test func aMatchBooksNothingButTheTime() async throws {
        try await repository.save(Draft(type: .opening, timestamp: 0, accountId: usd.id, amountMinor: 10_000), profileId: profileId)
        harness.clock.set(RepositoryHarness.start + 3_600_000)
        #expect(try await repository.reconcile(accountId: usd.id, actualMinor: 10_000, profileId: profileId) == nil)
        let books = try await harness.snapshot(profileId)
        #expect(books.operations.count == 1)
        #expect(books.accounts.first { $0.id == usd.id }?.reconciledAt == RepositoryHarness.start + 3_600_000)
        #expect(books.accounts.first { $0.id == rub.id }?.reconciledAt == nil)
    }

    // MARK: Rates

    @Test func freshRatesValueWhatHadNoRate() async throws {
        let euro = Account(id: StoreFixture.id(9), name: "Евро", currency: "EUR", type: .cash, includeInFree: true, sort: 4)
        try await repository.saveAccount(euro, profileId: profileId)
        let income = try await repository.save(Draft(type: .income, timestamp: 1, accountId: euro.id, amountMinor: 10_000), profileId: profileId)
        let spent = try await repository.save(Draft(type: .expense, timestamp: 2, accountId: euro.id, amountMinor: 2_000), profileId: profileId)
        let rubles = try await repository.save(Draft(type: .income, timestamp: 3, accountId: rub.id, amountMinor: 100), profileId: profileId)
        #expect(try await harness.operation(income, profileId)?.postings.map(\.rubMinor) == [0])

        // A failed download changes nothing.
        let offline = StubRatesSource { throw URLError(.notConnectedToInternet) }
        #expect(try await repository.refreshRates(from: offline) == false)
        #expect(try await harness.operation(income, profileId)?.postings.map(\.rubMinor) == [0])

        let fresh = StubRatesSource { [CbrRate(code: "EUR", rubPerUnit: 90, date: "2026-10-03"), CbrRate(code: "USD", rubPerUnit: 84, date: "2026-10-03")] }
        #expect(try await repository.refreshRates(from: fresh) == true)
        // 100 € × 90 × 1.1 and −20 € likewise; rubles and valued postings stay as they were.
        #expect(try await harness.operation(income, profileId)?.postings.map(\.rubMinor) == [990_000])
        #expect(try await harness.operation(spent, profileId)?.postings.map(\.rubMinor) == [-198_000])
        #expect(try await harness.operation(rubles, profileId)?.postings.map(\.rubMinor) == [100])
        let table = try await harness.database.read { try $0.rates() }
        #expect(table.first { $0.code == "USD" } == RateRecord(code: "USD", rubPerUnit: 84, date: "2026-10-03"))
        #expect(table.count == 4)
    }

    @Test func repairUsesEachProfilesOwnMarkup() async throws {
        var noMarkup = ProfileSettings()
        noMarkup.markup = 0
        let family = try await repository.createProfile(name: "Семья", settings: noMarkup).id
        let euros = [StoreFixture.id(10), StoreFixture.id(11)]
        try await repository.saveAccount(Account(id: euros[0], name: "€", currency: "EUR", type: .cash, includeInFree: true), profileId: profileId)
        try await repository.saveAccount(Account(id: euros[1], name: "€", currency: "EUR", type: .cash, includeInFree: true), profileId: family)
        try await repository.save(Draft(type: .income, timestamp: 1, accountId: euros[0], amountMinor: 10_000), profileId: profileId)
        try await repository.save(Draft(type: .income, timestamp: 1, accountId: euros[1], amountMinor: 10_000), profileId: family)

        try await repository.refreshRates(from: StubRatesSource { [CbrRate(code: "EUR", rubPerUnit: 90, date: "2026-10-03")] })
        #expect(try await harness.state(euros[0], profileId).rubMinor == 990_000)
        #expect(try await harness.state(euros[1], family).rubMinor == 900_000)
    }

    @Test func seedingFillsAnEmptyRateTableOnly() async throws {
        let database = try GoldaDatabase.inMemory()
        let repository = Repository(database: database, deviceSettings: harness.device)
        try await repository.ensureSeed()
        #expect(try await database.read { try $0.rates() } == CbrRatesSource.fallback.map(RateRecord.init).sorted { $0.code < $1.code })

        // Known rates are not replaced by older fallback ones.
        try await harness.repository.ensureSeed()
        #expect(try await harness.database.read { try $0.rates() }.count == RepositoryHarness.rates.count)
    }
}
