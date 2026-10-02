import Foundation
import GoldaCore
import Testing

@testable import GoldaData

/// Goals and the wishlist: the data side of Android's `Wishes`.
@Suite final class RepositoryWishTests {
    let harness: RepositoryHarness
    let profileId: UUID
    let rub = RepositoryLedgerTests.rubCard
    let usd = RepositoryLedgerTests.multiUsd
    var repository: Repository { harness.repository }

    init() async throws {
        harness = try RepositoryHarness()
        profileId = try await harness.profile(accounts: [rub, usd])
    }

    func goal(_ n: Int, main: Bool = false, target: Int64 = 1_000_000, currency: String = "RUB") -> Goal {
        Goal(id: StoreFixture.id(n), name: "Цель \(n)", targetMinor: target, currency: currency, isMain: main)
    }

    func goals(_ profileId: UUID? = nil) async throws -> [Goal] {
        let profileId = profileId ?? self.profileId
        return try await harness.database.read { try $0.goals(profileId: profileId) }
    }

    func mainGoals() async throws -> [UUID] {
        try await goals().filter(\.isMain).map(\.id)
    }

    func wish(_ id: UUID) async throws -> Wish? {
        let profileId = profileId
        return try await harness.database.read { try $0.wish(id, profileId: profileId) }
    }

    // MARK: Goals

    @Test func exactlyOneGoalIsMainAndTheOldestStepsIn() async throws {
        // Ids are deliberately out of creation order: "oldest" must mean created first.
        try await repository.saveGoal(goal(9), profileId: profileId)
        #expect(try await mainGoals() == [StoreFixture.id(9)])

        try await repository.saveGoal(goal(1), profileId: profileId)
        try await repository.saveGoal(goal(5, main: true), profileId: profileId)
        #expect(try await mainGoals() == [StoreFixture.id(5)])
        #expect(try await goals().map(\.id) == [5, 9, 1].map(StoreFixture.id))

        // Unmarking the main goal hands it to the oldest.
        try await repository.saveGoal(goal(5), profileId: profileId)
        #expect(try await mainGoals() == [StoreFixture.id(9)])

        try await repository.saveGoal(goal(1, main: true), profileId: profileId)
        try await repository.deleteGoal(StoreFixture.id(1), profileId: profileId)
        #expect(try await mainGoals() == [StoreFixture.id(9)])

        try await repository.deleteGoal(StoreFixture.id(9), profileId: profileId)
        #expect(try await mainGoals() == [StoreFixture.id(5)])
        try await repository.deleteGoal(StoreFixture.id(5), profileId: profileId)
        #expect(try await goals().isEmpty)
    }

    @Test func anotherProfilesMainGoalStaysMain() async throws {
        let family = try await harness.profile("Семья")
        try await repository.saveGoal(goal(1, main: true), profileId: family)
        try await repository.saveGoal(goal(2, main: true), profileId: profileId)
        #expect(try await goals(family).map(\.isMain) == [true])
        try await repository.deleteGoal(StoreFixture.id(1), profileId: profileId)
        #expect(try await goals(family).map(\.id) == [StoreFixture.id(1)])
    }

    // MARK: Wishes

    @Test func thinkingWaitsLongerForBiggerThings() async throws {
        let now = RepositoryHarness.start
        // No income: a day for anything.
        let small = try await repository.think(Consider(title: "Книга", amountMinor: 300_000, currency: "RUB"), profileId: profileId)
        #expect(small.status == .waiting && small.createdAt == now && small.decideAt == now + 24 * 3_600_000)
        #expect(try await wish(small.id) == small)

        // 100 000 ₽ a month: 3 000 ₽ is 3 % of it, three days; 50 $ is under 2 %, a day.
        var salary = ProfileSettings()
        salary.incomeHourly = false
        salary.monthlySalary = 100_000
        try await repository.saveProfileSettings(salary, profileId: profileId)
        let bigger = try await repository.think(Consider(title: "Кроссовки", amountMinor: 300_000, currency: "RUB"), profileId: profileId)
        #expect(bigger.decideAt == now + 72 * 3_600_000)
        let dollars = try await repository.think(Consider(title: "Игра", amountMinor: 1_000, currency: "USD"), profileId: profileId)
        #expect(dollars.decideAt == now + 24 * 3_600_000)
    }

    @Test func skippingWithoutAGoalIsStillRemembered() async throws {
        let outcome = try await repository.skip(Consider(title: "Бургер", amountMinor: 5_000, currency: "USD"), profileId: profileId)
        #expect(outcome.goal == nil && outcome.addedMinor == nil)
        #expect(outcome.wish.status == .skipped && outcome.wish.decidedAt == RepositoryHarness.start)
        #expect(outcome.wish.title == "Бургер" && outcome.wish.amountMinor == 5_000 && outcome.wish.currency == "USD")
        #expect(try await wish(outcome.wish.id) == outcome.wish)
    }

    @Test func skippingAWaitingWishPutsTheMoneyTowardsTheMainGoal() async throws {
        try await repository.saveGoal(Goal(id: StoreFixture.id(50), name: "Велосипед", targetMinor: 5_000_000, currency: "RUB", savedMinor: 100), profileId: profileId)
        let consider = Consider(title: "Бургер", amountMinor: 5_000, currency: "USD")
        let waiting = try await repository.think(consider, profileId: profileId)

        harness.clock.set(RepositoryHarness.start + 3_600_000)
        let outcome = try await repository.skip(consider, wishId: waiting.id, profileId: profileId)
        // 50 $ × 83.2454 × 1.1 = 4 578,50 ₽.
        #expect(outcome.addedMinor == 457_850)
        #expect(outcome.goal?.name == "Велосипед" && outcome.goal?.savedMinor == 457_950)
        #expect(outcome.wish.id == waiting.id && outcome.wish.createdAt == waiting.createdAt)
        #expect(try await wish(waiting.id)?.status == .skipped)
        #expect(try await wish(waiting.id)?.decidedAt == RepositoryHarness.start + 3_600_000)
        #expect(try await goals().first?.savedMinor == 457_950)
        // The refusal was recorded once, on the waiting wish.
        let profileId = profileId
        #expect(try await harness.database.read { try $0.wishes(profileId: profileId) }.count == 1)
    }

    @Test func skippingConvertsIntoTheGoalsCurrency() async throws {
        try await repository.saveGoal(Goal(id: StoreFixture.id(50), name: "Поездка", targetMinor: 100_000, currency: "USD"), profileId: profileId)
        let outcome = try await repository.skip(Consider(title: "Ужин", amountMinor: 457_850, currency: "RUB"), profileId: profileId)
        #expect(outcome.addedMinor == 5_000)
        #expect(outcome.goal?.currency == "USD")
    }

    @Test func buyingRecordsTheExpenseAndClosesTheWish() async throws {
        try await repository.save(Draft(type: .opening, timestamp: 0, accountId: rub.id, amountMinor: 13_000_000), profileId: profileId)
        let consider = Consider(title: "Наушники", amountMinor: 900_000, currency: "RUB")
        let waiting = try await repository.think(consider, profileId: profileId)

        harness.clock.set(RepositoryHarness.start + 60_000)
        let id = try #require(try await repository.buy(consider, wishId: waiting.id, profileId: profileId))
        let expense = try #require(try await harness.operation(id, profileId))
        #expect(expense.op.type == .expense && expense.op.note == "Наушники" && expense.op.timestamp == RepositoryHarness.start + 60_000)
        #expect(expense.postings.map(\.accountId) == [rub.id])
        #expect(expense.postings.map(\.amountMinor) == [-900_000])
        #expect(try await wish(waiting.id)?.status == .bought)
        #expect(try await wish(waiting.id)?.decidedAt == RepositoryHarness.start + 60_000)
        #expect(harness.device.current.lastAccountId[profileId] == rub.id)
        // 130 000 ₽ over 13 days, 9 000 ₽ of today's 10 000 gone.
        #expect(try await repository.impact(operationId: id, profileId: profileId)?.leftTodayRub == 100_000)
    }

    @Test func nothingToPayFromBuysNothing() async throws {
        let empty = try await harness.profile("Пусто")
        let consider = Consider(title: "Наушники", amountMinor: 900_000, currency: "RUB")
        let waiting = try await repository.think(consider, profileId: empty)
        #expect(try await repository.buy(consider, wishId: waiting.id, profileId: empty) == nil)
        #expect(try await harness.database.read { try $0.wish(waiting.id, profileId: empty) }?.status == .waiting)
        #expect(harness.device.current.lastAccountId.isEmpty)
    }

    @Test func boughtDeletedAndRestored() async throws {
        let waiting = try await repository.think(Consider(title: "Лампа", amountMinor: 200_000, currency: "RUB"), profileId: profileId)
        harness.clock.set(RepositoryHarness.start + 5)
        try await repository.bought(wishId: waiting.id, profileId: profileId)
        let bought = try #require(try await wish(waiting.id))
        #expect(bought.status == .bought && bought.decidedAt == RepositoryHarness.start + 5)

        let deleted = try #require(try await repository.deleteWish(waiting.id, profileId: profileId))
        #expect(deleted == bought)
        #expect(try await wish(waiting.id) == nil)
        #expect(try await repository.deleteWish(waiting.id, profileId: profileId) == nil)
        try await repository.restoreWish(deleted, profileId: profileId)
        #expect(try await wish(waiting.id) == bought)
    }

    // MARK: Read models

    @Test func considerWeighsThePriceInWorkDaysAndTheGoal() async throws {
        let income = ProfileSettings(from: Settings(incomeHourly: true, hourlyRate: 1000, taxPercent: 10, hoursPerWeek: 40))
        try await repository.saveProfileSettings(income, profileId: profileId)
        try await repository.save(Draft(type: .opening, timestamp: 0, accountId: rub.id, amountMinor: 13_000_000), profileId: profileId)
        try await repository.saveGoal(Goal(id: StoreFixture.id(50), name: "Велосипед", targetMinor: 3_600_000, currency: "RUB"), profileId: profileId)

        let facts = try await repository.consider(Consider(title: "Наушники", amountMinor: 900_000, currency: "RUB"), profileId: profileId)
        #expect(facts.item == "Наушники")
        // 9 000 ₽ at 900 ₽ an hour; 10 000 ₽ a day until payday; a quarter of the bike.
        expectClose(try #require(facts.hoursValue), 10, 0.0001)
        expectClose(try #require(facts.daysValue), 0.9, 0.0001)
        #expect(facts.goalName == "Велосипед")
        expectClose(try #require(facts.goalShare), 0.25, 0.0001)
        // September paid 158 400 ₽: 9 000 ₽ is between 2 % and 10 %, three days.
        #expect(facts.waitHours == 72)
    }

    @Test func impactIsOnlyForExpenses() async throws {
        let income = try await repository.save(Draft(type: .income, timestamp: 0, accountId: rub.id, amountMinor: 100), profileId: profileId)
        #expect(try await repository.impact(operationId: income, profileId: profileId) == nil)
        #expect(try await repository.impact(operationId: StoreFixture.id(77), profileId: profileId) == nil)
    }

    @Test func todayIsTheInjectedZonesDay() async throws {
        // 23:30 UTC on Oct 1 is already Oct 2 in Tbilisi (UTC+4), where the morning expense counts.
        let tbilisi = TimeZone(secondsFromGMT: 4 * 3600)!
        let clock = harness.clock
        let repository = Repository(database: harness.database, deviceSettings: harness.device, clock: { clock.now }, zone: { tbilisi })
        try await repository.save(Draft(type: .opening, timestamp: 0, accountId: rub.id, amountMinor: 13_000_000), profileId: profileId)
        let lunch = try await repository.save(Draft(type: .expense, timestamp: LocalDate(2026, 10, 1).atTimeMillis(hour: 23, minute: 30, in: RepositoryHarness.utc), accountId: rub.id, amountMinor: 300_000), profileId: profileId)
        #expect(try await repository.impact(operationId: lunch, profileId: profileId)?.leftTodayRub == 700_000)
    }
}
