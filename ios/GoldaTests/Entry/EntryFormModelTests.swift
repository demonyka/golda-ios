import Foundation
import GoldaCore
import GoldaData
import Testing

@testable import Golda

/// The operation form's rules, the state and decisions of Android's `EntrySheet`, on hand-built
/// books (`EntryFixture`): 80 ₽ a dollar and 30 ₽ a lari with a 10 % markup, lari local, "now"
/// 2026-10-02 10:00 UTC.
@Suite struct EntryFormModelTests {
    typealias E = EntryFixture

    // MARK: Defaults

    @Test func aNewExpenseStartsEmptyInTheLocalCurrencyFromTheAccountVoiceWouldPayFrom() {
        let books = E()
        let form = books.form()
        #expect(form.isNew)
        #expect(form.type == .expense)
        // No account used yet: the first free-money account in lari.
        #expect(form.accountId == books.cash.id)
        #expect(form.purchaseCurrency == "GEL")
        #expect(form.amountCode == "GEL")
        #expect(form.amountText.isEmpty)
        #expect(form.amount == nil)
        #expect(form.note.isEmpty)
        #expect(form.categoryKey == nil)
        #expect(form.date == E.today)
        #expect(!form.isDeciding)
        #expect(form.secondCode == nil)
        #expect(!form.isValid)
        #expect(form.draft(now: E.now) == nil)
        // The destination waits for a transfer: the first account that is not the source.
        #expect(form.toAccountId == books.rub.id)
    }

    @Test func theLastAccountWinsWhenItIsInTheLocalCurrency() {
        var books = E()
        books.device.localCurrency = "USD"
        books.lastUsed(books.usd)
        #expect(books.form().accountId == books.usd.id)

        // In another currency it gives way to a free-money account in the local one.
        books.device.localCurrency = "GEL"
        #expect(books.form().accountId == books.cash.id)
    }

    @Test func withNoAccountInTheLocalCurrencyTheLastOneIsUsedAndThePriceConverted() {
        var books = E()
        books.device.localCurrency = "EUR"
        books.device.displayCurrencies = ["RUB", "EUR"]
        books.lastUsed(books.usd)
        var form = books.form()
        #expect(form.accountId == books.usd.id)
        #expect(form.purchaseCurrency == "EUR")
        #expect(form.secondCode == "USD")
        // No euro rate in these books: the charge cannot be estimated, so nothing can be saved yet.
        form.amountText = "10"
        #expect(form.estimate == nil)
        #expect(!form.isValid)
    }

    @Test func aPurchaseToDecideOnOpensInNotSureWithItsPriceAndName() {
        let books = E()
        let form = books.form(EntryRequest(consider: Consider(title: "Наушники", amountMinor: 1_200_000, currency: "RUB")))
        #expect(form.isDeciding)
        #expect(form.type == .expense)
        #expect(form.purchaseCurrency == "RUB")
        // Paid from where voice would pay rubles: the ruble card.
        #expect(form.accountId == books.rub.id)
        #expect(form.amountText == "12\u{202F}000")
        #expect(form.amount == 1_200_000)
        #expect(form.note == "Наушники")
        #expect(!form.offersConsider)
        #expect(!form.returnsToForm, "nothing behind it to go back to")
        #expect(form.offersThink)
        #expect(!books.form(EntryRequest(consider: Consider(title: "x", amountMinor: 100, currency: "RUB"), wishId: UUID())).offersThink)
    }

    @Test func notSureOpenedFromTheFormGoesBackToIt() {
        var form = E().form()
        #expect(form.offersConsider)
        form.amountText = "15"
        form.isDeciding = true
        #expect(form.returnsToForm)
        #expect(!form.offersConsider)
        form.isDeciding = false
        #expect(form.offersConsider)
        // Income, transfers and edits have no "Not sure".
        form.pickType(.income)
        #expect(!form.offersConsider)
    }

    @Test func theBigNumberGroupsThousandsAndReadsWithoutThem() {
        var form = E().form()
        form.amountText = AmountInput.grouped("1500,5")
        #expect(form.amountText == "1\u{202F}500,5")
        #expect(form.amount == 150_050)
        form.amountText = "abc"
        #expect(form.amount == nil)
        #expect(form.isAmountInvalid)
        form.amountText = "0"
        #expect(form.amount == nil, "zero is not an amount")
        form.amountText = "  "
        #expect(!form.isAmountInvalid, "nothing typed is not an error")
    }

    // MARK: The second amount

    @Test func aPurchaseInAnotherCurrencyIsChargedAnEstimateTheBankCanCorrect() throws {
        let books = E()
        var form = books.form()
        form.pickAccount(books.usd.id)
        #expect(form.purchaseCurrency == "USD", "the price followed the account from lari")
        form.pickCurrency("GEL")
        form.amountText = "15"
        #expect(form.secondCode == "USD")
        // 15 ₾ at the cross rate 30 / 80 plus the card's 2 %: 5,7375 $.
        #expect(form.estimate == 574)
        #expect(form.secondText == "5,74")
        #expect(form.second == 574)
        #expect(form.underLine == .charged(amount: "5,74 $", isEstimate: true))
        var draft = try #require(form.draft(now: E.now))
        #expect(draft == Draft(
            type: .expense, timestamp: E.now, accountId: books.usd.id, amountMinor: 574, purchaseAmountMinor: 1_500,
            purchaseCurrency: "GEL", isEstimate: true
        ))

        // The bank's real figure: no longer an estimate, and it stays through a change of the price.
        form.isEditingSecond = true
        form.typeSecond("5,80")
        #expect(form.secondEdited)
        #expect(form.underLine == .charged(amount: "5,80 $", isEstimate: false))
        form.amountText = "16"
        #expect(form.second == 580)
        draft = try #require(form.draft(now: E.now))
        #expect(draft.amountMinor == 580)
        #expect(draft.purchaseAmountMinor == 1_600)
        #expect(!draft.isEstimate)

        // A new currency estimates afresh.
        form.pickCurrency("RUB")
        #expect(!form.secondEdited)
        // 16 ₽ at 1 / 80 plus 2 %: 0,204 $.
        #expect(form.second == 20)
        #expect(try #require(form.draft(now: E.now)).isEstimate)
    }

    @Test func aChargeThatCannotBeReadOrIsZeroStopsSaving() {
        let books = E()
        var form = books.form()
        form.pickAccount(books.usd.id)
        form.pickCurrency("GEL")
        form.amountText = "15"
        form.typeSecond("")
        #expect(!form.isValid)
        #expect(form.underLine == .charged(amount: nil, isEstimate: false))
        form.typeSecond("0")
        #expect(!form.isValid)
        form.typeSecond("1,2,3")
        #expect(!form.isValid)
        form.typeSecond("6")
        #expect(form.isValid)
    }

    @Test func whileDecidingTheChargeGivesWayToTheOtherCurrencies() {
        let books = E()
        var form = books.form()
        form.pickAccount(books.usd.id)
        form.pickCurrency("GEL")
        form.amountText = "15"
        form.isDeciding = true
        // 15 ₾ are 495 ₽ at the display rate, and 5,625 $, written to one decimal with the tie to even.
        #expect(form.underLine == .others("495 ₽ · 5,6 $", approximate: true))
    }

    @Test func pickingAnAccountMovesAPriceInTheOldAccountsCurrencyOnly() {
        let books = E()
        var form = books.form()
        #expect(form.purchaseCurrency == "GEL")
        form.pickAccount(books.rub.id)
        #expect(form.purchaseCurrency == "RUB", "lari were the cash's currency, so the price moved to rubles")
        form.pickCurrency("USD")
        form.pickAccount(books.cash.id)
        #expect(form.purchaseCurrency == "USD", "dollars were the price's own")
        #expect(form.secondCode == "GEL")
        form.typeSecond("3")
        form.pickAccount(books.usd.id)
        #expect(!form.secondEdited, "a new account estimates afresh")
        #expect(form.secondCode == nil)
    }

    // MARK: Income

    @Test func incomeIsInTheAccountsCurrencyWithItsOwnCategoriesAndNoLineUnderIt() throws {
        let books = E()
        var form = books.form()
        form.pickCurrency("USD")
        form.pickCategory("groceries")
        form.pickType(.income)
        #expect(form.type == .income)
        #expect(form.purchaseCurrency == "GEL", "income is in the account's currency")
        #expect(form.categoryKey == nil, "the category starts over")
        #expect(!form.picksCurrency)
        #expect(form.categories.map(\.key) == ["salary", "interest", "gift", "other_income"])
        form.amountText = "250"
        form.pickCategory("gift")
        #expect(form.underLine == .none)
        #expect(form.secondCode == nil)
        let draft = try #require(form.draft(now: E.now))
        #expect(draft == Draft(type: .income, timestamp: E.now, accountId: books.cash.id, amountMinor: 25_000, categoryKey: "gift"))
    }

    // MARK: Transfers

    @Test func aFirstTransferGoesFromTheRubleAccountToTheNextOne() throws {
        let books = E()
        var form = books.form()
        form.pickCategory("fun")
        form.pickType(.transfer)
        #expect(form.accountId == books.rub.id)
        #expect(form.toAccountId == books.cash.id)
        #expect(form.categoryKey == nil)
        #expect(form.categories.isEmpty)
        #expect(form.amountCode == "RUB")
        #expect(form.underLine == .none, "a transfer has its balances in the tiles")
        #expect(form.destinations.map(\.id) == [books.cash.id, books.usd.id, books.savings.id])

        // Rubles to lari: what arrives is estimated at the display rates, 100 / 33.
        form.amountText = "100"
        #expect(form.secondCode == "GEL")
        #expect(form.second == 303)
        #expect(form.underLine == .received(amount: "3,03 ₾", isEstimate: true))
        var draft = try #require(form.draft(now: E.now))
        #expect(draft == Draft(
            type: .transfer, timestamp: E.now, accountId: books.rub.id, amountMinor: 10_000, toAccountId: books.cash.id,
            toAmountMinor: 303, isEstimate: true
        ))

        // What the bank says arrived.
        form.typeSecond("3,10")
        draft = try #require(form.draft(now: E.now))
        #expect(draft.toAmountMinor == 310)
        #expect(!draft.isEstimate)

        // Between rubles nothing changes currency: what arrives is what left.
        form.pickDestination(books.savings.id)
        #expect(form.secondCode == nil)
        draft = try #require(form.draft(now: E.now))
        #expect(draft.toAccountId == books.savings.id)
        #expect(draft.toAmountMinor == 10_000)
        #expect(!draft.isEstimate)
    }

    @Test func aNewTransferTakesTheLastTransfersRoute() {
        var books = E()
        books.operations = [
            E.operation(.expense, category: "groceries", [(books.cash, -1_000, -33_000)]),
            E.operation(.transfer, at: E.now - 3_600_000, [(books.usd, -10_000, -880_000), (books.cash, 26_500, 880_000)]),
            E.operation(.transfer, at: E.now - 7_200_000, [(books.rub, -100_000, -100_000), (books.savings, 100_000, 100_000)]),
        ]
        var form = books.form()
        #expect(form.lastTransfer == EntryFormModel.Route(from: books.usd.id, to: books.cash.id))
        form.pickType(.transfer)
        #expect(form.accountId == books.usd.id)
        #expect(form.toAccountId == books.cash.id)
        #expect(form.amountCode == "USD")

        // Back to an expense: from the usual account again. The price keeps the transfer's
        // currency, as on Android, so dollars are charged to the lari cash.
        form.pickType(.expense)
        #expect(form.accountId == books.cash.id)
        #expect(form.purchaseCurrency == "USD")
        #expect(form.secondCode == "GEL")
    }

    @Test func swappingTheRouteAndPickingTheDestinationAsSource() {
        let books = E()
        var form = books.form()
        form.pickType(.transfer)
        form.amountText = "100"
        form.typeSecond("4")
        form.swapRoute()
        #expect(form.accountId == books.cash.id)
        #expect(form.toAccountId == books.rub.id)
        #expect(!form.secondEdited)
        #expect(form.amountCode == "GEL")
        // 100 ₾ are 3 300 ₽.
        #expect(form.second == 330_000)

        // The source picked as the destination's account: the destination steps aside.
        form.pickAccount(books.rub.id)
        #expect(form.accountId == books.rub.id)
        #expect(form.toAccountId == books.cash.id)
    }

    @Test func aTransferNeedsTwoAccounts() {
        var books = E()
        books.extraAccounts = []
        var form = books.form()
        form.pickType(.transfer)
        form.amountText = "100"
        #expect(form.isValid)

        // A profile with one account has nowhere to send it.
        let only = Account(name: "Карта", currency: "RUB", type: .card, includeInFree: true)
        let data = AppData(
            snapshot: ProfileSnapshot(profile: books.profile, accounts: [only], operations: [], obligations: [], goals: [], wishes: []),
            device: books.device, rates: [], zone: HomeFixture.utc
        )
        var lonely = EntryFormModel(data: data, request: EntryRequest(), today: E.today)
        lonely.pickType(.transfer)
        lonely.amountText = "100"
        #expect(lonely.accountId == only.id)
        #expect(lonely.toAccountId == nil)
        #expect(!lonely.isValid)
    }

    // MARK: Time

    @Test func aNewOperationIsNowTodayAndNoonOnAnotherDay() throws {
        var form = E().form()
        form.amountText = "15"
        #expect(try #require(form.draft(now: E.now)).timestamp == E.now)
        form.date = E.yesterday
        #expect(try #require(form.draft(now: E.now)).timestamp == HomeFixture.at(E.yesterday, hour: 12))
        // A form left open past midnight: the day picked is no longer today, so it gets its noon.
        form.date = E.today
        let tomorrowMorning = HomeFixture.at(E.today.plusDays(1), hour: 1)
        #expect(try #require(form.draft(now: tomorrowMorning)).timestamp == HomeFixture.at(E.today, hour: 12))
    }

    @Test func anEditKeepsItsTimeUntilTheDayChanges() throws {
        let books = E()
        let evening = HomeFixture.at(E.yesterday, hour: 18)
        let coffee = E.operation(.expense, at: evening, note: "Кофе", category: "eating_out", [(books.cash, -800, -26_400)])
        var form = books.form(EntryRequest(editing: coffee))
        #expect(form.date == E.yesterday)
        form.note = "Кофе с собой"
        #expect(try #require(form.draft(now: E.now)).timestamp == evening)
        form.date = E.today
        #expect(try #require(form.draft(now: E.now)).timestamp == E.now)
        form.date = LocalDate(2026, 9, 20)
        #expect(try #require(form.draft(now: E.now)).timestamp == HomeFixture.at(LocalDate(2026, 9, 20), hour: 12))
    }

    // MARK: Edit round trips

    @Test func anExpenseOpensAsStoredAndSavesBackTheSame() throws {
        let books = E()
        let at = HomeFixture.at(E.yesterday, hour: 18)
        let shawarma = E.operation(
            .expense, at: at, note: "Шаурма", category: "eating_out", voice: "шаурма пятнадцать лари", [(books.cash, -1_500, -49_500)]
        )
        let form = books.form(EntryRequest(editing: shawarma))
        #expect(!form.isNew)
        #expect(!form.offersConsider)
        #expect(form.type == .expense)
        #expect(form.accountId == books.cash.id)
        #expect(form.purchaseCurrency == "GEL")
        #expect(form.amountText == "15")
        #expect(form.categoryKey == "eating_out")
        #expect(form.note == "Шаурма")
        #expect(form.secondEdited, "a stored operation that is not an estimate")
        #expect(try #require(form.draft(now: E.now)) == Draft(
            type: .expense, timestamp: at, accountId: books.cash.id, amountMinor: 1_500, categoryKey: "eating_out",
            note: "Шаурма", voiceText: "шаурма пятнадцать лари", id: shawarma.op.id
        ))
    }

    @Test func aChargeTheBankConfirmedStaysAndAnEstimateIsWorkedOutAgain() throws {
        let books = E()
        let market = E.operation(
            .expense, at: E.now - 3_600_000, note: "Рынок", purchase: (4_850, "GEL"), estimate: false, [(books.usd, -1_899, -167_112)]
        )
        var form = books.form(EntryRequest(editing: market))
        #expect(form.amountText == "48,5")
        #expect(form.purchaseCurrency == "GEL")
        #expect(form.secondText == "18,99")
        var draft = try #require(form.draft(now: E.now))
        #expect(draft.amountMinor == 1_899)
        #expect(draft.purchaseAmountMinor == 4_850)
        #expect(draft.purchaseCurrency == "GEL")
        #expect(!draft.isEstimate)
        #expect(draft.id == market.op.id)

        // Stored as an estimate, the charge follows today's rates when the form opens, as on
        // Android: 48,5 ₾ × 30 / 80 × 1,02 = 18,55 $.
        var estimated = market
        estimated.op.isEstimate = true
        form = books.form(EntryRequest(editing: estimated))
        #expect(!form.secondEdited)
        #expect(form.secondText == "18,55")
        draft = try #require(form.draft(now: E.now))
        #expect(draft.amountMinor == 1_855)
        #expect(draft.isEstimate)
    }

    @Test func aTransferOpensWithBothSidesAndSavesBackTheSame() throws {
        let books = E()
        let at = HomeFixture.at(LocalDate(2026, 9, 21), hour: 12)
        let exchange = E.operation(.transfer, at: at, note: "Обмен", [(books.rub, -10_000, -10_000), (books.usd, 120, 10_000)])
        let form = books.form(EntryRequest(editing: exchange))
        #expect(form.type == .transfer)
        #expect(form.accountId == books.rub.id)
        #expect(form.toAccountId == books.usd.id)
        #expect(form.amountText == "100")
        #expect(form.secondText == "1,2")
        #expect(form.underLine == .received(amount: "1,20 $", isEstimate: false))
        #expect(try #require(form.draft(now: E.now)) == Draft(
            type: .transfer, timestamp: at, accountId: books.rub.id, amountMinor: 10_000, toAccountId: books.usd.id,
            toAmountMinor: 120, note: "Обмен", id: exchange.op.id
        ))
    }

    @Test func incomeOpensWithItsOnlyPosting() throws {
        let books = E()
        let salary = E.operation(.income, at: HomeFixture.at(LocalDate(2026, 9, 25), hour: 9), category: "salary", [(books.rub, 5_000_000, 5_000_000)])
        var form = books.form(EntryRequest(editing: salary))
        #expect(form.type == .income)
        #expect(form.accountId == books.rub.id)
        #expect(form.amountText == "50\u{202F}000")
        #expect(form.secondText.isEmpty)
        // An edit can change its type; the accounts stay where they are.
        form.pickType(.expense)
        #expect(form.accountId == books.rub.id)
        form.pickCategory("travel")
        let draft = try #require(form.draft(now: E.now))
        #expect(draft.type == .expense)
        #expect(draft.amountMinor == 5_000_000)
        #expect(draft.categoryKey == "travel")
        #expect(draft.id == salary.op.id)
    }

    @Test func onlyExpensesIncomeAndTransfersOpenTheForm() {
        let books = E()
        let opening = E.operation(.opening, [(books.rub, 100_000, 100_000)])
        let adjustment = E.operation(.adjustment, [(books.rub, -500, -500)])
        let coffee = E.operation(.expense, [(books.cash, -800, -26_400)])
        #expect(EntryFormModel.isBookkeeping(EntryRequest(editing: opening)))
        #expect(EntryFormModel.isBookkeeping(EntryRequest(editing: adjustment)))
        #expect(!EntryFormModel.isBookkeeping(EntryRequest(editing: coffee)))
        #expect(!EntryFormModel.isBookkeeping(EntryRequest()))
    }

    // MARK: Categories

    @Test func categoriesComeMostUsedFirstAndASecondTapClearsThePick() {
        var books = E()
        books.operations = [
            E.operation(.expense, category: "groceries", [(books.cash, -1_000, -33_000)]),
            E.operation(.expense, category: "eating_out", [(books.cash, -1_000, -33_000)]),
            E.operation(.expense, category: "groceries", [(books.cash, -1_000, -33_000)]),
            E.operation(.income, category: "gift", [(books.rub, 1_000, 1_000)]),
        ]
        var form = books.form()
        #expect(form.categories.map(\.key) == [
            "groceries", "eating_out", "transport", "housing", "telecom", "fun", "health", "clothes", "subscriptions",
            "travel", "fees", "other",
        ])
        form.pickCategory("fun")
        #expect(form.categoryKey == "fun")
        form.pickCategory("fun")
        #expect(form.categoryKey == nil)
        form.pickType(.income)
        #expect(form.categories.map(\.key) == ["gift", "salary", "interest", "other_income"])
    }

    // MARK: "Сомневаюсь"

    @Test func thePurchaseIsNamedByItsNoteElseItsCategoryElsePurchase() {
        var form = E().form()
        let name: (String) -> String = { "category:" + $0 }
        #expect(form.consider(categoryName: name, unnamed: "Покупка") == nil, "no price, nothing to weigh up")
        form.amountText = "80"
        #expect(form.consider(categoryName: name, unnamed: "Покупка") == Consider(title: "Покупка", amountMinor: 8_000, currency: "GEL"))
        form.pickCategory("clothes")
        #expect(form.consider(categoryName: name, unnamed: "Покупка")?.title == "category:clothes")
        form.note = "  Куртка "
        #expect(form.consider(categoryName: name, unnamed: "Покупка")?.title == "Куртка")
        form.pickCurrency("USD")
        #expect(form.consider(categoryName: name, unnamed: "Покупка")?.currency == "USD")
    }

    @Test func buyingSomethingNamelessCallsItAPurchase() throws {
        var form = E().form(EntryRequest(consider: Consider(title: "", amountMinor: 8_000, currency: "GEL")))
        #expect(try #require(form.purchaseDraft(now: E.now, unnamed: "Покупка")).note == "Покупка")
        form.pickCategory("fun")
        let draft = try #require(form.purchaseDraft(now: E.now, unnamed: "Покупка"))
        #expect(draft.note.isEmpty, "the category names it")
        #expect(draft.categoryKey == "fun")
        form.note = "Кино"
        #expect(try #require(form.purchaseDraft(now: E.now, unnamed: "Покупка")).note == "Кино")
    }

    @Test func theFactsStandAsDashesUntilKnownOnlyForWhatCanBeKnown() {
        var books = E()
        #expect(books.form().facts(nil) == [
            .init(kind: .hoursOfWork, value: "—"),
            .init(kind: .daysOfBudget, value: "—"),
        ])
        books.goals = [Goal(name: "Велосипед", targetMinor: 8_000_000, currency: "RUB", isMain: true)]
        books.profile.settings.hourlyRate = 0
        #expect(books.form().facts(nil) == [
            .init(kind: .goalShare, value: "— %"),
            .init(kind: .daysOfBudget, value: "—"),
        ])
        let known = Facts(item: "Куртка", hoursValue: 2.64, daysValue: 3.0, goalName: "Велосипед", goalShare: 0.125)
        #expect(books.form().facts(known) == [
            .init(kind: .hoursOfWork, value: "2,6"),
            .init(kind: .goalShare, value: "12,5 %"),
            .init(kind: .daysOfBudget, value: "3"),
        ])
        #expect(books.form().facts(Facts(item: "x")).isEmpty)
    }

    @Test func theFactsAreAskedForAgainOnlyWhenThePriceChanges() {
        var form = E().form()
        form.amountText = "80"
        let before = form.factsKey
        form.note = "Куртка"
        form.pickCategory("clothes")
        #expect(form.factsKey == before)
        form.amountText = "81"
        #expect(form.factsKey != before)
        let typed = form.factsKey
        form.pickCurrency("USD")
        #expect(form.factsKey != typed)
        form.isDeciding = true
        #expect(form.factsKey.isDeciding)
    }

    // MARK: Under the number

    @Test func beforeAnAmountTheLineSaysWhatIsSafeTodayAfterItWhatItComesTo() {
        var books = E()
        // 10 000 ₽ of free money over the 8 days to payday on the 10th.
        books.operations = [E.operation(.opening, at: HomeFixture.at(LocalDate(2026, 9, 1), hour: 8), [(books.rub, 1_000_000, 1_000_000)])]
        var form = books.form()
        #expect(form.underLine == .safeToday("1\u{202F}250 ₽"))
        form.amountText = "15"
        #expect(form.underLine == .others("495 ₽ · 5,6 $", approximate: true))

        // With no other currency shown the amount itself stands there.
        books.device.displayCurrencies = ["GEL"]
        form = books.form()
        form.amountText = "15"
        #expect(form.underLine == .others("15 ₾", approximate: false))
    }

    @Test func balancesShowInTheAccountsOwnCurrency() {
        var books = E()
        books.operations = [E.operation(.opening, [(books.usd, 12_050, 1_060_400)])]
        let form = books.form()
        #expect(form.balance(of: books.usd) == "120,50 $")
        #expect(form.balance(of: books.cash) == "0 ₾")
    }

    @Test func theCurrenciesToPickFromIncludeTheAccountsOwn() {
        var books = E()
        books.device.displayCurrencies = ["RUB"]
        var form = books.form()
        #expect(form.currencyChoices == ["GEL", "RUB"])
        form.pickAccount(books.usd.id)
        #expect(form.currencyChoices == ["GEL", "RUB", "USD"])
    }
}
