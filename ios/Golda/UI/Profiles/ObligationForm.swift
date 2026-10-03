import Foundation
import GoldaCore

/// Everything the payment form knows and decides, the state and rules of Android's
/// `ObligationSheet` without the views: a name, an amount above zero in a currency and a day of
/// the month make a payment; anything less saves nothing.
struct ObligationForm: Equatable, Sendable {
    /// The payment being changed; nil for a new one.
    let editing: Obligation?
    /// The id a new payment gets. Fixed for the life of the form, so a second tap on "Add" updates
    /// the payment the first one created instead of adding another.
    let obligationId: UUID
    /// Offered first, in the app's one order: the local currency, the shown ones, and an edited
    /// payment's own.
    let preferredCurrencies: [String]
    /// The rest of the common currencies.
    let otherCurrencies: [String]

    var name: String
    /// As typed; the big field groups thousands while typing, and reading ignores the grouping.
    var amountText: String
    /// Unlike an account's, a payment's currency can change: it has no postings in it. What was
    /// typed stays and is read in the new currency.
    var currency: String
    var day: Int?

    init(editing: Obligation?, settings: Settings, obligationId: UUID = UUID()) {
        self.editing = editing
        self.obligationId = editing?.id ?? obligationId
        let currency = editing?.currency ?? settings.localCurrency
        let preferred = CurrencyDisplay.currencyChoices(settings: settings, extra: [currency])
        preferredCurrencies = preferred
        otherCurrencies = Currencies.common.filter { !preferred.contains($0) }
        self.currency = currency
        name = editing?.name ?? ""
        amountText = editing.flatMap { $0.amountMinor > 0 ? AmountInput.grouped(Fmt.editable($0.amountMinor, $0.currency)) : nil } ?? ""
        day = editing.flatMap { (1...31).contains($0.dayOfMonth) ? $0.dayOfMonth : nil }
    }

    var isNew: Bool { editing == nil }

    /// Above zero, in minor units of [currency]; nil until then.
    var amount: Int64? {
        Fmt.parseMinor(amountText, currency).flatMap { $0 > 0 ? $0 : nil }
    }

    /// Something is typed that is not an amount to pay: the field turns red.
    var isAmountInvalid: Bool { !ProfileNumber.isBlank(amountText) && amount == nil }

    var canSave: Bool { output != nil }

    /// What saving writes; nil while the name is blank, the amount missing or no day picked.
    var output: Obligation? {
        guard let name = ProfileName.cleaned(name), let amount, let day else { return nil }
        return Obligation(id: obligationId, name: name, amountMinor: amount, currency: currency, dayOfMonth: day)
    }

    // MARK: Text

    var title: LocalizedStringResource {
        isNew
            ? LocalizedStringResource("New payment", table: "Profiles", comment: "Title of the payment form when adding one.")
            : LocalizedStringResource("Payment", table: "Profiles", comment: "A payment: the title of the payment form when changing one, and the last row of the payments, “+ Payment”.")
    }

    /// "Add" for a new payment, "Save" for a change, as on Android.
    var saveTitle: LocalizedStringResource {
        isNew
            ? LocalizedStringResource("Add", table: "Profiles", comment: "Payment form: the main action that adds the payment.")
            : LocalizedStringResource("Save", table: "Profiles", comment: "Sheets of the profile screen: the main action that saves the change.")
    }

    static let namePrompt = LocalizedStringResource("What is it", table: "Profiles", comment: "Payment form: the placeholder of the payment's name, like rent.")
    static let amountTitle = LocalizedStringResource("Amount", table: "Profiles", comment: "Payment form: what VoiceOver calls the amount field.")
    static let currencyTitle = LocalizedStringResource("Currency", table: "Profiles", comment: "Payment form: the payment's currency.")
    static let dayTitle = LocalizedStringResource("Day of the month", table: "Profiles", comment: "Payment form: the header over the grid of days.")
    static let deleteTitle = LocalizedStringResource("Delete payment", table: "Profiles", comment: "Payment form and row: deletes the payment (it can be undone).")

    /// "Платёж «Аренда» удалён", the undo toast's message.
    static func deletedMessage(_ name: String, in locale: Locale) -> String {
        LocalizedStringResource("Payment “\(name)” deleted", table: "Profiles", comment: "Toast after a payment was deleted, with its name; “Undo” follows.").text(in: locale)
    }
}

/// One payment in the profile's list: its name, its day and the amount in its own currency.
struct ObligationRow: Equatable, Identifiable, Sendable {
    let obligation: Obligation
    /// "699 ₽".
    let amount: String

    init(_ obligation: Obligation) {
        self.obligation = obligation
        amount = Fmt.amount(obligation.amountMinor, obligation.currency)
    }

    var id: UUID { obligation.id }
    var name: String { obligation.name }

    func dayText(in locale: Locale) -> String {
        ProfileIncome.paydayText(obligation.dayOfMonth, in: locale)
    }

    /// "Подписки, 699 российских рублей, 1-го": the amount in words.
    func accessibilityLabel(in locale: Locale) -> String {
        [name, SpokenAmount.text(amount, locale: locale), dayText(in: locale)].joined(separator: ", ")
    }
}
