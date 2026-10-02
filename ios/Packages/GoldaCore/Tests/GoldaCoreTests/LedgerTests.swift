import Foundation
import Testing

@testable import GoldaCore

/// Port of LedgerTest.kt.
@Suite final class LedgerTests {
    let rates = Rates(["USD": 83.2454, "GEL": 31.9597, "THB": 2.47438], markup: 0.10)
    let rubCard = Account(id: uid(1), name: "Карта ₽", currency: "RUB", type: .card, includeInFree: true)
    let multiUsd = Account(id: uid(2), name: "Мультивалютная USD", currency: "USD", type: .card, includeInFree: true)
    let cash = Account(id: uid(3), name: "Наличные ₾", currency: "GEL", type: .cash, includeInFree: true)
    var ops: [OperationFull] = []

    var accounts: [Account] { [rubCard, multiUsd, cash] }

    @discardableResult
    func book(_ draft: Draft) throws -> [Posting] {
        let states = Ledger.states(accounts, ops.flatMap(\.postings))
        let postings = try Ledger.postings(draft, states, rates)
        let id = uid(1000 + ops.count + 1)
        ops.append(OperationFull(
            Operation(id: id, type: draft.type, timestamp: draft.timestamp),
            postings.map { var p = $0; p.operationId = id; return p }
        ))
        return postings
    }

    func state(_ account: Account) -> AccountState {
        Ledger.states(accounts, ops.flatMap(\.postings))[account.id]!
    }

    @Test func transferCarriesRubleCostAndAverages() throws {
        try book(Draft(type: .opening, timestamp: 0, accountId: rubCard.id, amountMinor: 10_000_000))
        try book(Draft(type: .transfer, timestamp: 1, accountId: rubCard.id, amountMinor: 900_000, toAccountId: multiUsd.id, toAmountMinor: 10_000)) // 100 $ for 9 000 ₽
        try book(Draft(type: .transfer, timestamp: 2, accountId: rubCard.id, amountMinor: 4_600_000, toAccountId: multiUsd.id, toAmountMinor: 50_000)) // 500 $ for 46 000 ₽
        #expect(state(multiUsd).balanceMinor == 60_000)
        expectClose(state(multiUsd).costBasis!, 91.666, 0.001)
        #expect(state(rubCard).balanceMinor == 4_500_000)
    }

    @Test func spendingUsesAverageCostNotOfficialRate() throws {
        try book(Draft(type: .opening, timestamp: 0, accountId: rubCard.id, amountMinor: 4_600_000))
        try book(Draft(type: .transfer, timestamp: 1, accountId: rubCard.id, amountMinor: 4_600_000, toAccountId: multiUsd.id, toAmountMinor: 50_000))
        // 80 ฿ coffee charged as 2.41 $: 2.41 × 92 = 221.72 ₽, not 2.41 × 83.25.
        let coffee = try book(Draft(type: .expense, timestamp: 2, accountId: multiUsd.id, amountMinor: 241))
        #expect(coffee.count == 1)
        #expect(coffee[0].rubMinor == -22_172)
    }

    @Test func spendingTheWholeBalanceLeavesNoRubleDust() throws {
        try book(Draft(type: .opening, timestamp: 0, accountId: rubCard.id, amountMinor: 1_000_000))
        try book(Draft(type: .transfer, timestamp: 1, accountId: rubCard.id, amountMinor: 1_000_000, toAccountId: multiUsd.id, toAmountMinor: 10_900))
        try book(Draft(type: .expense, timestamp: 2, accountId: multiUsd.id, amountMinor: 3_333))
        try book(Draft(type: .expense, timestamp: 3, accountId: multiUsd.id, amountMinor: 7_567))
        #expect(state(multiUsd).balanceMinor == 0)
        #expect(state(multiUsd).rubMinor == 0)
    }

    @Test func atmWithdrawalMovesCostIntoCash() throws {
        try book(Draft(type: .opening, timestamp: 0, accountId: rubCard.id, amountMinor: 4_600_000))
        try book(Draft(type: .transfer, timestamp: 1, accountId: rubCard.id, amountMinor: 4_600_000, toAccountId: multiUsd.id, toAmountMinor: 50_000))
        try book(Draft(type: .transfer, timestamp: 2, accountId: multiUsd.id, amountMinor: 10_000, toAccountId: cash.id, toAmountMinor: 26_500))
        // 100 $ at 92 ₽ became 265 ₾, so a lari cost 34.72 ₽.
        expectClose(state(cash).costBasis!, 34.716, 0.001)
    }

    @Test func markupIsLearnedFromRubleTransfers() {
        let states = Ledger.states(accounts, [])
        let draft = Draft(type: .transfer, timestamp: 0, accountId: rubCard.id, amountMinor: 4_600_000, toAccountId: multiUsd.id, toAmountMinor: 50_000)
        expectClose(Ledger.learnedMarkup(draft, states, rates)!, 0.1051, 0.0001)
        var expense = draft
        expense.type = .expense
        #expect(Ledger.learnedMarkup(expense, states, rates) == nil)
        // An amount the app guessed itself says nothing about the real rate.
        var guessed = draft
        guessed.isEstimate = true
        #expect(Ledger.learnedMarkup(guessed, states, rates) == nil)
    }

    @Test func displayRatesCarryThePersonalMarkup() {
        // 20 ₾ at the CBR rate plus a 10 % markup.
        expectClose(Double(rates.rubMinor(2_000, "GEL")!) / 100.0, 703.1, 0.1)
        expectClose(Double(rates.convert(2_000, from: "GEL", to: "USD")!) / 100.0, 7.68, 0.01)
        expectClose(Double(rates.convert(2_000, from: "GEL", to: "THB")!) / 100.0, 258.3, 0.1)
    }

    @Test func cardChargeUsesOfficialCrossPlusCardMarkup() {
        // 80 ฿ from a USD card: 80 × 2.47438 / 83.2454 × 1.02 = 2.43 $
        #expect(rates.cardCharge(8_000, purchase: "THB", account: "USD") == 243)
    }

    @Test func todaySplitsFreeMoneyUntilPayday() throws {
        let settings = Settings(payday: 15)
        let today = LocalDate(2026, 10, 2)
        let morning = today.atTimeMillis(hour: 9, in: utc)
        try book(Draft(type: .opening, timestamp: 0, accountId: rubCard.id, amountMinor: 13_000_000)) // 130 000 ₽
        try book(Draft(type: .expense, timestamp: morning, accountId: rubCard.id, amountMinor: 300_000)) // 3 000 ₽ today
        let t = Budget.today(states: Ledger.states(accounts, ops.flatMap(\.postings)), operations: ops, settings: settings, today: today, zone: utc)
        #expect(t.daysLeft == 13)
        #expect(t.perDayRub == 1_000_000) // 130 000 / 13
        #expect(t.leftTodayRub == 700_000)
    }

    /// Free money before payday, the salary on Sep 15, then [spent] rubles over the next weeks; today is Oct 2.
    func paceAfter(_ spent: Int64) throws -> Int64? {
        let settings = Settings(payday: 15)
        let today = LocalDate(2026, 10, 2)
        func at(_ month: Int, _ day: Int) -> Int64 { LocalDate(2026, month, day).atTimeMillis(hour: 12, in: utc) }
        try book(Draft(type: .opening, timestamp: at(9, 10), accountId: rubCard.id, amountMinor: 10_000_000)) // 100 000 ₽
        try book(Draft(type: .income, timestamp: at(9, 15), accountId: rubCard.id, amountMinor: 9_000_000)) // salary 90 000 ₽ → 190 000 ₽ over 30 days
        try book(Draft(type: .expense, timestamp: at(9, 20), accountId: rubCard.id, amountMinor: spent))
        let t = Budget.today(states: Ledger.states(accounts, ops.flatMap(\.postings)), operations: ops, settings: settings, today: today, zone: utc)
        return Budget.pace(today: t, accounts: accounts, operations: ops, settings: settings, date: today, zone: utc)
    }

    @Test func spendingSlowerThanThePeriodAllowsIsAhead() throws {
        // 60 000 ₽ in 17 days: 130 000 ₽ left for 13 days is 10 000 ₽ a day against 6 333,33 at the start.
        #expect(try paceAfter(6_000_000) == 1_000_000 - 633_333)
    }

    @Test func spendingFasterThanThePeriodAllowsIsBehind() throws {
        // 150 000 ₽ gone: 40 000 ₽ for 13 days is about 3 077 ₽ a day, under the 6 333 ₽ baseline.
        #expect(try paceAfter(15_000_000)! < 0)
    }

    @Test func noPaceWithoutHistoryOrOnPayday() throws {
        let settings = Settings(payday: 15)
        let today = LocalDate(2026, 10, 2)
        // Started using the app after the last payday: nothing to compare with.
        try book(Draft(type: .opening, timestamp: LocalDate(2026, 9, 20).startOfDayMillis(in: utc), accountId: rubCard.id, amountMinor: 10_000_000))
        let states = Ledger.states(accounts, ops.flatMap(\.postings))
        #expect(Budget.pace(today: Budget.today(states: states, operations: ops, settings: settings, today: today, zone: utc), accounts: accounts, operations: ops, settings: settings, date: today, zone: utc) == nil)
        let payday = LocalDate(2026, 10, 15)
        #expect(Budget.pace(today: Budget.today(states: states, operations: ops, settings: settings, today: payday, zone: utc), accounts: accounts, operations: ops, settings: settings, date: payday, zone: utc) == nil)
    }

    @Test func paydayRollsOverToNextMonth() {
        let s = Settings(payday: 15)
        #expect(s.nextPayday(LocalDate(2026, 10, 2)) == LocalDate(2026, 10, 15))
        #expect(s.nextPayday(LocalDate(2026, 10, 15)) == LocalDate(2026, 11, 15))
        #expect(Settings(payday: 31).nextPayday(LocalDate(2027, 1, 31)) == LocalDate(2027, 2, 28))
    }

    @Test func salaryAndHourAreAfterTax() {
        let s = Settings(incomeHourly: true, hourlyRate: 1000, taxPercent: 10, hoursPerWeek: 40)
        expectClose(s.hourNet, 900, 0.01)
        // September 2026 has 22 weekdays → 176 h → 176 000 ₽ → 158 400 ₽ after tax.
        expectClose(s.salaryFor(YearMonth(2026, 9)), 158_400, 0.1)
    }

    @Test func savingsInterestUsesMonthlyMinimum() {
        let savings = Account(id: uid(4), name: "Накопительный", currency: "RUB", type: .savings, includeInFree: false, interestRate: 12.0)
        let today = LocalDate(2026, 10, 20)
        func at(_ day: Int) -> Int64 { LocalDate(2026, 10, day).startOfDayMillis(in: utc) }
        let history = [
            OperationFull(Operation(id: uid(1), type: .opening, timestamp: at(2)), [Posting(id: uid(11), operationId: uid(1), accountId: savings.id, amountMinor: 15_000_000, rubMinor: 15_000_000)]),
            OperationFull(Operation(id: uid(2), type: .transfer, timestamp: at(10)), [Posting(id: uid(12), operationId: uid(2), accountId: savings.id, amountMinor: -5_000_000, rubMinor: -5_000_000)]),
            OperationFull(Operation(id: uid(3), type: .transfer, timestamp: at(12)), [Posting(id: uid(13), operationId: uid(3), accountId: savings.id, amountMinor: 2_000_000, rubMinor: 2_000_000)]),
        ]
        // Minimum is 100 000 ₽: × 12 % × 31 / 365 = 1 019.18 ₽.
        #expect(Budget.interestForecast(savings, history, today: today, zone: utc) == 101_918)
    }

    @Test func parsingAndFormatting() {
        #expect(Fmt.parseMinor("15,5", "GEL") == 1_550)
        #expect(Fmt.parseMinor("1 500.25", "RUB") == 150_025)
        #expect(Fmt.parseMinor("abc", "RUB") == nil)
        #expect(Fmt.amount(1_500, "GEL") == "15 ₾")
        #expect(Fmt.amount(421_050, "RUB") == "4\u{202F}210,50 ₽")
        #expect(Fmt.approx(5.5, "USD") == "5,5 $")
        #expect(Fmt.approx(181.4, "THB") == "181 ฿")
        #expect(Fmt.editable(1_500, "GEL") == "15")
    }
}
