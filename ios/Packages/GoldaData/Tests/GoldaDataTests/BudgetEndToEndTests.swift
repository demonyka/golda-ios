import Foundation
import GoldaCore
import Testing

@testable import GoldaData

/// "Можно сегодня" through the whole stack: the repository writes, the snapshot reads, the profile's
/// settings are composed with the phone's, and `Budget` does the sums.
@Suite(.timeLimit(.minutes(1))) struct BudgetEndToEndTests {
    let harness: RepositoryHarness
    let utc = RepositoryHarness.utc

    init() throws {
        harness = try RepositoryHarness()
    }

    var repository: Repository { harness.repository }

    /// Both numbers of the main screen, worked out from a profile's snapshot the way the app will.
    struct DayBudget: Equatable {
        var today: Today
        var pace: Int64?
    }

    func budget(_ profileId: UUID) async throws -> DayBudget {
        let books = try await harness.snapshot(profileId)
        let settings = Settings(profile: books.profile.settings, device: harness.device.current, profileId: profileId)
        let rates = try await repository.rates(profileId: profileId)
        let date = LocalDate(epochMillis: harness.clock.now, in: utc)
        let states = Ledger.states(books.accounts, books.operations.flatMap(\.postings))
        let obligations = books.obligations + Debts.obligations(books.accounts, states)
        let today = Budget.today(
            states: states, operations: books.operations, settings: settings, today: date, zone: utc,
            obligations: obligations, rates: rates
        )
        let pace = Budget.pace(
            today: today, accounts: books.accounts, operations: books.operations, settings: settings, date: date,
            zone: utc, obligations: obligations, rates: rates
        )
        return DayBudget(today: today, pace: pace)
    }

    // MARK: Two profiles

    /// "Личный": payday on the 10th, one free card with 10 000 ₽. "Семья": payday on the 25th, two free
    /// accounts with 25 000 ₽, savings kept out of the sums, and the rent on the 15th.
    func twoProfiles() async throws -> (personal: UUID, family: UUID) {
        let personal = try await harness.profile("Личный", settings: ProfileSettings(from: Settings(payday: 10)))
        let family = try await harness.profile("Семья", settings: ProfileSettings(from: Settings(payday: 25)))
        try await repository.saveAccount(
            Account(name: "Карта ₽", currency: "RUB", type: .card, includeInFree: true, sort: 0), profileId: personal,
            openingMinor: 1_000_000
        )
        try await repository.saveAccount(
            Account(name: "Общая карта", currency: "RUB", type: .card, includeInFree: true, sort: 0), profileId: family,
            openingMinor: 2_000_000
        )
        try await repository.saveAccount(
            Account(name: "Наличные", currency: "RUB", type: .cash, includeInFree: true, sort: 1), profileId: family,
            openingMinor: 500_000
        )
        try await repository.saveAccount(
            Account(name: "Накопления", currency: "RUB", type: .savings, includeInFree: false, sort: 2), profileId: family,
            openingMinor: 9_000_000
        )
        try await repository.saveObligation(
            Obligation(name: "Аренда", amountMinor: 300_000, currency: "RUB", dayOfMonth: 15), profileId: family
        )
        return (personal, family)
    }

    @Test func twoProfilesCountTheirOwnToday() async throws {
        let (personal, family) = try await twoProfiles()
        let mine = try await budget(personal).today
        let ours = try await budget(family).today

        // 2026-10-02: eight days to the 10th, 23 to the 25th.
        #expect(mine.nextPayday == LocalDate(2026, 10, 10) && mine.daysLeft == 8)
        #expect(mine.freeRub == 1_000_000 && mine.obligationsRub == 0)
        #expect(mine.perDayRub == 125_000 && mine.leftTodayRub == 125_000)

        #expect(ours.nextPayday == LocalDate(2026, 10, 25) && ours.daysLeft == 23)
        #expect(ours.freeRub == 2_500_000)
        // The rent falls on the 15th, before payday, so it is set aside.
        #expect(ours.obligationsRub == 300_000)
        #expect(ours.perDayRub == (2_500_000 - 300_000) / 23)
        #expect(ours.leftTodayRub == ours.perDayRub)
    }

    @Test func spendingInOneProfileLeavesTheOtherAlone() async throws {
        let (personal, family) = try await twoProfiles()
        let familyBefore = try await budget(family)
        let card = try #require(try await harness.snapshot(personal).accounts.first)

        try await repository.save(
            Draft(type: .expense, timestamp: harness.clock.now, accountId: card.id, amountMinor: 20_000, categoryKey: "groceries"),
            profileId: personal
        )

        let mine = try await budget(personal).today
        #expect(mine.freeRub == 980_000 && mine.spentTodayRub == 20_000)
        // The day's budget was set at the start of the day, so the spending comes off what is left.
        #expect(mine.perDayRub == 125_000 && mine.leftTodayRub == 105_000)
        #expect(try await budget(family) == familyBefore)
    }

    @Test(arguments: [true, false])
    func deletingOneProfileChangesNothingInTheOther(deleteFamily: Bool) async throws {
        let (personal, family) = try await twoProfiles()
        let card = try #require(try await harness.snapshot(personal).accounts.first)
        try await repository.save(
            Draft(type: .expense, timestamp: harness.clock.now, accountId: card.id, amountMinor: 20_000), profileId: personal
        )
        let (gone, kept) = deleteFamily ? (family, personal) : (personal, family)
        let before = try await budget(kept)
        let booksBefore = try await harness.snapshot(kept)

        try await repository.deleteProfile(gone)

        #expect(try await harness.database.read { try $0.snapshot(profileId: gone) } == nil)
        #expect(try await harness.snapshot(kept) == booksBefore)
        #expect(try await budget(kept) == before)
    }

    // MARK: The sample life

    func atNoon(_ date: LocalDate) {
        harness.clock.set(date.atTimeMillis(hour: 10, in: utc))
    }

    @Test func samplesGiveAPositiveBudgetAndAPaceOnceThereIsHistory() async throws {
        // The 15th: the last payday (the 10th) is behind the pay that landed on the 3rd, so the period
        // has something to be compared with.
        atNoon(LocalDate(2026, 10, 15))
        let profileId = try await Demo.samples(repository)
        let books = try await harness.snapshot(profileId)
        let result = try await budget(profileId)
        let today = result.today
        let rates = try await repository.rates(profileId: profileId)

        #expect(today.freeRub > 0)
        // Payday is the 10th: 26 days from 2026-10-15 to 2026-11-10.
        #expect(today.nextPayday == LocalDate(2026, 11, 10) && today.daysLeft == 26)

        // The rent and the subscriptions on the 1st, the card's minimum on the 25th and the loan on the
        // 5th all fall before payday and are set aside; the rent is in lari, at the display rate.
        let rent = try #require(rates.rubMinor(90_000, "GEL"))
        #expect(today.obligationsRub == rent + 69_900 + 300_000 + 1_000_000)

        // Two coffees and a shawarma today, all paid in cash.
        let dayStart = LocalDate(2026, 10, 15).startOfDayMillis(in: utc)
        let freeIds = Set(books.accounts.filter(Budget.isFree).map(\.id))
        let spent = books.operations
            .filter { $0.op.type == .expense && $0.op.timestamp >= dayStart }
            .flatMap(\.postings).filter { freeIds.contains($0.accountId) }
            .reduce(Int64(0)) { $0 - $1.rubMinor }
        #expect(spent > 0 && today.spentTodayRub == spent)
        #expect(today.perDayRub == (today.freeRub + spent - today.obligationsRub) / 26)
        #expect(today.leftTodayRub == today.perDayRub - spent)

        // Pace: today's per-day against the one the period started with, the free money at the end of the
        // 10th spread over the 31 days from the 10th to the 10th.
        let pace = try #require(result.pace)
        let periodStart = LocalDate(2026, 10, 10)
        let freeThen = books.operations
            .filter { $0.op.timestamp < periodStart.plusDays(1).startOfDayMillis(in: utc) }
            .flatMap(\.postings).filter { freeIds.contains($0.accountId) }
            .reduce(Int64(0)) { $0 + $1.rubMinor }
        #expect(pace == today.perDayRub - (freeThen - today.obligationsRub) / 31)
    }

    @Test func samplesOnTheSecondOfTheMonthHaveNoPaceYet() async throws {
        // All the history is newer than the last payday (September 10th), so there is nothing to compare with.
        let profileId = try await Demo.samples(repository)
        let result = try await budget(profileId)

        #expect(result.pace == nil)
        #expect(result.today.freeRub > 0)
        #expect(result.today.nextPayday == LocalDate(2026, 10, 10) && result.today.daysLeft == 8)
        // Only the loan's payment on the 5th falls before payday; the rent and the subscriptions wait for November.
        #expect(result.today.obligationsRub == 1_000_000)
    }
}
