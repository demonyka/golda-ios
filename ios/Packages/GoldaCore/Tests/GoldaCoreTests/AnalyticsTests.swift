import Foundation
import Testing

@testable import GoldaCore

/// Port of AnalyticsTest.kt. The Kotlin category ids 1 and 2 are the keys "eating_out" and "groceries".
@Suite struct AnalyticsTests {
    let rates = Rates(["USD": 83.2454, "GEL": 31.9597], markup: 0.10)
    let rubCard = Account(id: uid(1), name: "Карта ₽", currency: "RUB", type: .card, includeInFree: true)
    let multiUsd = Account(id: uid(2), name: "Мультивалютная USD", currency: "USD", type: .card, includeInFree: true)
    let today = LocalDate(2026, 10, 2)
    let ops: [OperationFull]

    var accounts: [UUID: Account] { [rubCard.id: rubCard, multiUsd.id: multiUsd] }

    static func at(_ day: Int, _ hour: Int = 12) -> Int64 { LocalDate(2026, 10, day).atTimeMillis(hour: hour, in: utc) }
    static func atSep(_ day: Int) -> Int64 { LocalDate(2026, 9, day).atTimeMillis(hour: 12, in: utc) }

    init() {
        var nextId = 0
        func op(_ type: OpType, _ time: Int64, _ category: String?, _ postings: [Posting], cbrFrom: Double? = nil, cbrTo: Double? = nil) -> OperationFull {
            nextId += 1
            let id = uid(100 + nextId)
            return OperationFull(
                Operation(id: id, type: type, timestamp: time, categoryKey: category, cbrFrom: cbrFrom, cbrTo: cbrTo),
                postings.map { var p = $0; p.operationId = id; return p }
            )
        }
        let rub = uid(1), usd = uid(2)
        ops = [
            op(.expense, Self.at(2, 9), "eating_out", [Posting(accountId: rub, amountMinor: -50_000, rubMinor: -50_000)]),
            op(.expense, Self.at(2, 13), "groceries", [Posting(accountId: usd, amountMinor: -1_000, rubMinor: -92_000)]),
            op(.expense, Self.at(1), "eating_out", [Posting(accountId: rub, amountMinor: -30_000, rubMinor: -30_000)]),
            op(.expense, Self.atSep(20), "eating_out", [Posting(accountId: rub, amountMinor: -999_900, rubMinor: -999_900)]),
            op(.income, Self.at(1), nil, [Posting(accountId: rub, amountMinor: 100_000, rubMinor: 100_000)]),
            // 46 000 ₽ → 500 $ while the CBR said 83.25: 4 377 ₽ lost on the way.
            op(
                .transfer, Self.at(1), nil,
                [
                    Posting(accountId: rub, amountMinor: -4_600_000, rubMinor: -4_600_000),
                    Posting(accountId: usd, amountMinor: 50_000, rubMinor: 4_600_000),
                ],
                cbrFrom: 1.0, cbrTo: 83.2454
            ),
        ]
    }

    @Test func weekReport() {
        let period = Analytics.period(.week, today: today, settings: Settings())
        #expect(period == Period(from: LocalDate(2026, 9, 26), to: today))
        let r = Analytics.report(ops, accounts: accounts, period: period, today: today, zone: utc, rates: rates)
        #expect(r.days.count == 7)
        #expect(r.days.last!.rubMinor == 142_000) // 500 ₽ + 10 $ that cost 920 ₽
        #expect(r.days[r.days.count - 2].rubMinor == 30_000)
        #expect(r.spentRub == 172_000)
        #expect(r.averagePerDayRub == 172_000 / 7)
        #expect(r.categories.map(\.categoryKey) == ["groceries", "eating_out"])
        #expect(r.categories.map(\.rubMinor) == [92_000, 80_000])
        #expect(r.incomeRub == 100_000)
        #expect(r.fxLossRub == 437_730)
        #expect(r.fxVolumeRub == 4_600_000)
    }

    @Test func averageCountsOnlyDaysThatHappened() {
        let period = Period(from: LocalDate(2026, 10, 1), to: LocalDate(2026, 10, 31))
        let r = Analytics.report(ops, accounts: accounts, period: period, today: today, zone: utc, rates: rates)
        #expect(r.days.count == 31)
        #expect(r.averagePerDayRub == 172_000 / 2)
    }

    @Test func sinceLastPayday() {
        #expect(Analytics.period(.sincePayday, today: today, settings: Settings(payday: 15)).from == LocalDate(2026, 9, 15))
    }

    @Test func obligationsBeforePaydayAreSetAside() {
        let states = Ledger.states([rubCard], [Posting(accountId: rubCard.id, amountMinor: 13_000_000, rubMinor: 13_000_000)])
        let obligations = [
            Obligation(id: uid(1), name: "Кредит", amountMinor: 2_600_000, currency: "RUB", dayOfMonth: 10), // Oct 10: before payday
            Obligation(id: uid(2), name: "Подписка", amountMinor: 1_000, currency: "USD", dayOfMonth: 20), // Oct 20: after payday, not yet
            Obligation(id: uid(3), name: "Аренда", amountMinor: 50_000, currency: "GEL", dayOfMonth: 2), // today: still due
        ]
        let t = Budget.today(states: states, operations: [], settings: Settings(payday: 15), today: today, zone: utc, obligations: obligations, rates: rates)
        // 26 000 ₽ + 500 ₾ × 35.156 = 17 577.84 ₽
        #expect(t.obligationsRub == 2_600_000 + 1_757_784)
        #expect(t.perDayRub == (13_000_000 - t.obligationsRub) / 13)
    }

    @Test func nextDueRollsOverAndClamps() {
        #expect(Budget.nextDue(2, today) == LocalDate(2026, 10, 2))
        #expect(Budget.nextDue(1, today) == LocalDate(2026, 11, 1))
        #expect(Budget.nextDue(31, LocalDate(2027, 2, 1)) == LocalDate(2027, 2, 28))
    }
}
