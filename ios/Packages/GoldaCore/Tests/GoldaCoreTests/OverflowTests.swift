import Foundation
import Testing

@testable import GoldaCore

/// Kotlin's Long wraps on overflow; Swift's Int64 traps. A stored amount near Int64.max (typed by
/// mistake on Android before the cap, read from a crafted backup, synced from another phone) would
/// then crash every launch as soon as the sums ran, with no way to reach the row and delete it.
/// Amounts are capped where they enter, and the sums hold at ±Int64.max (D59).
@Suite struct OverflowTests {
    let rubCard = Account(id: uid(1), name: "Карта ₽", currency: "RUB", type: .card, includeInFree: true)
    let usdCard = Account(id: uid(2), name: "Доллары", currency: "USD", type: .card, includeInFree: true)
    let today = LocalDate(2026, 10, 2)

    func op(_ n: Int, _ type: OpType, _ time: Int64, _ postings: [Posting]) -> OperationFull {
        OperationFull(
            Operation(id: uid(100 + n), type: type, timestamp: time, categoryKey: type == .expense ? "eating_out" : nil),
            postings.map { var p = $0; p.operationId = uid(100 + n); return p }
        )
    }

    // MARK: Entry

    @Test func parsingStopsAtTheCap() {
        #expect(Money.maxMinor == 1_000_000_000_000_000)
        #expect(Fmt.parseMinor("10000000000000", "RUB") == Money.maxMinor)
        #expect(Fmt.parseMinor("10000000000000,01", "RUB") == nil)
        #expect(Fmt.parseMinor("1000000000000000", "JPY") == Money.maxMinor)
        #expect(Fmt.parseMinor("1000000000000001", "JPY") == nil)
        // 1e16 dollars, the slip of the finding: refused instead of stored.
        #expect(Fmt.parseMinor("10000000000000000", "USD") == nil)
    }

    // MARK: Saturating arithmetic

    @Test func addingHoldsAtTheEndsInsteadOfTrapping() {
        #expect(Money.add(2, 3) == 5)
        #expect(Money.add(.max, 1) == .max)
        #expect(Money.add(-.max, -1) == -.max)
        #expect(Money.add(.max, .min) == -1)
        #expect(Money.subtract(5, 3) == 2)
        #expect(Money.subtract(-.max, 2) == -.max)
        #expect(Money.subtract(.max, -1) == .max)
        #expect(Money.subtract(0, .min) == .max)
        #expect([Int64.max, 1, 1].moneySum { $0 } == .max)
        // Held, not wrapped: what comes after the ceiling counts from it.
        #expect([Int64.max, 1, -5].moneySum { $0 } == .max - 5)
        // Negating a saturated sum is always safe.
        #expect(-[Int64.min, -1].moneySum { $0 } == .max)
    }

    // MARK: The sums of a launch

    /// A posting held at Int64.max (what `Money.roundHalfUp` gives a huge conversion), then any
    /// positive kopeck: the states, the day's budget, the pace and the report run without a trap.
    @Test func theLaunchSumsSurviveAHugePosting() {
        let morning = today.atTimeMillis(hour: 9, in: utc)
        let ops = [
            op(1, .income, LocalDate(2026, 9, 1).atTimeMillis(hour: 9, in: utc), [Posting(accountId: usdCard.id, amountMinor: Money.maxMinor, rubMinor: .max)]),
            op(2, .income, LocalDate(2026, 9, 2).atTimeMillis(hour: 9, in: utc), [Posting(accountId: usdCard.id, amountMinor: Money.maxMinor, rubMinor: .max)]),
            op(3, .opening, 0, [Posting(accountId: rubCard.id, amountMinor: .max, rubMinor: .max)]),
            op(4, .expense, morning, [Posting(accountId: rubCard.id, amountMinor: -.max, rubMinor: .min)]),
            op(5, .expense, morning, [Posting(accountId: rubCard.id, amountMinor: -100, rubMinor: -100)]),
        ]
        let accounts = [rubCard, usdCard]
        let states = Ledger.states(accounts, ops.flatMap(\.postings))
        #expect(states[usdCard.id]?.rubMinor == .max)
        #expect(states[usdCard.id]?.balanceMinor == 2 * Money.maxMinor)

        let settings = Settings(payday: 15)
        let budget = Budget.today(states: states, operations: ops, settings: settings, today: today, zone: utc)
        #expect(budget.freeRub == .max || budget.freeRub > 0)
        _ = Budget.pace(today: budget, accounts: accounts, operations: ops, settings: settings, date: today, zone: utc)

        let report = Analytics.report(
            ops, accounts: Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) }),
            period: Period(from: today.minusDays(6), to: today), today: today, zone: utc, rates: Rates(["USD": 90], markup: 0.1)
        )
        #expect(report.spentRub == .max)
    }

    /// Spending more than an account holds at a huge rate: the ruble value of the outflow saturates
    /// instead of trapping when its two parts are added.
    @Test func anOutflowPastTheBalanceDoesNotTrap() {
        let state = AccountState(account: usdCard, balanceMinor: 100, rubMinor: .max - 10)
        let rates = Rates(["USD": 1e17], markup: 0)
        #expect(Ledger.outflowRub(state, 200, rates) == .max)
    }

    @Test func aGoalsSavingsBesideAHugeAccountDoNotTrap() {
        let account = Account(id: uid(3), name: "Копилка", currency: "RUB", type: .savings, includeInFree: false)
        let goal = Goal(name: "Дом", targetMinor: 100, currency: "RUB", accountId: account.id, savedMinor: .max)
        let states = [account.id: AccountState(account: account, balanceMinor: .max, rubMinor: .max)]
        #expect(Goals.progressMinor(goal, states, Rates([:], markup: 0)) == .max)
    }
}
