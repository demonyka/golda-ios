import Foundation
import GoldaCore
import Testing

@testable import Golda

/// The account form's rules, the state and `save` of Android's `AccountSheet`: defaults per type,
/// what makes it valid, and the account and opening balance it hands over.
@Suite struct AccountFormModelTests {
    static let today = LocalDate(2026, 10, 2)
    static let ru = Locale(identifier: "ru")
    static let en = Locale(identifier: "en")

    /// Abroad in Georgia, showing rubles, dollars and lari.
    let settings = Settings(displayCurrencies: ["RUB", "USD", "GEL"], localCurrency: "GEL")
    let card = Account(name: "Карта ₽", currency: "RUB", type: .card, groupName: "Т-Банк", includeInFree: true, sort: 0)
    let usd = Account(name: "Доллары", currency: "USD", type: .card, groupName: "Мультивалютная", includeInFree: true, sort: 1)
    let gel = Account(name: "Лари", currency: "GEL", type: .card, groupName: "Мультивалютная", includeInFree: true, sort: 4)
    let cash = Account(name: "Наличные", currency: "GEL", type: .cash, groupName: "  ", includeInFree: true, sort: 2)
    let loan = Account(
        name: "Ипотека", currency: "RUB", type: .loan, includeInFree: false, interestRate: 24.9, sort: 3,
        paymentDay: 5, paymentMinor: 1_000_000, reconciledAt: 1_700_000_000_000
    )

    var accounts: [Account] { [card, usd, gel, cash, loan] }

    private func newForm(_ accounts: [Account]? = nil, id: UUID = UUID()) -> AccountFormModel {
        AccountFormModel(accounts: accounts ?? self.accounts, settings: settings, editing: nil, accountId: id)
    }

    private func editing(_ account: Account) -> AccountFormModel {
        AccountFormModel(accounts: accounts, settings: settings, editing: account)
    }

    // MARK: A new account

    @Test func aNewAccountIsACardInTheLocalCurrencyThatCountsInTheBudget() throws {
        var form = newForm()
        #expect(form.isNew)
        #expect(form.type == .card)
        #expect(form.currency == "GEL")
        #expect(form.includeInFree)
        #expect(form.groupChoice == .none)
        #expect(!form.canSave, "no name yet")

        form.name = "  Кошелёк  "
        let output = try #require(form.output)
        #expect(output.account.name == "Кошелёк")
        #expect(output.account.id == form.accountId)
        #expect(output.account.currency == "GEL")
        #expect(output.account.includeInFree)
        #expect(output.account.groupName == nil)
        #expect(output.account.interestRate == nil)
        #expect(output.account.reconciledAt == nil)
        // After the last account (sort 4), not after the count of them.
        #expect(output.account.sort == 5)
        // Nothing typed is an opening balance of zero, which the repository does not book.
        #expect(output.openingMinor == 0)
    }

    @Test func savingsAndDebtsStartOutsideTheBudget() {
        var form = newForm()
        for (type, counts) in [(AccountType.card, true), (.cash, true), (.savings, false), (.credit, false), (.loan, false)] {
            form.type = type
            #expect(form.includeInFree == counts, "\(type)")
            #expect(AccountFormModel.countsInBudgetByDefault(type) == counts)
        }
    }

    @Test func eachTypeAsksForWhatItNeeds() {
        var form = newForm()
        form.type = .card
        #expect(!form.hasRate && !form.isDebt && !form.hasGracePeriod)
        form.type = .cash
        #expect(!form.hasRate && !form.isDebt && !form.hasGracePeriod)
        form.type = .savings
        #expect(form.hasRate && !form.isDebt && !form.hasGracePeriod)
        form.type = .credit
        #expect(form.hasRate && form.isDebt && form.hasGracePeriod)
        form.type = .loan
        #expect(form.hasRate && form.isDebt && !form.hasGracePeriod)
    }

    @Test func theBudgetSwitchOnceTouchedStaysThroughAChangeOfType() throws {
        var form = newForm()
        form.name = "Вклад"
        form.type = .savings
        #expect(!form.includeInFree)
        form.includeInFree = true
        form.type = .loan
        form.type = .savings
        #expect(form.includeInFree)
        #expect(try #require(form.output).account.includeInFree)
    }

    @Test func aNewDebtsOpeningBalanceIsWhatIsOwedAsANegativeAmount() throws {
        var form = newForm()
        form.name = "Кредит"
        form.pickCurrency("RUB")
        form.openingText = "200\u{202F}000"
        #expect(try #require(form.output).openingMinor == 20_000_000)

        // The same figure on a debt is what is owed: the ledger keeps it negative, as Android's
        // `if (debt) -balance else balance`.
        form.type = .loan
        #expect(try #require(form.output).openingMinor == -20_000_000)
        form.type = .credit
        #expect(try #require(form.output).openingMinor == -20_000_000)
    }

    @Test func termsAreSavedOnlyByTheTypesThatHaveThem() throws {
        var form = newForm()
        form.name = "Кредитка"
        form.pickCurrency("RUB")
        form.rateText = "29,9"
        form.paymentText = "3000"
        form.paymentDay = 25
        form.setGracePeriod(true, today: Self.today)
        form.graceUntil = Self.today.plusDays(40)

        form.type = .credit
        var account = try #require(form.output).account
        #expect(account.interestRate == 29.9)
        #expect(account.paymentMinor == 300_000)
        #expect(account.paymentDay == 25)
        #expect(account.graceUntil == Int64(Self.today.plusDays(40).epochDay))

        form.type = .loan
        account = try #require(form.output).account
        #expect(account.interestRate == 29.9)
        #expect(account.paymentMinor == 300_000)
        #expect(account.paymentDay == 25)
        #expect(account.graceUntil == nil, "only a credit card has a grace period")

        form.type = .savings
        account = try #require(form.output).account
        #expect(account.interestRate == 29.9)
        #expect(account.paymentMinor == nil)
        #expect(account.paymentDay == nil)

        form.type = .card
        account = try #require(form.output).account
        #expect(account.interestRate == nil)
        #expect(account.paymentMinor == nil)
        #expect(account.graceUntil == nil)
    }

    @Test func theGracePeriodStartsOnTodayAndCanBeTurnedOff() {
        var form = newForm()
        form.type = .credit
        #expect(form.graceUntil == nil)
        form.setGracePeriod(true, today: Self.today)
        #expect(form.graceUntil == Self.today)
        form.graceUntil = Self.today.plusDays(50)
        // Turning it on again keeps the day picked.
        form.setGracePeriod(true, today: Self.today)
        #expect(form.graceUntil == Self.today.plusDays(50))
        form.setGracePeriod(false, today: Self.today)
        #expect(form.graceUntil == nil)
    }

    @Test func theSameIdEverySaveSoASecondTapDoesNotAddAnother() throws {
        let id = UUID()
        var form = newForm(id: id)
        form.name = "Карта"
        #expect(try #require(form.output).account.id == id)
        form.name = "Карта 2"
        #expect(try #require(form.output).account.id == id)
    }

    @Test func theFirstAccountGoesFirst() throws {
        var form = newForm([])
        form.name = "Карта"
        #expect(try #require(form.output).account.sort == 0)
    }

    // MARK: Validation

    @Test func aNameIsNeeded() {
        var form = newForm()
        form.name = "   "
        #expect(!form.canSave)
        form.name = "Карта"
        #expect(form.canSave)
    }

    @Test func textThatIsNotAnAmountStopsTheSave() {
        var form = newForm()
        form.name = "Карта"
        form.openingText = "12a"
        #expect(form.invalidFields == [.opening])
        #expect(form.output == nil)
        form.openingText = "-5"
        #expect(form.invalidFields == [.opening], "a negative opening balance is typed as a debt instead")
        form.openingText = "1 500,25"
        #expect(form.invalidFields.isEmpty)
        #expect(form.output?.openingMinor == 150_025)
    }

    @Test func aRateOrAPaymentThatCannotBeReadStopsTheSaveOnlyWhereItIsUsed() {
        var form = newForm()
        form.name = "Кредит"
        form.type = .loan
        form.rateText = "двадцать"
        form.paymentText = "1,2,3"
        #expect(form.invalidFields == [.rate, .payment])
        #expect(!form.canSave)

        // A savings account has a rate but no payment.
        form.type = .savings
        #expect(form.invalidFields == [.rate])

        // A card saves neither, so what is left in the hidden fields does not matter.
        form.type = .card
        #expect(form.invalidFields.isEmpty)
        #expect(form.canSave)
    }

    @Test func emptyTermsAreSavedAsNone() throws {
        var form = newForm()
        form.name = "Кредит"
        form.type = .loan
        form.rateText = " "
        let account = try #require(form.output).account
        #expect(account.interestRate == nil)
        #expect(account.paymentMinor == nil)
        #expect(account.paymentDay == nil)
    }

    // MARK: Currency

    @Test func theLocalAndShownCurrenciesComeFirstThenTheRest() {
        let form = newForm()
        #expect(form.preferredCurrencies == ["GEL", "RUB", "USD"])
        #expect(form.otherCurrencies == ["EUR", "THB", "TRY", "KZT", "AMD", "CNY", "AED", "VND", "IDR"])
    }

    @Test func amountsAreReadInTheCurrencyPicked() throws {
        var form = newForm()
        form.name = "Счёт"
        form.type = .loan
        form.openingText = "15,5"
        form.paymentText = "1,25"
        form.pickCurrency("USD")
        var output = try #require(form.output)
        #expect(output.openingMinor == -1_550)
        #expect(output.account.paymentMinor == 125)
        #expect(output.account.currency == "USD")

        // What was typed stays as typed; yen have no fraction, so it rounds half up.
        form.pickCurrency("JPY")
        #expect(form.openingText == "15,5")
        output = try #require(form.output)
        #expect(output.openingMinor == -16)
        #expect(output.account.paymentMinor == 1)
        #expect(output.account.currency == "JPY")
    }

    @Test func currencyLabelsCarryTheSymbolWhenThereIsOne() {
        #expect(AccountFormModel.currencyLabel("GEL") == "₾ GEL")
        #expect(AccountFormModel.currencyLabel("AED") == "AED")
    }

    // MARK: Groups

    @Test func theGroupsInUseAreOfferedOnceEachInTheOrderOfTheAccounts() {
        let form = newForm()
        // The blank one is not a group.
        #expect(form.existingGroups == ["Т-Банк", "Мультивалютная"])
    }

    @Test func aGroupIsPickedTypedOrLeftOut() throws {
        var form = newForm()
        form.name = "Евро"
        form.groupChoice = .existing("Мультивалютная")
        #expect(try #require(form.output).account.groupName == "Мультивалютная")

        form.groupChoice = .new
        form.newGroupName = "  Альфа  "
        #expect(try #require(form.output).account.groupName == "Альфа")
        form.newGroupName = "   "
        #expect(try #require(form.output).account.groupName == nil)

        form.groupChoice = .none
        form.newGroupName = "Альфа"
        #expect(try #require(form.output).account.groupName == nil)
    }

    @Test func withNoGroupsYetTheFormAsksForANewOne() {
        let form = newForm([loan])
        #expect(form.existingGroups.isEmpty)
        #expect(form.groupChoice == .new)
    }

    // MARK: Editing

    @Test func editingStartsFromTheAccountAsItIs() {
        let form = editing(loan)
        #expect(!form.isNew)
        #expect(form.name == "Ипотека")
        #expect(form.type == .loan)
        #expect(form.currency == "RUB")
        #expect(form.rateText == "24,9")
        // A plain field, as Android's: no grouping.
        #expect(form.paymentText == "10000")
        #expect(form.paymentDay == 5)
        #expect(!form.includeInFree)
        #expect(form.groupChoice == .none)
        #expect(form.invalidFields.isEmpty)
        #expect(form.canSave)
    }

    @Test func editingKeepsTheIdTheSortAndTheReconcileStampAndBooksNoOpening() throws {
        var form = editing(loan)
        form.name = "Кредит на машину"
        form.paymentText = "12 500,50"
        form.openingText = "999"
        let output = try #require(form.output)
        #expect(output.openingMinor == nil)
        #expect(output.account == Account(
            id: loan.id, name: "Кредит на машину", currency: "RUB", type: .loan, includeInFree: false, interestRate: 24.9, sort: 3,
            paymentDay: 5, paymentMinor: 1_250_050, reconciledAt: 1_700_000_000_000
        ))
    }

    @Test func anAccountKeepsItsCurrency() throws {
        var form = editing(usd)
        form.pickCurrency("EUR")
        #expect(form.currency == "USD")
        #expect(try #require(form.output).account.currency == "USD")
    }

    @Test func anEditedAccountsCurrencyIsAmongTheChoices() {
        let lira = Account(name: "Лиры", currency: "TRY", type: .cash, includeInFree: true)
        let form = AccountFormModel(accounts: accounts + [lira], settings: settings, editing: lira)
        #expect(form.preferredCurrencies == ["GEL", "RUB", "USD", "TRY"])
        #expect(!form.otherCurrencies.contains("TRY"))
    }

    @Test func editingKeepsTheGroupAndTheGracePeriod() throws {
        let credit = Account(
            name: "Кредитка", currency: "RUB", type: .credit, groupName: "Т-Банк", includeInFree: true, interestRate: 29.9,
            paymentDay: 25, paymentMinor: 300_000, graceUntil: Int64(Self.today.plusDays(40).epochDay)
        )
        let form = AccountFormModel(accounts: accounts + [credit], settings: settings, editing: credit)
        #expect(form.groupChoice == .existing("Т-Банк"))
        #expect(form.graceUntil == Self.today.plusDays(40))
        // A debt that was put in the budget by hand stays there.
        #expect(form.includeInFree)
        #expect(try #require(form.output).account == credit)
    }

    @Test func aGroupMissingFromAStaleListIsStillOffered() {
        let moved = Account(name: "Евро", currency: "EUR", type: .card, groupName: "Новый банк", includeInFree: true)
        let form = AccountFormModel(accounts: accounts, settings: settings, editing: moved)
        #expect(form.existingGroups == ["Т-Банк", "Мультивалютная", "Новый банк"])
        #expect(form.groupChoice == .existing("Новый банк"))
    }

    // MARK: Text

    @Test func theFormSpeaksBothLanguages() {
        var form = newForm()
        #expect(form.title.text(in: Self.ru) == "Новый счёт")
        #expect(form.title.text(in: Self.en) == "New account")
        #expect(form.saveTitle.text(in: Self.ru) == "Добавить")
        #expect(form.saveTitle.text(in: Self.en) == "Add")
        #expect(form.openingCaption.text(in: Self.ru) == "Сколько сейчас")
        #expect(form.rateTitle.text(in: Self.en) == "Rate on balance")
        form.type = .credit
        #expect(form.openingCaption.text(in: Self.ru) == "Сколько должен сейчас")
        #expect(form.openingCaption.text(in: Self.en) == "How much you owe now")
        #expect(form.rateTitle.text(in: Self.ru) == "Ставка")
        #expect(form.paymentTitle.text(in: Self.ru) == "Минимальный платёж")
        form.type = .loan
        #expect(form.paymentTitle.text(in: Self.en) == "Payment")

        let edit = editing(loan)
        #expect(edit.title.text(in: Self.ru) == "Счёт")
        #expect(edit.saveTitle.text(in: Self.ru) == "Сохранить")
        #expect(edit.saveTitle.text(in: Self.en) == "Save")
        #expect(edit.deleteQuestion(in: Self.ru) == "Удалить «Ипотека»?")
        #expect(edit.deleteQuestion(in: Self.en) == "Delete “Ипотека”?")
        #expect(AccountFormModel.deleteWarning.text(in: Self.ru) == "Удалятся и все операции с этим счётом, включая переводы.")

        let tiles = AccountType.allCases.map { AccountFormModel.typeTitle($0) }
        #expect(tiles.map { $0.text(in: Self.ru) } == ["Карта", "Наличные", "Вклад", "Кредитка", "Кредит"])
        #expect(tiles.map { $0.text(in: Self.en) } == ["Card", "Cash", "Savings", "Credit", "Loan"])
    }
}

/// The thousands an amount field groups while it is typed, Android's `Grouping`.
@Suite struct AmountInputTests {
    @Test func theWholePartIsGroupedByThousands() {
        #expect(AmountInput.grouped("") == "")
        #expect(AmountInput.grouped("15") == "15")
        #expect(AmountInput.grouped("1500") == "1\u{202F}500")
        #expect(AmountInput.grouped("1500,5") == "1\u{202F}500,5")
        #expect(AmountInput.grouped("1500.") == "1\u{202F}500.")
        #expect(AmountInput.grouped("1234567,89") == "1\u{202F}234\u{202F}567,89")
    }

    @Test func spacesTypedOrPastedAreRegrouped() {
        #expect(AmountInput.grouped("1 500 000") == "1\u{202F}500\u{202F}000")
        #expect(AmountInput.grouped("1\u{202F}50") == "150")
        #expect(AmountInput.grouped("12\u{00A0}345") == "12\u{202F}345")
    }

    @Test func textThatIsNotAnAmountIsLeftAsTyped() {
        #expect(AmountInput.grouped("abc") == "abc")
        #expect(AmountInput.grouped("1,2,3") == "1,2,3")
        #expect(AmountInput.grouped("-1500") == "-1500")
    }

    @Test func groupedTextIsReadBackExactly() {
        #expect(Fmt.parseMinor(AmountInput.grouped("1234567,89"), "RUB") == 123_456_789)
    }

    // MARK: Keystrokes

    private let s = "\u{202F}"

    /// Types [keys] one by one at the caret, starting from an empty field.
    private func type(_ keys: String) -> (text: String, caret: Int) {
        var state = (text: "", caret: 0)
        for key in keys {
            state = AmountInput.edit(state.text, range: NSRange(location: state.caret, length: 0), replacement: String(key))
        }
        return state
    }

    @Test func typingGroupsAsItGoesAndTheCaretStaysAtTheEnd() {
        #expect(type("150").text == "150")
        let typed = type("150000")
        #expect(typed.text == "150\(s)000")
        #expect(typed.caret == typed.text.utf16.count)
        #expect(type("1234567,5").text == "1\(s)234\(s)567,5")
    }

    @Test func aDigitTypedInTheMiddleKeepsTheCaretAfterIt() {
        // "1 500" with the caret after "1": a "2" makes "12 500", caret after the "2".
        let edit = AmountInput.edit("1\(s)500", range: NSRange(location: 1, length: 0), replacement: "2")
        #expect(edit.text == "12\(s)500")
        #expect(edit.caret == 2)
    }

    @Test func deletingRegroupsAndASpaceTakesTheDigitBeforeIt() {
        // Backspace at the end of "1 500": "150".
        var edit = AmountInput.edit("1\(s)500", range: NSRange(location: 4, length: 1), replacement: "")
        #expect(edit.text == "150")
        #expect(edit.caret == 3)
        // Backspace right after the space of "12 500" deletes the "2": "1 500", caret after the "1".
        edit = AmountInput.edit("12\(s)500", range: NSRange(location: 2, length: 1), replacement: "")
        #expect(edit.text == "1\(s)500")
        #expect(edit.caret == 1)
    }

    @Test func aPasteIsGroupedWhole() {
        let edit = AmountInput.edit("", range: NSRange(location: 0, length: 0), replacement: "2 500 000,75")
        #expect(edit.text == "2\(s)500\(s)000,75")
        #expect(edit.caret == edit.text.utf16.count)
    }
}
