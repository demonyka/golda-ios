import Foundation
import GoldaCore
import Testing

@testable import Golda

/// The payment form, the rules of Android's `ObligationSheet`: a name, an amount above zero in a
/// currency, and a day of the month, or nothing is saved.
@Suite struct ObligationFormTests {
    private let ru = Locale(identifier: "ru")
    private let en = Locale(identifier: "en")
    /// Abroad in Georgia, showing rubles, dollars and lari.
    private let settings = Settings(displayCurrencies: ["RUB", "USD", "GEL"], localCurrency: "GEL")
    private let subscriptions = Obligation(name: "Подписки", amountMinor: 69_900, currency: "RUB", dayOfMonth: 1)

    @Test func aNewPaymentStartsEmptyInTheLocalCurrency() {
        let form = ObligationForm(editing: nil, settings: settings)
        #expect(form.isNew)
        #expect(form.currency == "GEL")
        #expect(form.preferredCurrencies == ["GEL", "RUB", "USD"])
        #expect(form.name.isEmpty && form.amountText.isEmpty && form.day == nil)
        #expect(form.output == nil)
        #expect(form.title.text(in: ru) == "Новый платёж")
        #expect(form.title.text(in: en) == "New payment")
        #expect(form.saveTitle.text(in: ru) == "Добавить")
        #expect(form.saveTitle.text(in: en) == "Add")
    }

    @Test func aNameAnAmountAndADayMakeAPayment() throws {
        let id = UUID()
        var form = ObligationForm(editing: nil, settings: settings, obligationId: id)
        form.name = "  Аренда "
        form.amountText = "900"
        #expect(form.output == nil, "no day yet")
        form.day = 1
        let payment = try #require(form.output)
        #expect(payment == Obligation(id: id, name: "Аренда", amountMinor: 90_000, currency: "GEL", dayOfMonth: 1))
    }

    @Test func eachMissingPieceKeepsItFromSaving() {
        var form = ObligationForm(editing: nil, settings: settings)
        form.name = "Аренда"
        form.amountText = "900"
        form.day = 31
        #expect(form.canSave)

        form.name = "   "
        #expect(!form.canSave, "a blank name")
        form.name = "Аренда"

        form.amountText = ""
        #expect(!form.canSave, "no amount")
        #expect(!form.isAmountInvalid, "nothing typed is not a mistake")

        form.amountText = "0"
        #expect(!form.canSave, "nothing to pay")
        #expect(form.isAmountInvalid)

        form.amountText = "abc"
        #expect(!form.canSave)
        #expect(form.isAmountInvalid)
    }

    @Test func aBigAmountReadsThroughItsGrouping() throws {
        var form = ObligationForm(editing: nil, settings: settings)
        form.name = "Ипотека"
        form.amountText = AmountInput.grouped("150000,5")
        form.day = 5
        #expect(form.amountText == "150\u{202F}000,5")
        #expect(try #require(form.output).amountMinor == 15_000_050)
    }

    @Test func anotherCurrencyRereadsTheSameText() throws {
        var form = ObligationForm(editing: nil, settings: settings)
        form.name = "VPN"
        form.amountText = "5"
        form.day = 12
        form.currency = "USD"
        let payment = try #require(form.output)
        #expect(payment.currency == "USD")
        #expect(payment.amountMinor == 500)
    }

    @Test func editingOpensThePaymentAndKeepsItsId() throws {
        var form = ObligationForm(editing: subscriptions, settings: settings)
        #expect(!form.isNew)
        #expect(form.name == "Подписки")
        #expect(form.amountText == "699")
        #expect(form.currency == "RUB")
        #expect(form.day == 1)
        #expect(form.title.text(in: ru) == "Платёж")
        #expect(form.title.text(in: en) == "Payment")
        #expect(form.saveTitle.text(in: ru) == "Сохранить")
        #expect(form.saveTitle.text(in: en) == "Save")

        form.amountText = "799"
        form.day = 3
        let payment = try #require(form.output)
        #expect(payment.id == subscriptions.id)
        #expect(payment.amountMinor == 79_900)
        #expect(payment.dayOfMonth == 3)
    }

    @Test func aPaymentInACurrencyNoLongerShownKeepsItOnOffer() {
        let baht = Obligation(name: "Кондо", amountMinor: 1_500_000, currency: "THB", dayOfMonth: 28)
        let form = ObligationForm(editing: baht, settings: settings)
        #expect(form.preferredCurrencies == ["GEL", "RUB", "USD", "THB"])
        #expect(form.amountText == "15\u{202F}000")
    }

    @Test func kopecksShowOnlyWhenThereAreAny() {
        let odd = Obligation(name: "Связь", amountMinor: 45_050, currency: "RUB", dayOfMonth: 20)
        #expect(ObligationForm(editing: odd, settings: settings).amountText == "450,5")
    }

    @Test func aRowSaysTheDayAndTheAmount() {
        let row = ObligationRow(subscriptions)
        #expect(row.amount == "699 ₽")
        #expect(row.dayText(in: ru) == "1-го")
        #expect(row.dayText(in: en) == "day 1")
        #expect(row.accessibilityLabel(in: ru) == "Подписки, 699 российских рублей, 1-го")
        #expect(row.accessibilityLabel(in: en) == "Подписки, 699 Russian rubles, day 1")
    }

    @Test func theUndoToastNamesThePayment() {
        #expect(ObligationForm.deletedMessage("Аренда", in: ru) == "Платёж «Аренда» удалён")
        #expect(ObligationForm.deletedMessage("Rent", in: en) == "Payment “Rent” deleted")
    }
}
