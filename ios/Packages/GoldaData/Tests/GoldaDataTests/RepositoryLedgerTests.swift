import Foundation
import GoldaCore
import Testing

@testable import GoldaData

/// GoldaCore's LedgerTests (the port of LedgerTest.kt) once more, with every draft booked by
/// `Repository.save` on a real database: the numbers must not change on the way through the store.
@Suite final class RepositoryLedgerTests {
    static let rubCard = Account(id: StoreFixture.id(1), name: "Карта ₽", currency: "RUB", type: .card, includeInFree: true, sort: 0)
    static let multiUsd = Account(id: StoreFixture.id(2), name: "Мультивалютная USD", currency: "USD", type: .card, includeInFree: true, sort: 1)
    static let cash = Account(id: StoreFixture.id(3), name: "Наличные ₾", currency: "GEL", type: .cash, includeInFree: true, sort: 2)

    let harness: RepositoryHarness
    let profileId: UUID
    let rubCard = RepositoryLedgerTests.rubCard
    let multiUsd = RepositoryLedgerTests.multiUsd
    let cash = RepositoryLedgerTests.cash
    let utc = RepositoryHarness.utc

    init() async throws {
        harness = try RepositoryHarness()
        profileId = try await harness.profile(accounts: [Self.rubCard, Self.multiUsd, Self.cash])
    }

    @discardableResult
    func book(_ draft: Draft) async throws -> [Posting] {
        let id = try await harness.repository.save(draft, profileId: profileId)
        return try #require(try await harness.operation(id, profileId)).postings
    }

    func state(_ account: Account) async throws -> AccountState {
        try await harness.state(account.id, profileId)
    }

    @Test func transferCarriesRubleCostAndAverages() async throws {
        try await book(Draft(type: .opening, timestamp: 0, accountId: rubCard.id, amountMinor: 10_000_000))
        try await book(Draft(type: .transfer, timestamp: 1, accountId: rubCard.id, amountMinor: 900_000, toAccountId: multiUsd.id, toAmountMinor: 10_000)) // 100 $ for 9 000 ₽
        try await book(Draft(type: .transfer, timestamp: 2, accountId: rubCard.id, amountMinor: 4_600_000, toAccountId: multiUsd.id, toAmountMinor: 50_000)) // 500 $ for 46 000 ₽
        #expect(try await state(multiUsd).balanceMinor == 60_000)
        expectClose(try #require(try await state(multiUsd).costBasis), 91.666, 0.001)
        #expect(try await state(rubCard).balanceMinor == 4_500_000)
    }

    @Test func spendingUsesAverageCostNotOfficialRate() async throws {
        try await book(Draft(type: .opening, timestamp: 0, accountId: rubCard.id, amountMinor: 4_600_000))
        try await book(Draft(type: .transfer, timestamp: 1, accountId: rubCard.id, amountMinor: 4_600_000, toAccountId: multiUsd.id, toAmountMinor: 50_000))
        // 80 ฿ coffee charged as 2.41 $: 2.41 × 92 = 221.72 ₽, not 2.41 × 83.25.
        let coffee = try await book(Draft(type: .expense, timestamp: 2, accountId: multiUsd.id, amountMinor: 241))
        #expect(coffee.count == 1)
        #expect(coffee[0].rubMinor == -22_172)
    }

    @Test func spendingTheWholeBalanceLeavesNoRubleDust() async throws {
        try await book(Draft(type: .opening, timestamp: 0, accountId: rubCard.id, amountMinor: 1_000_000))
        try await book(Draft(type: .transfer, timestamp: 1, accountId: rubCard.id, amountMinor: 1_000_000, toAccountId: multiUsd.id, toAmountMinor: 10_900))
        try await book(Draft(type: .expense, timestamp: 2, accountId: multiUsd.id, amountMinor: 3_333))
        try await book(Draft(type: .expense, timestamp: 3, accountId: multiUsd.id, amountMinor: 7_567))
        #expect(try await state(multiUsd).balanceMinor == 0)
        #expect(try await state(multiUsd).rubMinor == 0)
    }

    @Test func atmWithdrawalMovesCostIntoCash() async throws {
        try await book(Draft(type: .opening, timestamp: 0, accountId: rubCard.id, amountMinor: 4_600_000))
        try await book(Draft(type: .transfer, timestamp: 1, accountId: rubCard.id, amountMinor: 4_600_000, toAccountId: multiUsd.id, toAmountMinor: 50_000))
        try await book(Draft(type: .transfer, timestamp: 2, accountId: multiUsd.id, amountMinor: 10_000, toAccountId: cash.id, toAmountMinor: 26_500))
        // 100 $ at 92 ₽ became 265 ₾, so a lari cost 34.72 ₽.
        expectClose(try #require(try await state(cash).costBasis), 34.716, 0.001)
    }

    @Test func markupIsLearnedFromRubleTransfers() async throws {
        let draft = Draft(type: .transfer, timestamp: 0, accountId: rubCard.id, amountMinor: 4_600_000, toAccountId: multiUsd.id, toAmountMinor: 50_000)
        var expense = draft
        expense.type = .expense
        try await book(expense)
        #expect(try await harness.profileSettings(profileId).markup == 0.10)
        // An amount the app guessed itself says nothing about the real rate.
        var guessed = draft
        guessed.isEstimate = true
        try await book(guessed)
        #expect(try await harness.profileSettings(profileId).markup == 0.10)

        try await book(draft)
        expectClose(try await harness.profileSettings(profileId).markup, 0.1051, 0.0001)
        expectClose(try await harness.repository.settings(profileId: profileId).markup, 0.1051, 0.0001)
    }

    @Test func displayRatesCarryThePersonalMarkup() async throws {
        let rates = try await harness.repository.rates(profileId: profileId)
        // 20 ₾ at the CBR rate plus a 10 % markup.
        expectClose(Double(try #require(rates.rubMinor(2_000, "GEL"))) / 100.0, 703.1, 0.1)
        expectClose(Double(try #require(rates.convert(2_000, from: "GEL", to: "USD"))) / 100.0, 7.68, 0.01)
        expectClose(Double(try #require(rates.convert(2_000, from: "GEL", to: "THB"))) / 100.0, 258.3, 0.1)
    }

    @Test func cardChargeUsesOfficialCrossPlusCardMarkup() async throws {
        // The dollar card was used last, so a purchase in baht is charged to it.
        try await book(Draft(type: .expense, timestamp: 0, accountId: multiUsd.id, amountMinor: 100))
        let id = try #require(try await harness.repository.buy(Consider(title: "Кофе", amountMinor: 8_000, currency: "THB"), profileId: profileId))
        let coffee = try #require(try await harness.operation(id, profileId))
        // 80 ฿ from a USD card: 80 × 2.47438 / 83.2454 × 1.02 = 2.43 $
        #expect(coffee.postings.map(\.amountMinor) == [-243])
        #expect(coffee.postings.map(\.accountId) == [multiUsd.id])
        #expect(coffee.op.purchaseAmountMinor == 8_000 && coffee.op.purchaseCurrency == "THB" && coffee.op.isEstimate)
    }

    @Test func todaySplitsFreeMoneyUntilPayday() async throws {
        let morning = RepositoryHarness.today.atTimeMillis(hour: 9, in: utc)
        try await book(Draft(type: .opening, timestamp: 0, accountId: rubCard.id, amountMinor: 13_000_000)) // 130 000 ₽
        let spent = try await harness.repository.save(Draft(type: .expense, timestamp: morning, accountId: rubCard.id, amountMinor: 300_000), profileId: profileId) // 3 000 ₽ today
        let books = try await harness.snapshot(profileId)
        let settings = try await harness.repository.settings(profileId: profileId)
        let t = Budget.today(
            states: Ledger.states(books.accounts, books.operations.flatMap(\.postings)), operations: books.operations,
            settings: settings, today: RepositoryHarness.today, zone: utc
        )
        #expect(t.daysLeft == 13)
        #expect(t.perDayRub == 1_000_000) // 130 000 / 13
        #expect(t.leftTodayRub == 700_000)
        // The comment after the expense says the same.
        #expect(try await harness.repository.impact(operationId: spent, profileId: profileId) == Impact(costRub: 300_000, hoursOfWork: nil, leftTodayRub: 700_000))
    }

    /// Free money before payday, the salary on Sep 15, then [spent] rubles over the next weeks; today is Oct 2.
    func paceAfter(_ spent: Int64) async throws -> Int64? {
        func at(_ month: Int, _ day: Int) -> Int64 { LocalDate(2026, month, day).atTimeMillis(hour: 12, in: utc) }
        try await book(Draft(type: .opening, timestamp: at(9, 10), accountId: rubCard.id, amountMinor: 10_000_000)) // 100 000 ₽
        try await book(Draft(type: .income, timestamp: at(9, 15), accountId: rubCard.id, amountMinor: 9_000_000)) // salary 90 000 ₽ → 190 000 ₽ over 30 days
        try await book(Draft(type: .expense, timestamp: at(9, 20), accountId: rubCard.id, amountMinor: spent))
        return try await pace(on: RepositoryHarness.today)
    }

    func pace(on date: LocalDate) async throws -> Int64? {
        let books = try await harness.snapshot(profileId)
        let settings = try await harness.repository.settings(profileId: profileId)
        let states = Ledger.states(books.accounts, books.operations.flatMap(\.postings))
        let t = Budget.today(states: states, operations: books.operations, settings: settings, today: date, zone: utc)
        return Budget.pace(today: t, accounts: books.accounts, operations: books.operations, settings: settings, date: date, zone: utc)
    }

    @Test func spendingSlowerThanThePeriodAllowsIsAhead() async throws {
        // 60 000 ₽ in 17 days: 130 000 ₽ left for 13 days is 10 000 ₽ a day against 6 333,33 at the start.
        #expect(try await paceAfter(6_000_000) == 1_000_000 - 633_333)
    }

    @Test func spendingFasterThanThePeriodAllowsIsBehind() async throws {
        // 150 000 ₽ gone: 40 000 ₽ for 13 days is about 3 077 ₽ a day, under the 6 333 ₽ baseline.
        #expect(try #require(try await paceAfter(15_000_000)) < 0)
    }

    @Test func noPaceWithoutHistoryOrOnPayday() async throws {
        // Started using the app after the last payday: nothing to compare with.
        try await book(Draft(type: .opening, timestamp: LocalDate(2026, 9, 20).startOfDayMillis(in: utc), accountId: rubCard.id, amountMinor: 10_000_000))
        #expect(try await pace(on: RepositoryHarness.today) == nil)
        #expect(try await pace(on: LocalDate(2026, 10, 15)) == nil)
    }

    @Test func paydayRollsOverToNextMonth() async throws {
        var profile = try await harness.profileSettings(profileId)
        profile.payday = 15
        try await harness.repository.saveProfileSettings(profile, profileId: profileId)
        let s = try await harness.repository.settings(profileId: profileId)
        #expect(s.nextPayday(LocalDate(2026, 10, 2)) == LocalDate(2026, 10, 15))
        #expect(s.nextPayday(LocalDate(2026, 10, 15)) == LocalDate(2026, 11, 15))

        profile.payday = 31
        try await harness.repository.saveProfileSettings(profile, profileId: profileId)
        #expect(try await harness.repository.settings(profileId: profileId).nextPayday(LocalDate(2027, 1, 31)) == LocalDate(2027, 2, 28))
    }

    @Test func salaryAndHourAreAfterTax() async throws {
        let profile = ProfileSettings(from: Settings(incomeHourly: true, hourlyRate: 1000, taxPercent: 10, hoursPerWeek: 40))
        try await harness.repository.saveProfileSettings(profile, profileId: profileId)
        let s = try await harness.repository.settings(profileId: profileId)
        expectClose(s.hourNet, 900, 0.01)
        // September 2026 has 22 weekdays → 176 h → 176 000 ₽ → 158 400 ₽ after tax.
        expectClose(s.salaryFor(YearMonth(2026, 9)), 158_400, 0.1)
        // So 1 800 ₽ is two hours of work.
        let lunch = try await harness.repository.save(Draft(type: .expense, timestamp: RepositoryHarness.start, accountId: rubCard.id, amountMinor: 180_000), profileId: profileId)
        expectClose(try #require(try await harness.repository.impact(operationId: lunch, profileId: profileId)?.hoursOfWork), 2, 0.0001)
    }

    @Test func savingsInterestUsesMonthlyMinimum() async throws {
        let savings = Account(id: StoreFixture.id(4), name: "Накопительный", currency: "RUB", type: .savings, includeInFree: false, interestRate: 12.0, sort: 3)
        try await harness.repository.saveAccount(savings, profileId: profileId)
        func at(_ day: Int) -> Int64 { LocalDate(2026, 10, day).startOfDayMillis(in: utc) }
        try await book(Draft(type: .opening, timestamp: at(2), accountId: savings.id, amountMinor: 15_000_000))
        try await book(Draft(type: .transfer, timestamp: at(10), accountId: savings.id, amountMinor: 5_000_000, toAccountId: rubCard.id))
        try await book(Draft(type: .transfer, timestamp: at(12), accountId: rubCard.id, amountMinor: 2_000_000, toAccountId: savings.id))
        let history = try await harness.snapshot(profileId).operations
        // Minimum is 100 000 ₽: × 12 % × 31 / 365 = 1 019.18 ₽.
        #expect(Budget.interestForecast(savings, history, today: LocalDate(2026, 10, 20), zone: utc) == 101_918)
    }

    @Test func parsingAndFormatting() async throws {
        // Amounts typed the way people type them are stored and read back to the kopeck.
        let lari = try #require(Fmt.parseMinor("15,5", "GEL"))
        let rubles = try #require(Fmt.parseMinor("1 500.25", "RUB"))
        #expect(lari == 1_550 && rubles == 150_025)
        #expect(Fmt.parseMinor("abc", "RUB") == nil)
        try await book(Draft(type: .income, timestamp: 0, accountId: cash.id, amountMinor: lari))
        try await book(Draft(type: .income, timestamp: 0, accountId: rubCard.id, amountMinor: rubles))
        try await book(Draft(type: .income, timestamp: 0, accountId: rubCard.id, amountMinor: 421_050 - rubles))
        try await book(Draft(type: .expense, timestamp: 0, accountId: cash.id, amountMinor: 50))
        #expect(Fmt.amount(try await state(cash).balanceMinor, "GEL") == "15 ₾")
        #expect(Fmt.amount(try await state(rubCard).balanceMinor, "RUB") == "4\u{202F}210,50 ₽")
        #expect(Fmt.editable(try await state(cash).balanceMinor, "GEL") == "15")
        #expect(Fmt.approx(5.5, "USD") == "5,5 $")
        #expect(Fmt.approx(181.4, "THB") == "181 ฿")
    }
}
