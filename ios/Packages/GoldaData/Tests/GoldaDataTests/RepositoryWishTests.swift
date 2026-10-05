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

    func goalCounters() async throws -> [UUID: Int64] {
        let profileId = profileId
        return try await harness.database.read { try $0.goalCreationCounters(profileId: profileId) }
    }

    @Test func anUndoneDeleteTakesTheGoalsPlaceBackSoTheOldestStillStepsIn() async throws {
        try await repository.saveGoal(goal(9, main: true), profileId: profileId)
        try await repository.saveGoal(goal(1), profileId: profileId)
        try await repository.saveGoal(goal(5), profileId: profileId)

        let deleted = try #require(try await repository.deleteGoal(StoreFixture.id(1), profileId: profileId))
        #expect(deleted.goal == goal(1) && deleted.createdAt == 2)
        try await repository.saveGoal(deleted.goal, profileId: profileId, createdAt: deleted.createdAt)
        #expect(try await goals().map(\.id) == [9, 1, 5].map(StoreFixture.id))

        // The main goal goes: the oldest left is the one undone, not the one created after it.
        try await repository.deleteGoal(StoreFixture.id(9), profileId: profileId)
        #expect(try await mainGoals() == [StoreFixture.id(1)])
        #expect(try await goals().map(\.id) == [1, 5].map(StoreFixture.id))
    }

    @Test func anUndoneDeleteOfTheMainGoalMakesItMainAgainInItsPlace() async throws {
        try await repository.saveGoal(goal(9), profileId: profileId)
        try await repository.saveGoal(goal(1, main: true), profileId: profileId)
        try await repository.saveGoal(goal(5), profileId: profileId)

        let deleted = try #require(try await repository.deleteGoal(StoreFixture.id(1), profileId: profileId))
        #expect(deleted.goal.isMain && deleted.createdAt == 2)
        #expect(try await mainGoals() == [StoreFixture.id(9)])
        try await repository.saveGoal(deleted.goal, profileId: profileId, createdAt: deleted.createdAt)
        #expect(try await mainGoals() == [StoreFixture.id(1)])
        #expect(try await goalCounters() == [StoreFixture.id(9): 1, StoreFixture.id(1): 2, StoreFixture.id(5): 3])
    }

    @Test func aGoalCreatedWhileTheLastWasDeletedMakesWayForItsUndo() async throws {
        try await repository.saveGoal(goal(9, main: true), profileId: profileId)
        try await repository.saveGoal(goal(1), profileId: profileId)
        let deleted = try #require(try await repository.deleteGoal(StoreFixture.id(1), profileId: profileId))
        // The new goal takes the number the deleted one had; the undo puts it back before the new one.
        try await repository.saveGoal(goal(5), profileId: profileId)
        try await repository.saveGoal(deleted.goal, profileId: profileId, createdAt: deleted.createdAt)
        #expect(try await goalCounters() == [StoreFixture.id(9): 1, StoreFixture.id(1): 2, StoreFixture.id(5): 3])

        try await repository.deleteGoal(StoreFixture.id(9), profileId: profileId)
        #expect(try await mainGoals() == [StoreFixture.id(1)])
    }

    @Test func deletingAGoalThatIsNotThereGivesNothingToUndo() async throws {
        let family = try await harness.profile("Семья")
        try await repository.saveGoal(goal(1), profileId: family)
        #expect(try await repository.deleteGoal(StoreFixture.id(1), profileId: profileId) == nil)
        #expect(try await repository.deleteGoal(StoreFixture.id(2), profileId: family) == nil)
        #expect(try await goals(family).map(\.id) == [StoreFixture.id(1)])
    }

    @Test func anotherProfilesMainGoalStaysMain() async throws {
        let family = try await harness.profile("Семья")
        try await repository.saveGoal(goal(1, main: true), profileId: family)
        try await repository.saveGoal(goal(2, main: true), profileId: profileId)
        #expect(try await goals(family).map(\.isMain) == [true])
        try await repository.deleteGoal(StoreFixture.id(1), profileId: profileId)
        #expect(try await goals(family).map(\.id) == [StoreFixture.id(1)])
    }

    // MARK: Obligations

    func payment(_ n: Int, day: Int, amount: Int64 = 100) -> Obligation {
        Obligation(id: StoreFixture.id(n), name: "Платёж \(n)", amountMinor: amount, currency: "RUB", dayOfMonth: day)
    }

    func payments(_ profileId: UUID? = nil) async throws -> [UUID] {
        let profileId = profileId ?? self.profileId
        return try await harness.database.read { try $0.obligations(profileId: profileId) }.map(\.id)
    }

    /// Android listed payments by `dayOfMonth, id`, its ids counting up as they were created (O10).
    @Test func paymentsOfOneDayKeepTheOrderTheyWereCreatedIn() async throws {
        // Ids are deliberately out of creation order.
        try await repository.saveObligation(payment(9, day: 5), profileId: profileId)
        try await repository.saveObligation(payment(1, day: 5), profileId: profileId)
        try await repository.saveObligation(payment(5, day: 1), profileId: profileId)
        #expect(try await payments() == [5, 9, 1].map(StoreFixture.id))

        // An edit keeps the place.
        try await repository.saveObligation(payment(9, day: 5, amount: 300), profileId: profileId)
        #expect(try await payments() == [5, 9, 1].map(StoreFixture.id))

        // Deleted and undone: back before the payment created after it.
        let deleted = try #require(try await repository.deleteObligation(StoreFixture.id(9), profileId: profileId))
        #expect(deleted.obligation == payment(9, day: 5, amount: 300) && deleted.createdAt == 1)
        #expect(try await payments() == [5, 1].map(StoreFixture.id))
        try await repository.saveObligation(deleted.obligation, profileId: profileId, createdAt: deleted.createdAt)
        #expect(try await payments() == [5, 9, 1].map(StoreFixture.id))

        // A payment added later goes after them all.
        try await repository.saveObligation(payment(2, day: 5), profileId: profileId)
        #expect(try await payments() == [5, 9, 1, 2].map(StoreFixture.id))
    }

    @Test func aPaymentCreatedWhileTheLastWasDeletedMakesWayForItsUndo() async throws {
        try await repository.saveObligation(payment(9, day: 5), profileId: profileId)
        try await repository.saveObligation(payment(1, day: 5), profileId: profileId)
        let deleted = try #require(try await repository.deleteObligation(StoreFixture.id(1), profileId: profileId))
        // The new payment takes the number the deleted one had; the undo puts it back before the new one.
        try await repository.saveObligation(payment(5, day: 5), profileId: profileId)
        try await repository.saveObligation(deleted.obligation, profileId: profileId, createdAt: deleted.createdAt)
        #expect(try await payments() == [9, 1, 5].map(StoreFixture.id))
        let profileId = profileId
        #expect(try await harness.database.read { try $0.obligationCreationCounters(profileId: profileId) } == [
            StoreFixture.id(9): 1, StoreFixture.id(1): 2, StoreFixture.id(5): 3,
        ])
    }

    @Test func deletingAPaymentOfAnotherProfileGivesNothingToUndo() async throws {
        let family = try await harness.profile("Семья")
        try await repository.saveObligation(payment(1, day: 5), profileId: family)
        #expect(try await repository.deleteObligation(StoreFixture.id(1), profileId: profileId) == nil)
        #expect(try await payments(family) == [StoreFixture.id(1)])
        // Each profile counts on its own.
        try await repository.saveObligation(payment(2, day: 5), profileId: profileId)
        let personal = profileId
        let counters = try await harness.database.read { store in
            [
                try store.createdAt(ofObligation: StoreFixture.id(1), profileId: family),
                try store.createdAt(ofObligation: StoreFixture.id(2), profileId: personal),
            ]
        }
        #expect(counters == [1, 1])
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

    @Test func skippingIsRemembered() async throws {
        let wish = try await repository.skip(Consider(title: "Бургер", amountMinor: 5_000, currency: "USD"), profileId: profileId)
        #expect(wish.status == .skipped && wish.decidedAt == RepositoryHarness.start)
        #expect(wish.title == "Бургер" && wish.amountMinor == 5_000 && wish.currency == "USD")
        #expect(try await self.wish(wish.id) == wish)
    }

    /// Money not spent is not money put aside (D63): a refusal leaves the goals as they are.
    @Test func skippingAWaitingWishClosesItAndLeavesTheGoalAlone() async throws {
        let goal = Goal(id: StoreFixture.id(50), name: "Велосипед", targetMinor: 5_000_000, currency: "RUB", savedMinor: 100, isMain: true)
        try await repository.saveGoal(goal, profileId: profileId)
        let before = try await goals()
        let consider = Consider(title: "Бургер", amountMinor: 5_000, currency: "USD")
        let waiting = try await repository.think(consider, profileId: profileId)

        harness.clock.set(RepositoryHarness.start + 3_600_000)
        let skipped = try await repository.skip(consider, wishId: waiting.id, profileId: profileId)
        #expect(skipped.id == waiting.id && skipped.createdAt == waiting.createdAt)
        #expect(try await wish(waiting.id)?.status == .skipped)
        #expect(try await wish(waiting.id)?.decidedAt == RepositoryHarness.start + 3_600_000)
        #expect(try await goals() == before)
        // The refusal was recorded once, on the waiting wish.
        let profileId = profileId
        #expect(try await harness.database.read { try $0.wishes(profileId: profileId) }.count == 1)
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

    @Test func impactIsWhatTheExpenseCostInRublesAndHours() async throws {
        let income = ProfileSettings(from: Settings(incomeHourly: true, hourlyRate: 1000, taxPercent: 10, hoursPerWeek: 40))
        try await repository.saveProfileSettings(income, profileId: profileId)
        try await repository.save(Draft(type: .opening, timestamp: 0, accountId: rub.id, amountMinor: 13_000_000), profileId: profileId)
        try await repository.save(Draft(type: .transfer, timestamp: 1, accountId: rub.id, amountMinor: 900_000, toAccountId: usd.id, toAmountMinor: 10_000), profileId: profileId)

        // 50 $ bought at 90 ₽ cost 4 500 ₽, five hours at 900 ₽ an hour (not 50 × 83.2454 × 1.1).
        let dinner = try await repository.save(Draft(type: .expense, timestamp: RepositoryHarness.start, accountId: usd.id, amountMinor: 5_000), profileId: profileId)
        let impact = try #require(try await repository.impact(operationId: dinner, profileId: profileId))
        #expect(impact.costRub == 450_000)
        expectClose(try #require(impact.hoursOfWork), 5, 0.0001)
        // Free money: 121 000 ₽ and 50 $ worth 4 500 ₽, plus today's 4 500 ₽, over 13 days, less today's.
        #expect(impact.leftTodayRub == 13_000_000 / 13 - 450_000)

        // Without an income there are no hours to show.
        try await repository.saveProfileSettings(ProfileSettings(), profileId: profileId)
        let again = try #require(try await repository.impact(operationId: dinner, profileId: profileId))
        #expect(again.costRub == 450_000 && again.hoursOfWork == nil)
    }

    @Test func impactIsOnlyForExpenses() async throws {
        let income = try await repository.save(Draft(type: .income, timestamp: 0, accountId: rub.id, amountMinor: 100), profileId: profileId)
        #expect(try await repository.impact(operationId: income, profileId: profileId) == nil)
        #expect(try await repository.impact(operationId: StoreFixture.id(77), profileId: profileId) == nil)
    }

    @Test func todayIsTheInjectedZonesDay() async throws {
        // 23:30 UTC on Oct 1 is already Oct 2 in Tbilisi (UTC+4), where the morning expense counts.
        let repository = harness.repository(zone: TimeZone(secondsFromGMT: 4 * 3600)!)
        try await repository.save(Draft(type: .opening, timestamp: 0, accountId: rub.id, amountMinor: 13_000_000), profileId: profileId)
        let lunch = try await repository.save(Draft(type: .expense, timestamp: LocalDate(2026, 10, 1).atTimeMillis(hour: 23, minute: 30, in: RepositoryHarness.utc), accountId: rub.id, amountMinor: 300_000), profileId: profileId)
        #expect(try await repository.impact(operationId: lunch, profileId: profileId)?.leftTodayRub == 700_000)
    }
}
