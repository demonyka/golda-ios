import Foundation
import GoldaCore
import GoldaData

@testable import Golda

/// One profile's goals and wishlist built by hand, no database, shaped like Android's screenshot:
/// the main goal "Велосипед" (80 000 ₽, 30 330,19 ₽ put aside), "Подушка" (300 000 ₽) on the
/// savings account that holds 330 000 ₽, "Наушники" for 120 $ waiting three more days, "Кроссовки"
/// for 250 ₾ skipped two days ago and "Кофемашина" for 30 000 ₽ bought yesterday.
///
/// The accounts and rates are `HomeFixture`'s: 80 ₽ a dollar and 30 ₽ a lari with the default
/// 10 % markup, so 120 $ are worth 10 560 ₽ and 250 ₾ are 8 250 ₽. "Now" is 2026-10-02 10:00 UTC.
struct GoalsFixture {
    typealias F = HomeFixture

    static let now = F.at(hour: 10)
    static let hour: Int64 = 3_600_000
    static let day = 24 * hour

    var home = HomeFixture()
    var bike = Goal(name: "Велосипед", targetMinor: 8_000_000, currency: "RUB", savedMinor: 3_033_019, isMain: true)
    var cushion: Goal
    var headphones = Wish(
        title: "Наушники", amountMinor: 12_000, currency: "USD", createdAt: GoalsFixture.now - day,
        decideAt: GoalsFixture.now + 3 * day
    )
    var sneakers = Wish(
        title: "Кроссовки", amountMinor: 25_000, currency: "GEL", createdAt: GoalsFixture.now - 2 * day,
        decideAt: GoalsFixture.now - 2 * day, status: .skipped, decidedAt: GoalsFixture.now - 2 * day
    )
    var coffee = Wish(
        title: "Кофемашина", amountMinor: 3_000_000, currency: "RUB", createdAt: GoalsFixture.now - 5 * day,
        decideAt: GoalsFixture.now - 2 * day, status: .bought, decidedAt: GoalsFixture.now - day
    )
    var goals: [Goal]
    var wishes: [Wish]

    init() {
        cushion = Goal(name: "Подушка", targetMinor: 30_000_000, currency: "RUB", accountId: home.savings.id)
        goals = [bike, cushion]
        wishes = [headphones, sneakers, coffee]
        // The savings hold 330 000 ₽ and the card 50 000 ₽, opened on September 1.
        home.operations = [
            F.operation(.opening, at: F.at(LocalDate(2026, 9, 1), hour: 8), [(home.savings, 33_000_000, 33_000_000)]),
            F.operation(.opening, at: F.at(LocalDate(2026, 9, 1), hour: 8), [(home.rub, 5_000_000, 5_000_000)]),
        ]
    }

    var data: AppData { data() }

    func data(goals: [Goal]? = nil, wishes: [Wish]? = nil, accounts: [Account]? = nil) -> AppData {
        AppData(
            snapshot: ProfileSnapshot(
                profile: home.profile, accounts: accounts ?? home.accounts, operations: home.operations,
                obligations: [], goals: goals ?? self.goals, wishes: wishes ?? self.wishes
            ),
            device: home.device,
            rates: [
                RateRecord(code: "USD", rubPerUnit: 80, date: "2026-10-02"),
                RateRecord(code: "GEL", rubPerUnit: 30, date: "2026-10-02"),
            ],
            zone: F.utc
        )
    }

    func content(_ data: AppData? = nil, now: Int64 = GoalsFixture.now, celebrated: UUID? = nil) -> GoalsContent {
        GoalsContent(data: data ?? self.data, now: now, celebratedGoalId: celebrated)
    }

    /// The main goal's hero; fails the test when the hero is another state.
    func mainHero(_ content: GoalsContent) throws -> MainGoalHero {
        guard case .main(let hero) = content.hero else { throw FixtureError.noMainGoal }
        return hero
    }

    enum FixtureError: Error { case noMainGoal }
}
