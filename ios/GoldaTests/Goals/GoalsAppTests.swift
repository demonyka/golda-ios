import Foundation
import GoldaCore
import GoldaData
import Testing

@testable import Golda

/// The Goals tab over the real app model: the sample books as the screen shows them, and every
/// intent of the tab through the model to the database and back to the screen.
@MainActor @Suite(.timeLimit(.minutes(1))) struct GoalsAppTests {
    typealias F = HomeFixture

    private func samples() async throws -> (AppHarness, AppData) {
        let harness = try AppHarness()
        await harness.model.start(command: .samples, profileName: "Личный")
        return (harness, try await harness.data())
    }

    private func content(_ harness: AppHarness) throws -> GoalsContent {
        let data = try #require(harness.model.data)
        return GoalsContent(data: data, now: AppHarness.now, celebratedGoalId: harness.model.celebratedGoalId)
    }

    private func goal(_ name: String, in harness: AppHarness) throws -> Goal {
        try #require(harness.model.data?.goals.first { $0.name == name })
    }

    @Test func theSampleBooksOnTheGoalsTab() async throws {
        let (harness, _) = try await samples()
        let content = try content(harness)

        guard case .main(let hero) = content.hero else {
            Issue.record("expected the main goal, got \(content.hero)")
            return
        }
        #expect(hero.goal.name == "Велосипед")
        #expect(hero.skipped.rubMinor > 0)
        #expect(hero.savedMinor == 2_150_000 + hero.skipped.rubMinor)
        #expect(content.goals.map(\.goal.name) == ["Подушка"])
        // 250 000 ₽ opened and 80 000 ₽ put in on payday: 110 % of 300 000 ₽.
        #expect(content.goals[0].percent == 110)
        #expect(content.waiting.map(\.wish.title) == ["Наушники"])
        // Put off just now; 120 $ is between 2 % and 10 % of the 158 400 ₽ pay: three days to think.
        #expect(content.waiting[0].wait == .left(.days(3)))
        #expect(content.decided.map(\.wish.title) == ["Кроссовки"])
        #expect(content.decided[0].detailText(in: F.ru) == "не стал покупать")
    }

    @Test func aGoalIsAddedAndAnotherMadeMain() async throws {
        let (harness, _) = try await samples()
        try await harness.model.saveGoal(Goal(name: "Отпуск", targetMinor: 5_000_000, currency: "RUB"))
        await eventually { harness.model.data?.goals.count == 3 }
        #expect(try content(harness).goals.map(\.goal.name) == ["Подушка", "Отпуск"])

        // The star on "Подушка": it takes over, "Велосипед" becomes another goal.
        var cushion = try goal("Подушка", in: harness)
        cushion.isMain = true
        try await harness.model.saveGoal(cushion)
        await eventually { harness.model.data?.goals.first?.name == "Подушка" }
        let content = try content(harness)
        guard case .main(let hero) = content.hero else {
            Issue.record("expected the main goal, got \(content.hero)")
            return
        }
        #expect(hero.goal.name == "Подушка")
        #expect(hero.isReached)
        #expect(hero.celebrates)
        #expect(content.goals.map(\.goal.name) == ["Велосипед", "Отпуск"])
        #expect(harness.model.data?.goals.filter(\.isMain).count == 1)
    }

    @Test func aReachedGoalIsBoughtFromTheAccountTheQuestionNamed() async throws {
        let (harness, data) = try await samples()
        var cushion = try goal("Подушка", in: harness)
        cushion.isMain = true
        try await harness.model.saveGoal(cushion)
        await eventually { harness.model.data?.goals.first?.isMain == true && harness.model.data?.goals.first?.name == "Подушка" }
        let before = try #require(harness.model.data)
        let plan = GoalPurchasePlan(goal: cushion, data: before, now: AppHarness.now)
        #expect(plan.accountName != nil)
        let accountId = try #require(before.accounts.first { $0.name == plan.accountName }?.id)
        let balance = before.states[accountId]?.balanceMinor ?? 0

        let outcome = try #require(try await harness.model.buyGoal(cushion))
        await eventually { harness.model.data?.goals.contains { $0.id == cushion.id } == false }
        let after = try #require(harness.model.data)
        // The expense of the goal's amount, from that account, named after the goal.
        let operation = try #require(after.operations.first { $0.op.id == outcome.operationId })
        #expect(operation.op.type == .expense)
        #expect(operation.op.note == "Подушка")
        #expect(operation.postings.map(\.accountId) == [accountId])
        #expect(after.states[accountId]?.balanceMinor == balance - 30_000_000)
        #expect(after.operations.count == data.operations.count + 1)
        // The goal is gone; the oldest left is the main one again.
        #expect(after.goals.map(\.name) == ["Велосипед"])
        #expect(after.goals.first?.isMain == true)
        #expect(outcome.impact?.costRub == 30_000_000)
        let report = GoalPurchaseReport(goal: cushion, impact: outcome.impact, base: after.base)
        #expect(report.text(in: F.ru).hasPrefix("Подушка · 300\u{202F}000\u{00A0}₽\n≈ "))
        #expect(report.text(in: F.ru).contains("ч работы · перерасход "))
    }

    @Test func withNoAccountTheGoalIsNotBoughtAndStays() async throws {
        let harness = try AppHarness()
        let profile = try await harness.profile("Личный")
        harness.onboard(active: profile)
        await harness.model.start()
        _ = try await harness.data()
        let bike = Goal(name: "Велосипед", targetMinor: 100, currency: "RUB", savedMinor: 100, isMain: true)
        try await harness.model.saveGoal(bike)
        await eventually { harness.model.data?.goals.count == 1 }

        #expect(try await harness.model.buyGoal(bike) == nil)
        #expect(harness.model.data?.goals.map(\.id) == [bike.id])
        #expect(harness.model.data?.operations.isEmpty == true)
    }

    @Test func aDeletedGoalComesBackMainAsItWas() async throws {
        let (harness, _) = try await samples()
        let bike = try goal("Велосипед", in: harness)
        let token = try await harness.model.deleteGoal(bike)
        await eventually { harness.model.data?.goals.map(\.name) == ["Подушка"] }
        // The main one gone, the oldest left took its place.
        #expect(harness.model.data?.goals.first?.isMain == true)

        try await harness.model.restoreGoal(token)
        await eventually { harness.model.data?.goals.count == 2 }
        #expect(harness.model.data?.goals.first == bike)
        #expect(harness.model.data?.goals.filter(\.isMain).map(\.name) == ["Велосипед"])
    }

    @Test func aRemovedWishComesBackAsItWas() async throws {
        let (harness, _) = try await samples()
        let headphones = try #require(harness.model.data?.wishes.first { $0.title == "Наушники" })
        let token = try #require(try await harness.model.deleteWish(headphones.id))
        await eventually { (try? content(harness))?.waiting.isEmpty == true }
        #expect(token.wish == headphones)

        try await harness.model.restoreWish(token)
        await eventually { harness.model.data?.wishes.contains(headphones) == true }
        #expect(try content(harness).waiting.map(\.wish) == [headphones])

        // A decided one goes the same way.
        let sneakers = try #require(harness.model.data?.wishes.first { $0.title == "Кроссовки" })
        _ = try await harness.model.deleteWish(sneakers.id)
        await eventually { (try? content(harness).decidedCount) == 0 }
        #expect(try await harness.model.deleteWish(sneakers.id) == nil)
    }

    @Test func aReachedGoalIsCelebratedOncePerProfile() async throws {
        let (harness, _) = try await samples()
        var cushion = try goal("Подушка", in: harness)
        cushion.isMain = true
        try await harness.model.saveGoal(cushion)
        await eventually { harness.model.data?.goals.first?.name == "Подушка" }
        #expect(harness.model.celebratedGoalId == nil)

        harness.model.markGoalCelebrated(cushion.id)
        await eventually { harness.model.celebratedGoalId == cushion.id }
        let profileId = try #require(harness.model.data?.profile.id)
        #expect(harness.device.current.celebratedGoalId == [profileId: cushion.id])
        guard case .main(let hero) = try content(harness).hero else {
            Issue.record("expected the main goal")
            return
        }
        #expect(hero.isReached)
        #expect(!hero.celebrates)

        // Another profile has celebrated nothing.
        let family = try await harness.model.createProfile(name: "Семья")
        await eventually { harness.model.data?.profile.id == family.id }
        #expect(harness.model.celebratedGoalId == nil)
    }
}
