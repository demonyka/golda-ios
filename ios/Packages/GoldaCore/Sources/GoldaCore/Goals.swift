import Foundation

/// How long "Подумаю" waits, for the screen to turn into "3 дня" or "12 hours".
public enum WaitSpan: Equatable, Sendable {
    case hours(Int64)
    case days(Int64)
}

/// What a purchase means, for the "хочу купить" card. Numbers only: the screen formats them.
public struct Facts: Equatable, Sendable {
    public var item: String
    /// Hours of work the price is.
    public var hoursValue: Double?
    /// Days of "можно сегодня" the price is.
    public var daysValue: Double?
    public var goalName: String?
    /// Share of the main goal the price is, 0...1 and beyond.
    public var goalShare: Double?
    /// How long "Подумаю" would wait.
    public var waitHours: Int64?

    public init(
        item: String, hoursValue: Double? = nil, daysValue: Double? = nil, goalName: String? = nil,
        goalShare: Double? = nil, waitHours: Int64? = nil
    ) {
        self.item = item
        self.hoursValue = hoursValue
        self.daysValue = daysValue
        self.goalName = goalName
        self.goalShare = goalShare
        self.waitHours = waitHours
    }
}

public enum Goals {
    /// Saved so far, in the goal's currency: the linked account plus what skipped purchases put aside.
    public static func progressMinor(_ goal: Goal, _ states: [UUID: AccountState], _ rates: Rates) -> Int64 {
        let account = goal.accountId.flatMap { states[$0] }
        let fromAccount: Int64
        if let account {
            if account.currency == goal.currency {
                fromAccount = account.balanceMinor
            } else {
                fromAccount = rates.fromRub(account.rubMinor, goal.currency).map { Currencies.toMinor($0, goal.currency) } ?? 0
            }
        } else {
            fromAccount = 0
        }
        return max(fromAccount + goal.savedMinor, 0)
    }

    public static func targetRub(_ goal: Goal, _ rates: Rates) -> Int64? {
        goal.currency == "RUB" ? goal.targetMinor : rates.rubMinor(goal.targetMinor, goal.currency)
    }

    /// How long to think before buying: a day for small things, three days for up to a tenth of a
    /// month's pay, a week for anything bigger.
    public static func waitHours(_ rubMinor: Int64, _ settings: Settings, _ month: YearMonth) -> Int64 {
        let income = settings.salaryFor(month.minusMonths(1)) * 100
        if income <= 0 || Double(rubMinor) < income * 0.02 { return 24 }
        if Double(rubMinor) < income * 0.10 { return 72 }
        return 168
    }

    public static func waitSpan(_ hours: Int64) -> WaitSpan {
        hours < 48 ? .hours(hours) : .days(hours / 24)
    }

    /// Facts about spending [rubMinor] on [item] for the "хочу купить" card.
    public static func facts(
        item: String, rubMinor: Int64, settings: Settings, perDayRub: Int64, mainGoal: Goal?, rates: Rates
    ) -> Facts {
        let hours = settings.hourNet > 0 ? Double(rubMinor) / 100.0 / settings.hourNet : nil
        let goalRub = mainGoal.flatMap { targetRub($0, rates) }.flatMap { $0 > 0 ? $0 : nil }
        return Facts(
            item: item,
            hoursValue: hours,
            daysValue: perDayRub > 0 ? Double(rubMinor) / Double(perDayRub) : nil,
            goalName: mainGoal?.name,
            goalShare: goalRub.map { Double(rubMinor) / Double($0) }
        )
    }

    public static func rubOf(_ minor: Int64, _ currency: String, _ rates: Rates) -> Int64 {
        currency == "RUB" ? minor : rates.rubMinor(minor, currency) ?? 0
    }

    public static func minorOfRub(_ rubMinor: Int64, _ currency: String, _ rates: Rates) -> Int64 {
        currency == "RUB" ? rubMinor : rates.fromRub(rubMinor, currency).map { Currencies.toMinor($0, currency) } ?? 0
    }

    public static func share(_ part: Int64, _ whole: Int64) -> Float {
        whole > 0 ? Float(min(max(Double(part) / Double(whole), 0), 1)) : 0
    }

    public static func percentRounded(_ part: Int64, _ whole: Int64) -> Int64 {
        whole > 0 ? Money.roundHalfUp(Double(part) * 100.0 / Double(whole)) : 0
    }
}
