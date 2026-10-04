import Foundation
import GoldaCore
import Testing

@testable import Golda

/// The goal form's rules, those of Android's `GoalSheet`: what it starts with, what makes it valid,
/// the goal saving hands over, and how the star keeps exactly one main goal.
@Suite struct GoalFormModelTests {
    typealias F = HomeFixture

    private func form(_ fixture: GoalsFixture = GoalsFixture(), editing: Goal? = nil, goals: [Goal]? = nil) -> GoalFormModel {
        GoalFormModel(data: fixture.data(goals: goals), editing: editing)
    }

    // MARK: Starting

    @Test func aNewGoalStartsEmptyInTheFirstForeignShownCurrency() {
        let form = form()
        #expect(form.isNew)
        #expect(form.name.isEmpty)
        #expect(form.targetText.isEmpty)
        #expect(form.savedText.isEmpty)
        #expect(form.accountId == nil)
        // Shown: RUB, USD, GEL; the ruble is skipped, as on Android.
        #expect(form.currency == "USD")
        #expect(form.preferredCurrencies == ["GEL", "RUB", "USD"])
        #expect(form.accounts.map(\.name) == ["Карта ₽", "Наличные ₾", "Доллары", "Накопительный"])
        #expect(!form.canSave)
        #expect(form.title.text(in: F.ru) == "Новая цель")
        #expect(form.title.text(in: F.en) == "New goal")
        #expect(form.saveTitle.text(in: F.ru) == "Добавить")
    }

    @Test func onlyRublesShownStartsInRubles() {
        var fixture = GoalsFixture()
        fixture.home.device.displayCurrencies = ["RUB"]
        fixture.home.device.localCurrency = "RUB"
        #expect(form(fixture).currency == "RUB")
    }

    @Test func anExistingGoalOpensAsItIs() {
        var fixture = GoalsFixture()
        fixture.bike.savedMinor = 3_033_019
        let form = form(fixture, editing: fixture.bike)
        #expect(!form.isNew)
        #expect(form.goalId == fixture.bike.id)
        #expect(form.name == "Велосипед")
        #expect(form.currency == "RUB")
        // The big field groups thousands; the plain one does not, as on Android.
        #expect(form.targetText == "80\u{202F}000")
        #expect(form.savedText == "30330,19")
        #expect(form.isMain)
        #expect(form.title.text(in: F.ru) == "Цель")
        #expect(form.title.text(in: F.en) == "Goal")
        #expect(form.saveTitle.text(in: F.ru) == "Сохранить")
        #expect(form.output == fixture.bike)
    }

    @Test func aGoalOnAnAccountKeepsWhatRefusalsPutAside() {
        var fixture = GoalsFixture()
        fixture.cushion.savedMinor = 825_000
        var form = form(fixture, editing: fixture.cushion)
        #expect(form.accountId == fixture.home.savings.id)
        #expect(form.accountName == "Накопительный")
        #expect(form.output?.savedMinor == 825_000)
        // Taken off the account, the same amount shows as put aside.
        form.accountId = nil
        #expect(form.output?.accountId == nil)
        #expect(form.output?.savedMinor == 825_000)
    }

    // MARK: Reading what was typed

    @Test func savingNeedsANameAndATargetAboveNothing() {
        var form = form()
        form.name = "  Отпуск  "
        #expect(!form.canSave)
        form.targetText = "0"
        #expect(!form.canSave)
        #expect(form.isTargetInvalid)
        form.targetText = "1\u{202F}500,5"
        #expect(form.canSave)
        #expect(!form.isTargetInvalid)
        let goal = form.output
        #expect(goal?.name == "Отпуск")
        #expect(goal?.targetMinor == 150_050)
        #expect(goal?.currency == "USD")
        #expect(goal?.savedMinor == 0)
        #expect(goal?.id == form.goalId)

        form.name = "   "
        #expect(!form.canSave)
    }

    @Test func whatIsPutAsideMustBeReadable() {
        var form = form()
        form.name = "Отпуск"
        form.targetText = "1000"
        form.savedText = "abc"
        #expect(form.isSavedInvalid)
        #expect(!form.canSave)
        form.savedText = "250,5"
        #expect(form.output?.savedMinor == 25_050)
    }

    @Test func theTargetIsReadInTheCurrencyPicked() {
        var form = form()
        form.name = "Отпуск"
        form.targetText = "1000"
        form.currency = "JPY"
        #expect(form.output?.targetMinor == 1_000)
        #expect(form.output?.currency == "JPY")
    }

    // MARK: The main goal

    @Test func theFirstGoalIsTheMainOneAndCannotBeOtherwise() {
        var form = form(goals: [])
        #expect(form.isMain)
        #expect(form.isMainLocked)
        #expect(form.mainNote == .onlyGoal)
        #expect(form.mainNoteText(in: F.ru) == "Первая цель — главная.")
        #expect(form.mainNoteText(in: F.en) == "The first goal is the main one.")
        form.isMain = false
        #expect(form.willBeMain)
        form.name = "Велосипед"
        form.targetText = "80000"
        #expect(form.output?.isMain == true)
    }

    @Test func aNewGoalBesideAMainOneStartsPlainAndCanTakeOver() {
        let fixture = GoalsFixture()
        var form = form(fixture)
        #expect(!form.isMain)
        #expect(!form.isMainLocked)
        #expect(form.mainNote == .explains)
        #expect(form.mainNoteText(in: F.ru) == "С главной целью сравнивается каждая покупка, а отказы копятся в неё.")
        form.isMain = true
        #expect(form.mainNote == .takesOverFrom("Велосипед"))
        #expect(form.mainNoteText(in: F.ru) == "«Велосипед» перестанет быть главной.")
        #expect(form.mainNoteText(in: F.en) == "“Велосипед” will no longer be the main goal.")
        form.name = "Отпуск"
        form.targetText = "1000"
        #expect(form.output?.isMain == true)
    }

    @Test func anotherGoalCanBeMadeMain() {
        let fixture = GoalsFixture()
        var form = form(fixture, editing: fixture.cushion)
        #expect(!form.isMainLocked)
        #expect(form.mainNote == .explains)
        form.isMain = true
        #expect(form.mainNote == .takesOverFrom("Велосипед"))
        #expect(form.output?.isMain == true)
    }

    /// Turning the star off on the main goal would change nothing: the repository makes the oldest
    /// goal main again. Only another goal's star moves it, and the form says so.
    @Test func theMainGoalStaysMain() {
        let fixture = GoalsFixture()
        var form = form(fixture, editing: fixture.bike)
        #expect(form.isMainLocked)
        #expect(form.mainNote == .staysMain)
        #expect(form.mainNoteText(in: F.ru) == "Чтобы сменить главную, отметь звездой другую цель.")
        #expect(form.mainNoteText(in: F.en) == "To change the main goal, star another one.")
        form.isMain = false
        #expect(form.willBeMain)
        #expect(form.output?.isMain == true)
    }

    @Test func withNoMainGoalANewOneStartsAsMain() {
        var fixture = GoalsFixture()
        fixture.bike.isMain = false
        let form = form(fixture, goals: [fixture.bike, fixture.cushion])
        #expect(form.isMain)
        #expect(!form.isMainLocked)
        #expect(form.mainNote == .explains)
    }

    @Test func theFormsLinesAreTranslated() {
        let lines: [(LocalizedStringResource, String, String)] = [
            (GoalFormModel.namePrompt, "На что копишь", "What it is for"),
            (GoalFormModel.targetCaption, "Сколько нужно", "How much it takes"),
            (GoalFormModel.currencyTitle, "Валюта", "Currency"),
            (GoalFormModel.accountTitle, "Копится на", "Saved on"),
            (GoalFormModel.noAccount, "Без счёта", "No account"),
            (GoalFormModel.accountFooter, "Прогресс — остаток на счёте плюс отказы.", "Progress is the account’s balance plus what you skip."),
            (GoalFormModel.savedTitle, "Уже отложено", "Already put aside"),
            (GoalFormModel.mainTitle, "Главная цель", "Main goal"),
            (GoalFormModel.cancelTitle, "Отмена", "Cancel"),
            (GoalFormModel.deleteTitle, "Удалить цель", "Delete goal"),
            (GoalFormModel.okTitle, "ОК", "OK"),
            (GoalFormModel.saveFailed, "Цель не сохранилась. Попробуй ещё раз.", "The goal was not saved. Try again."),
            (GoalFormModel.somethingFailed, "Не получилось. Попробуй ещё раз.", "That did not work. Try again."),
        ]
        for (resource, russian, english) in lines {
            #expect(resource.text(in: F.ru) == russian)
            #expect(resource.text(in: F.en) == english)
        }
    }
}
