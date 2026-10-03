import Foundation
import GoldaCore
import GoldaData
import Testing

@testable import Golda

/// The Goals tab's display models: what Android's `GoalsScreen` writes, as structure and as text in
/// both languages, from fixed books and a fixed clock.
@Suite struct GoalsModelTests {
    typealias F = HomeFixture
    typealias G = GoalsFixture

    // MARK: Hero

    @Test func theMainGoalIsTheHeroAsOnAndroidsScreenshot() throws {
        let fixture = GoalsFixture()
        let hero = try fixture.mainHero(fixture.content())

        #expect(hero.goal.name == "Велосипед")
        #expect(hero.savedMinor == 3_033_019)
        #expect(hero.saved == "30\u{202F}330,19 ₽")
        // 30 330,19 of 80 000 is 37,9 %: the bar takes the share, the text the rounded percent.
        #expect(abs(hero.progress - 0.379127) < 0.000_01)
        #expect(hero.percent == 38)
        #expect(hero.progressText(in: F.ru) == "38\u{00A0}% из 80\u{202F}000 ₽")
        #expect(hero.progressText(in: F.en) == "38\u{00A0}% of 80\u{202F}000 ₽")
        #expect(!hero.isReached)
        #expect(!hero.celebrates)
        // 250 ₾ skipped at 33 ₽ (30 ₽ and the 10 % markup).
        #expect(hero.skipped.rubMinor == 825_000)
        #expect(hero.skipped.text(in: F.ru) == "+8\u{202F}250 ₽ отказами")
        #expect(hero.skipped.text(in: F.en) == "+8\u{202F}250 ₽ from what you skipped")
    }

    @Test func withoutGoalsTheHeroAsksForOneAndStillShowsTheRefusals() {
        var fixture = GoalsFixture()
        fixture.goals = []
        let content = fixture.content()

        guard case .noGoals(let skipped) = content.hero else {
            Issue.record("expected the empty hero, got \(content.hero)")
            return
        }
        #expect(skipped.amount == "+8\u{202F}250 ₽")
        #expect(GoalsHero.caption.text(in: F.ru) == "Копилка")
        #expect(GoalsHero.setGoalTitle.text(in: F.ru) == "Поставь цель")
        #expect(GoalsHero.setGoalTitle.text(in: F.en) == "Set a goal")
        #expect(GoalsHero.setGoalText.text(in: F.ru) == "Велосипед, поездка, подушка. С ней сравнивается каждая покупка, а отказы копятся в неё.")
        #expect(content.goals.isEmpty)
        #expect(content.goalsHeader == nil)
        #expect(!content.hasMainGoal)
        // Waiting wishes say nothing of a goal there is not.
        #expect(content.waiting.map { $0.detailText(in: F.ru) } == ["через 3 дня"])
    }

    @Test func theRefusalsAreShownFromTheStartAsZero() {
        var fixture = GoalsFixture()
        fixture.wishes = [fixture.headphones, fixture.coffee]
        let skipped = SkippedTotal(wishes: fixture.wishes, rates: fixture.data.rates, base: fixture.data.base)
        #expect(skipped.rubMinor == 0)
        #expect(skipped.text(in: F.ru) == "0 ₽ отказами")
        #expect(skipped.text(in: F.en) == "0 ₽ from what you skipped")
    }

    @Test func refusalsAreCountedInTheMainCurrency() {
        var fixture = GoalsFixture()
        fixture.home.device.baseCurrency = "USD"
        let skipped = SkippedTotal(wishes: fixture.wishes, rates: fixture.data.rates, base: fixture.data.base)
        // 8 250 ₽ at 88 ₽ a dollar.
        #expect(skipped.amount == "+93,8 $")
    }

    @Test func goalsWithoutAMainOneAskToPickIt() {
        var fixture = GoalsFixture()
        fixture.bike.isMain = false
        fixture.goals = [fixture.bike, fixture.cushion]
        let content = fixture.content()

        guard case .noMainGoal = content.hero else {
            Issue.record("expected the pick-a-main-goal hero, got \(content.hero)")
            return
        }
        #expect(GoalsHero.pickMainTitle.text(in: F.ru) == "Выбери главную цель")
        #expect(GoalsHero.pickMainText.text(in: F.ru) == "Звезда в цели делает её главной")
        #expect(GoalsHero.pickMainText.text(in: F.en) == "The star in a goal makes it the main one")
        // Every goal is a row then, under "Цели".
        #expect(content.goals.map(\.goal.name) == ["Велосипед", "Подушка"])
        #expect(content.goalsHeader?.text(in: F.ru) == "Цели")
        #expect(content.waiting.map { $0.detailText(in: F.ru) } == ["через 3 дня"])
    }

    @Test func aReachedGoalFillsTheBarOffersToBuyAndCelebratesOnce() throws {
        var fixture = GoalsFixture()
        fixture.bike.savedMinor = 8_000_000
        fixture.goals = [fixture.bike, fixture.cushion]
        let hero = try fixture.mainHero(fixture.content())

        #expect(hero.isReached)
        #expect(hero.progress == 1)
        #expect(hero.percent == 100)
        #expect(hero.celebrates)
        #expect(hero.buyTitle(in: F.ru) == "Купить Велосипед · 80\u{202F}000 ₽")
        #expect(hero.buyTitle(in: F.en) == "Buy Велосипед · 80\u{202F}000 ₽")

        // Celebrated on this phone already: the wave is flat from the start, no haptics.
        let again = try fixture.mainHero(fixture.content(celebrated: fixture.bike.id))
        #expect(again.isReached)
        #expect(!again.celebrates)
        // Another goal celebrated before does not count for this one.
        #expect(try fixture.mainHero(fixture.content(celebrated: fixture.cushion.id)).celebrates)
    }

    @Test func anOvershotGoalSaysSoAndTheBarStaysFull() throws {
        var fixture = GoalsFixture()
        fixture.cushion.isMain = true
        fixture.bike.isMain = false
        fixture.goals = [fixture.cushion, fixture.bike]
        let hero = try fixture.mainHero(fixture.content())
        #expect(hero.savedMinor == 33_000_000)
        #expect(hero.percent == 110)
        #expect(hero.progress == 1)
        #expect(hero.isReached)
        #expect(hero.progressText(in: F.ru) == "110\u{00A0}% из 300\u{202F}000 ₽")
    }

    @Test func theHeroReadsAsOneSentence() throws {
        let fixture = GoalsFixture()
        let hero = try fixture.mainHero(fixture.content())
        #expect(hero.accessibilityLabel(in: F.en) == "Велосипед. 30330.19 Russian rubles. 38\u{00A0}% of 80000 Russian rubles. 8250 Russian rubles from what you skipped")
    }

    // MARK: Percent

    /// The hero rounds half up (Kotlin's `roundToLong`); the share of a wish rounds half to even
    /// (Kotlin's `round`), and "<1 %" stands for a share that has not reached half a percent.
    @Test func percentsRoundAsOnAndroid() {
        #expect(Goals.percentRounded(375, 1_000) == 38)
        #expect(Goals.percentRounded(125, 1_000) == 13)
        #expect(Goals.percentRounded(1_100, 1_000) == 110)
        #expect(Goals.percentRounded(5, 0) == 0)

        // 12,5 and 37,5 are exact in binary: the tie goes to the even neighbour.
        #expect(GoalPercent.whole(0.125) == "12\u{00A0}%")
        #expect(GoalPercent.whole(0.375) == "38\u{00A0}%")
        #expect(GoalPercent.whole(0.132) == "13\u{00A0}%")
        #expect(GoalPercent.whole(0.004) == "<1\u{00A0}%")
        #expect(GoalPercent.whole(0) == "0\u{00A0}%")
        #expect(GoalPercent.whole(2.5) == "250\u{00A0}%")
    }

    // MARK: Other goals

    @Test func theOtherGoalsAreRowsWithTheirPercentAndWhatIsSaved() {
        let fixture = GoalsFixture()
        let content = fixture.content()

        #expect(content.goals.map(\.goal.name) == ["Подушка"])
        let cushion = content.goals[0]
        #expect(cushion.saved == "330\u{202F}000 ₽")
        #expect(cushion.percent == 110)
        #expect(cushion.progress == 1)
        #expect(cushion.detailText(in: F.ru) == "110\u{00A0}% · из 300\u{202F}000 ₽")
        #expect(cushion.detailText(in: F.en) == "110\u{00A0}% · of 300\u{202F}000 ₽")
        #expect(cushion.accessibilityLabel(in: F.en) == "Подушка, 110\u{00A0}% · of 300000 Russian rubles, 330000 Russian rubles")
        #expect(content.goalsHeader?.text(in: F.ru) == "Другие цели")
        #expect(content.goalsHeader?.text(in: F.en) == "Other goals")
    }

    @Test func aGoalOnAnAccountInAnotherCurrencyCountsItsWorth() {
        var fixture = GoalsFixture()
        // 300 000 ₽ in dollars on the ruble savings: 330 000 ₽ at 88 ₽ a dollar is 3 750 $.
        fixture.cushion.currency = "USD"
        fixture.cushion.targetMinor = 500_000
        fixture.goals = [fixture.bike, fixture.cushion]
        let row = fixture.content().goals[0]
        #expect(row.savedMinor == 375_000)
        #expect(row.percent == 75)
        #expect(row.saved == "3\u{202F}750 $")
    }

    @Test func onlyTheMainGoalLeavesNoHeaderButTheAddRow() {
        var fixture = GoalsFixture()
        fixture.goals = [fixture.bike]
        let content = fixture.content()
        #expect(content.goals.isEmpty)
        #expect(content.goalsHeader == nil)
        #expect(content.hasMainGoal)
    }

    // MARK: Waiting wishes

    @Test func waitLabelsCountWholeHoursRoundedUp() {
        let now = G.now, hour = G.hour, day = G.day
        #expect(WishWait(decideAt: now + 10 * 60_000, now: now) == .left(.hours(1)))
        #expect(WishWait(decideAt: now + hour, now: now) == .left(.hours(1)))
        #expect(WishWait(decideAt: now + hour + 1, now: now) == .left(.hours(2)))
        #expect(WishWait(decideAt: now + 47 * hour, now: now) == .left(.hours(47)))
        #expect(WishWait(decideAt: now + 48 * hour, now: now) == .left(.days(2)))
        #expect(WishWait(decideAt: now + 3 * day - 1, now: now) == .left(.days(3)))
        #expect(WishWait(decideAt: now + 7 * day, now: now) == .left(.days(7)))
        #expect(WishWait(decideAt: now, now: now) == .due)
        #expect(WishWait(decideAt: now - 5 * hour, now: now) == .due)
    }

    @Test func waitLabelsTakeTheRussianForms() {
        let hours: [Int64] = [1, 2, 5, 11, 21, 22, 47]
        #expect(hours.map { WishWait.left(.hours($0)).text(in: F.ru) } == [
            "через 1 час", "через 2 часа", "через 5 часов", "через 11 часов", "через 21 час", "через 22 часа", "через 47 часов",
        ])
        #expect([Int64(2), 3, 5, 7].map { WishWait.left(.days($0)).text(in: F.ru) } == [
            "через 2 дня", "через 3 дня", "через 5 дней", "через 7 дней",
        ])
        #expect(WishWait.left(.hours(1)).text(in: F.en) == "in 1 hour")
        #expect(WishWait.left(.hours(5)).text(in: F.en) == "in 5 hours")
        #expect(WishWait.left(.days(3)).text(in: F.en) == "in 3 days")
        #expect(WishWait.due.text(in: F.ru) == "пора решать")
        #expect(WishWait.due.text(in: F.en) == "time to decide")
    }

    @Test func aWaitingWishSaysItsWaitAndShareOfTheMainGoal() {
        let fixture = GoalsFixture()
        let content = fixture.content()
        #expect(content.waiting.map(\.wish.title) == ["Наушники"])
        let headphones = content.waiting[0]
        // 120 $ at 88 ₽ is 10 560 ₽: 13,2 % of 80 000 ₽.
        #expect(abs((headphones.goalShare ?? 0) - 0.132) < 0.000_001)
        #expect(headphones.amount == "120 $")
        #expect(headphones.detailText(in: F.ru) == "через 3 дня · 13\u{00A0}% цели")
        #expect(headphones.detailText(in: F.en) == "in 3 days · 13\u{00A0}% of the goal")
        #expect(headphones.consider == Consider(title: "Наушники", amountMinor: 12_000, currency: "USD"))
        #expect(headphones.accessibilityLabel(in: F.en) == "Наушники, in 3 days · 13\u{00A0}% of the goal, 120 US dollars")

        // Its time up: "пора решать", and the share stays.
        let due = fixture.content(now: G.now + 4 * G.day).waiting[0]
        #expect(due.detailText(in: F.ru) == "пора решать · 13\u{00A0}% цели")
    }

    @Test func aTinyWishIsLessThanOnePercentOfTheGoal() {
        var fixture = GoalsFixture()
        fixture.headphones.amountMinor = 100 // 1 $ is 88 ₽, 0,11 % of the bike
        fixture.wishes = [fixture.headphones]
        #expect(fixture.content().waiting[0].detailText(in: F.ru) == "через 3 дня · <1\u{00A0}% цели")
    }

    @Test func waitingWishesComeSoonestFirstAndTiesKeepTheirOrder() {
        var fixture = GoalsFixture()
        let later = Wish(title: "Самокат", amountMinor: 1_000_000, currency: "RUB", createdAt: G.now, decideAt: G.now + 7 * G.day)
        let soon = Wish(title: "Книга", amountMinor: 100_000, currency: "RUB", createdAt: G.now, decideAt: G.now + 5 * G.hour)
        let tie = Wish(title: "Зонт", amountMinor: 200_000, currency: "RUB", createdAt: G.now, decideAt: G.now + 5 * G.hour)
        fixture.wishes = [later, fixture.headphones, soon, tie, fixture.coffee]
        let content = fixture.content()
        #expect(content.waiting.map(\.wish.title) == ["Книга", "Зонт", "Наушники", "Самокат"])
        #expect(content.waiting.map { $0.wait } == [.left(.hours(5)), .left(.hours(5)), .left(.days(3)), .left(.days(7))])
    }

    // MARK: Decided

    @Test func decidedWishesComeNewestFirstAndSayWhatWasDecided() {
        let fixture = GoalsFixture()
        let content = fixture.content()
        #expect(content.decided.map(\.wish.title) == ["Кофемашина", "Кроссовки"])
        #expect(content.decidedCount == 2)
        #expect(content.decided.map { $0.detailText(in: F.ru) } == ["купил", "не стал покупать"])
        #expect(content.decided.map { $0.detailText(in: F.en) } == ["bought", "skipped"])
        #expect(content.decided.map(\.amount) == ["30\u{202F}000 ₽", "250 ₾"])
        #expect(content.decidedTitle(in: F.ru) == "Решено · 2")
        #expect(content.decidedTitle(in: F.en) == "Decided · 2")
    }

    @Test func theDecidedListShowsTheNewestThirtyAndCountsThemAll() {
        var fixture = GoalsFixture()
        // Forty decisions an hour apart, the oldest first; one with no time goes last.
        var wishes = (0..<40).map { i in
            Wish(
                title: "Покупка \(i)", amountMinor: 10_000, currency: "RUB", createdAt: G.now, decideAt: G.now,
                status: i.isMultiple(of: 2) ? .bought : .skipped, decidedAt: G.now - Int64(40 - i) * G.hour
            )
        }
        wishes.insert(Wish(title: "Без времени", amountMinor: 1, currency: "RUB", createdAt: 0, decideAt: 0, status: .skipped), at: 0)
        fixture.wishes = wishes
        let content = fixture.content()
        #expect(content.decidedCount == 41)
        #expect(content.decided.count == 30)
        #expect(content.decided.first?.wish.title == "Покупка 39")
        #expect(content.decided.last?.wish.title == "Покупка 10")
        #expect(content.decidedTitle(in: F.ru) == "Решено · 41")
    }

    @Test func aMissingDecisionTimeGoesLast() {
        var fixture = GoalsFixture()
        let undated = Wish(title: "Без времени", amountMinor: 1, currency: "RUB", createdAt: 0, decideAt: 0, status: .bought)
        fixture.wishes = [undated, fixture.sneakers, fixture.coffee]
        #expect(fixture.content().decided.map(\.wish.title) == ["Кофемашина", "Кроссовки", "Без времени"])
    }

    // MARK: Buying

    @Test func buyingNamesTheAccountThePurchaseComesFrom() {
        var fixture = GoalsFixture()
        let rubPlan = GoalPurchasePlan(goal: fixture.cushion, data: fixture.data, now: G.now)
        #expect(rubPlan.canBuy)
        #expect(rubPlan.accountName == "Карта ₽")
        #expect(rubPlan.title(in: F.ru) == "Купить «Подушка»?")
        #expect(rubPlan.title(in: F.en) == "Buy “Подушка”?")
        #expect(rubPlan.message(in: F.ru) == "Расход 300\u{202F}000 ₽ с «Карта ₽». Цель закроется.")
        #expect(rubPlan.message(in: F.en) == "300\u{202F}000 ₽ spent from “Карта ₽”. The goal closes.")

        // A dollar goal comes from the dollar card, as `VoiceMapper.buy` picks.
        var trip = fixture.bike
        trip.currency = "USD"
        trip.targetMinor = 150_000
        #expect(GoalPurchasePlan(goal: trip, data: fixture.data, now: G.now).accountName == "Доллары")

        // The last account used wins when it is in the goal's currency.
        fixture.home.lastUsed(fixture.home.savings)
        #expect(GoalPurchasePlan(goal: fixture.cushion, data: fixture.data, now: G.now).accountName == "Накопительный")
    }

    @Test func withNoAccountThereIsNothingToBuyFrom() {
        let fixture = GoalsFixture()
        let plan = GoalPurchasePlan(goal: fixture.cushion, data: fixture.data(accounts: []), now: G.now)
        #expect(!plan.canBuy)
        #expect(plan.message(in: F.ru) == "Нет подходящего счёта.")
        #expect(plan.message(in: F.en) == "No suitable account.")
    }

    @Test func theReportAfterBuyingSaysTheHoursAndWhatIsLeft() {
        let fixture = GoalsFixture()
        let base = fixture.data.base
        let over = GoalPurchaseReport(
            goal: fixture.cushion, impact: Impact(costRub: 30_000_000, hoursOfWork: 333.333, leftTodayRub: -29_000_000), base: base
        )
        // The symbol never wraps away from its digits.
        #expect(over.text(in: F.ru) == "Подушка · 300\u{202F}000\u{00A0}₽\n≈ 333,3 ч работы · перерасход 290\u{202F}000\u{00A0}₽")
        #expect(over.text(in: F.en) == "Подушка · 300\u{202F}000\u{00A0}₽\n≈ 333,3 h of work · over budget by 290\u{202F}000\u{00A0}₽")

        let left = GoalPurchaseReport(goal: fixture.bike, impact: Impact(costRub: 8_000_000, hoursOfWork: nil, leftTodayRub: 50_300), base: base)
        #expect(left.text(in: F.ru) == "Велосипед · 80\u{202F}000\u{00A0}₽\nна сегодня осталось 503\u{00A0}₽")
        #expect(left.text(in: F.en) == "Велосипед · 80\u{202F}000\u{00A0}₽\nleft for today 503\u{00A0}₽")

        #expect(GoalPurchaseReport(goal: fixture.bike, impact: nil, base: base).text(in: F.ru) == "Велосипед · 80\u{202F}000\u{00A0}₽")
    }

    // MARK: Toasts

    @Test func toastsNameWhatWasRemoved() {
        #expect(GoalsContent.wishRemoved("Наушники", in: F.ru) == "«Наушники» убрано")
        #expect(GoalsContent.wishRemoved("Наушники", in: F.en) == "“Наушники” removed")
        #expect(GoalsContent.goalDeleted("Велосипед", in: F.ru) == "Цель «Велосипед» удалена")
        #expect(GoalsContent.goalDeleted("Велосипед", in: F.en) == "Goal “Велосипед” deleted")
    }
}
