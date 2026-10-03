import Foundation
import GoldaCore
import GoldaData
import Testing

@testable import Golda

/// What the operation form's intents do to the open profile's books, through `AppModel` and a
/// real in-memory database on the harness's fixed clock: the form's own draft goes in, and the
/// values for the toast come back.
@MainActor @Suite struct EntryIntentTests {
    /// A profile paid 1 000 ₽ an hour with 10 % tax, payday on the 10th, with a ruble card holding
    /// 10 000 ₽ and the main goal "Велосипед" (80 000 ₽, 21 500 ₽ saved).
    private func books() async throws -> (AppHarness, profile: UUID, card: Account, goal: Goal) {
        let harness = try AppHarness()
        let card = Account.card("Карта")
        let income = Settings(incomeHourly: true, hourlyRate: 1000, taxPercent: 10, payday: 10)
        let profile = try await harness.repository.createProfile(name: "Личный", settings: ProfileSettings(from: income)).id
        try await harness.repository.saveAccount(card, profileId: profile, openingMinor: 1_000_000)
        let goal = Goal(name: "Велосипед", targetMinor: 8_000_000, currency: "RUB", savedMinor: 2_150_000, isMain: true)
        try await harness.repository.saveGoal(goal, profileId: profile)
        harness.onboard(active: profile)
        await harness.model.start()
        _ = try await harness.data()
        return (harness, profile, card, goal)
    }

    @Test func aNewExpenseComesBackWithWhatItCostAndUndoTakesItAway() async throws {
        let (harness, profile, card, _) = try await books()
        var form = EntryFormModel(data: try await harness.data(), request: EntryRequest(), today: LocalDate(2026, 10, 2))
        form.pickAccount(card.id)
        form.amountText = "1800"
        form.note = "Ужин"
        let draft = try #require(form.draft(now: AppHarness.now))
        #expect(draft.timestamp == AppHarness.now)

        let saved = try await harness.model.saveEntry(draft)
        #expect(saved.profileId == profile)
        // 1 800 ₽ is two hours at 900 ₽ on hand; 10 000 ₽ over the 8 days to payday is 1 250 ₽ a
        // day, and after the dinner that is −550 ₽ for today.
        #expect(saved.impact == Impact(costRub: 180_000, hoursOfWork: 2, leftTodayRub: -55_000))
        await eventually { harness.model.data?.visibleOperations.count == 1 }
        #expect(harness.model.data?.states[card.id]?.balanceMinor == 820_000)
        #expect(harness.model.data?.settings.lastAccountId == card.id, "an expense makes its account the usual one")

        try await harness.model.undoEntry(saved)
        await eventually { harness.model.data?.visibleOperations.isEmpty == true }
        #expect(harness.model.data?.states[card.id]?.balanceMinor == 1_000_000)
    }

    @Test func anEditOrAnythingButAnExpenseHasNoImpact() async throws {
        let (harness, _, card, _) = try await books()
        let income = Draft(type: .income, timestamp: AppHarness.now, accountId: card.id, amountMinor: 500_000, categoryKey: "gift")
        let saved = try await harness.model.saveEntry(income)
        #expect(saved.impact == nil)

        await eventually { harness.model.data?.visibleOperations.count == 1 }
        let stored = try #require(harness.model.data?.visibleOperations.first)
        var form = EntryFormModel(data: try await harness.data(), request: EntryRequest(editing: stored), today: LocalDate(2026, 10, 2))
        form.amountText = "6000"
        let edit = try #require(form.draft(now: AppHarness.now))
        #expect(edit.id == stored.op.id)
        let resaved = try await harness.model.saveEntry(edit)
        #expect(resaved.operationId == stored.op.id)
        #expect(resaved.impact == nil)
        await eventually { harness.model.data?.states[card.id]?.balanceMinor == 1_600_000 }
        #expect(harness.model.data?.visibleOperations.count == 1, "the same operation, changed")
    }

    @Test func buyingAWaitingWishThroughTheFormMarksItBought() async throws {
        let (harness, profile, card, _) = try await books()
        let wish = try await harness.model.thinkAbout(Consider(title: "Наушники", amountMinor: 1_200_000, currency: "RUB"))
        var form = EntryFormModel(
            data: try await harness.data(),
            request: EntryRequest(consider: Consider(title: wish.title, amountMinor: wish.amountMinor, currency: wish.currency), wishId: wish.id),
            today: LocalDate(2026, 10, 2)
        )
        #expect(form.accountId == card.id)
        #expect(!form.offersThink)
        form.isDeciding = true
        let draft = try #require(form.purchaseDraft(now: AppHarness.now, unnamed: "Покупка"))
        _ = try await harness.model.saveEntry(draft, wishId: wish.id)

        let stored = try await harness.environment.database.read { try $0.wish(wish.id, profileId: profile) }
        #expect(stored?.status == .bought)
        #expect(stored?.decidedAt == AppHarness.now)
        await eventually { harness.model.data?.visibleOperations.first?.op.note == "Наушники" }
    }

    @Test func thinkingPutsThePurchaseOnTheWishlistForItsWait() async throws {
        let (harness, profile, _, _) = try await books()
        // 12 000 ₽ is under a tenth of September's pay (22 weekdays × 8 h × 900 ₽ = 158 400 ₽):
        // three days.
        let wish = try await harness.model.thinkAbout(Consider(title: "Наушники", amountMinor: 1_200_000, currency: "RUB"))
        #expect(wish.status == .waiting)
        #expect(wish.decideAt - wish.createdAt == 72 * 3_600_000)
        let stored = try await harness.environment.database.read { try $0.wishes(profileId: profile) }
        #expect(stored.map(\.id) == [wish.id])
    }

    @Test func skippingAddsThePriceToTheMainGoal() async throws {
        let (harness, profile, _, goal) = try await books()
        let outcome = try await harness.model.skipPurchase(Consider(title: "Кроссовки", amountMinor: 750_000, currency: "RUB"))
        #expect(outcome.goal?.id == goal.id)
        #expect(outcome.addedMinor == 750_000)
        #expect(outcome.goal?.savedMinor == 2_900_000)
        #expect(outcome.wish.status == .skipped)
        let goals = try await harness.environment.database.read { try $0.goals(profileId: profile) }
        #expect(goals.first?.savedMinor == 2_900_000)
    }

    @Test func theFactsOfAPrice() async throws {
        let (harness, _, _, _) = try await books()
        let facts = try await harness.model.purchaseFacts(Consider(title: "Куртка", amountMinor: 450_000, currency: "RUB"))
        // 4 500 ₽: five hours at 900 ₽, 3,6 days of 1 250 ₽, 5,6 % of the bike; between 2 % and
        // 10 % of September's 158 400 ₽, so three days to think.
        #expect(facts.hoursValue == 5)
        #expect(facts.daysValue == 3.6)
        #expect(facts.goalShare == 0.05625)
        #expect(facts.waitHours == 72)
    }

    @Test func deletingAndRestoringKeepsTheSameOperation() async throws {
        let (harness, _, card, _) = try await books()
        let saved = try await harness.model.saveEntry(
            Draft(type: .expense, timestamp: AppHarness.now, accountId: card.id, amountMinor: 30_000, categoryKey: "groceries")
        )
        await eventually { harness.model.data?.visibleOperations.count == 1 }
        let token = try #require(try await harness.model.deleteOperation(saved.operationId))
        await eventually { harness.model.data?.visibleOperations.isEmpty == true }
        try await harness.model.restoreOperation(token)
        await eventually { harness.model.data?.visibleOperations.count == 1 }
        #expect(harness.model.data?.visibleOperations.first?.op.id == saved.operationId)
    }

    @Test func withNoProfileOpenNothingIsWritten() async throws {
        let harness = try AppHarness()
        await harness.model.start()
        let consider = Consider(title: "x", amountMinor: 100, currency: "RUB")
        await #expect(throws: AppModelError.noProfileOpen) {
            try await harness.model.saveEntry(Draft(type: .expense, timestamp: AppHarness.now, accountId: UUID(), amountMinor: 100))
        }
        await #expect(throws: AppModelError.noProfileOpen) { try await harness.model.purchaseFacts(consider) }
        await #expect(throws: AppModelError.noProfileOpen) { try await harness.model.skipPurchase(consider) }
        await #expect(throws: AppModelError.noProfileOpen) { try await harness.model.thinkAbout(consider) }
    }
}
