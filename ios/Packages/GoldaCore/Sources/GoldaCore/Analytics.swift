import Foundation

/// Both ends included.
public struct Period: Equatable, Sendable {
    public let from: LocalDate
    public let to: LocalDate

    public init(from: LocalDate, to: LocalDate) {
        self.from = from
        self.to = to
    }

    public var days: [LocalDate] {
        guard from <= to else { return [] }
        return (0...LocalDate.daysBetween(from, to)).map { from.plusDays($0) }
    }
}

public enum PeriodKind: Sendable, CaseIterable {
    case week, month, sincePayday, custom
}

public struct CategorySpend: Equatable, Sendable {
    public let categoryKey: String?
    public let rubMinor: Int64
}

public struct DaySpend: Equatable, Sendable {
    public let date: LocalDate
    public let rubMinor: Int64
}

public struct Report: Equatable, Sendable {
    public let period: Period
    /// Spending per day of the period, in rubles (kopecks), oldest first.
    public let days: [DaySpend]
    public let spentRub: Int64
    public let averagePerDayRub: Int64
    /// Biggest first.
    public let categories: [CategorySpend]
    public let incomeRub: Int64
    /// What currency exchanges cost against the CBR rate.
    public let fxLossRub: Int64
    /// How many rubles' worth went through exchanges.
    public let fxVolumeRub: Int64
}

public enum Analytics {
    public static func period(_ kind: PeriodKind, today: LocalDate, settings: Settings, custom: Period? = nil) -> Period {
        switch kind {
        case .week: Period(from: today.minusDays(6), to: today)
        case .month: Period(from: today.minusDays(29), to: today)
        case .sincePayday: Period(from: settings.nextPayday(today).minusMonths(1), to: today)
        case .custom: custom ?? Period(from: today.minusDays(6), to: today)
        }
    }

    public static func report(
        _ operations: [OperationFull],
        accounts: [UUID: Account],
        period: Period,
        today: LocalDate,
        zone: TimeZone,
        rates: Rates
    ) -> Report {
        let inPeriod = operations.filter {
            let day = Ledger.localDate($0.op.timestamp, zone)
            return !day.isBefore(period.from) && !day.isAfter(period.to)
        }
        let expenses = inPeriod.filter { $0.op.type == .expense }
        // Sums held at ±Int64.max, so a stored row too big to add up cannot crash the report (D59).
        func cost(_ full: OperationFull) -> Int64 { -full.postings.moneySum(\.rubMinor) }

        var byDay: [LocalDate: Int64] = [:]
        for full in expenses {
            let day = Ledger.localDate(full.op.timestamp, zone)
            byDay[day] = Money.add(byDay[day] ?? 0, cost(full))
        }
        let spent = expenses.moneySum(cost)
        let lastCounted = min(period.to, today)
        let countedDays = max(Int64(LocalDate.daysBetween(period.from, lastCounted)) + 1, 1)

        var loss = 0.0
        var volume = 0.0
        for full in inPeriod where full.op.type == .transfer {
            guard let out = full.postings.first(where: { $0.amountMinor < 0 }),
                  let into = full.postings.first(where: { $0.amountMinor > 0 }),
                  let fromCode = accounts[out.accountId]?.currency,
                  let toCode = accounts[into.accountId]?.currency,
                  fromCode != toCode,
                  let fromRate = full.op.cbrFrom ?? rates.official(fromCode),
                  let toRate = full.op.cbrTo ?? rates.official(toCode)
            else { continue }
            let sent = Currencies.toMajor(-out.amountMinor, fromCode) * fromRate
            let received = Currencies.toMajor(into.amountMinor, toCode) * toRate
            loss += sent - received
            volume += sent
        }

        // Grouped in order of first appearance, then sorted biggest first with ties kept in that order.
        var order: [String?] = []
        var totals: [String?: Int64] = [:]
        for full in expenses {
            let key = full.op.categoryKey
            if totals[key] == nil { order.append(key) }
            totals[key] = Money.add(totals[key] ?? 0, cost(full))
        }
        let categories = order
            .map { CategorySpend(categoryKey: $0, rubMinor: totals[$0] ?? 0) }
            .stableSorted { $0.rubMinor > $1.rubMinor }

        return Report(
            period: period,
            days: period.days.map { DaySpend(date: $0, rubMinor: byDay[$0] ?? 0) },
            spentRub: spent,
            averagePerDayRub: spent / countedDays,
            categories: categories,
            incomeRub: inPeriod.filter { $0.op.type == .income }.moneySum { $0.postings.moneySum(\.rubMinor) },
            fxLossRub: Money.roundHalfUp(loss * 100),
            fxVolumeRub: Money.roundHalfUp(volume * 100)
        )
    }
}
