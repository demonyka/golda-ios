import Foundation
import GoldaCore

public enum RepositoryError: Error, Equatable, Sendable {
    /// Every profile but one may go; the last one holds the app together.
    case lastProfile
    case unknownProfile(UUID)
    case unknownAccount(UUID)
}

/// What an expense just recorded means: "≈ 2,6 ч работы · на сегодня осталось 503 ₽". Numbers only;
/// the screen writes the sentence in the main currency.
public struct Impact: Equatable, Sendable {
    /// What the expense cost, kopecks.
    public var costRub: Int64
    /// Hours of work after tax it took; nil while no income is set.
    public var hoursOfWork: Double?
    /// "Можно сегодня" left after it, kopecks; below zero is the overspend.
    public var leftTodayRub: Int64

    public init(costRub: Int64, hoursOfWork: Double?, leftTodayRub: Int64) {
        self.costRub = costRub
        self.hoursOfWork = hoursOfWork
        self.leftTodayRub = leftTodayRub
    }
}

/// What "Не беру" did: "+50 $ к «Велосипед»", or "Сэкономлено 50 $" without a main goal.
public struct SkipOutcome: Equatable, Sendable {
    /// The refusal as it was recorded, SKIPPED.
    public var wish: Wish
    /// The main goal with the money added; nil when there is no main goal.
    public var goal: Goal?
    /// What went to the goal, in the goal's currency; nil when there is no main goal.
    public var addedMinor: Int64?

    public init(wish: Wish, goal: Goal?, addedMinor: Int64?) {
        self.wish = wish
        self.goal = goal
        self.addedMinor = addedMinor
    }
}
