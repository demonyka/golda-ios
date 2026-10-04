import Foundation
import GoldaCore

/// Everything the account form knows and decides, the state and rules of Android's `AccountSheet`
/// without the views: the defaults each type brings, what makes the form valid, and the `Account`
/// with its opening balance that saving hands over. The sheet only lays it out.
struct AccountFormModel: Equatable, Sendable {
    /// Where the account stands among the profile's: with a bank's other accounts, or alone.
    enum GroupChoice: Hashable, Sendable {
        case none
        case existing(String)
        /// The name typed in `newGroupName`.
        case new
    }

    /// The fields that can hold text the form cannot read; the sheet paints them red.
    enum Field: Hashable, Sendable {
        case opening, rate, payment
    }

    /// What saving hands to the repository.
    struct Output: Equatable, Sendable {
        let account: Account
        /// A new account's opening balance as the ledger keeps it: what is owed on a debt is
        /// negative. Nil when editing, where the repository would ignore it anyway.
        let openingMinor: Int64?
    }

    /// The account being changed; nil for a new one.
    let editing: Account?
    /// The id a new account gets. Fixed for the life of the form, so a second tap on "Add" updates
    /// the account the first one created instead of adding another.
    let accountId: UUID
    /// The groups the profile's accounts are in, in the order of the accounts.
    let existingGroups: [String]
    /// Offered first, in the app's one order: the local currency, the shown ones, and an edited
    /// account's own. Every other currency follows them in the list (`CurrencySections`).
    let preferredCurrencies: [String]
    /// A new account goes after the last one.
    let nextSort: Int

    var name: String
    var type: AccountType
    /// Picked while creating only (`pickCurrency`): an account's postings are in its currency, so
    /// once it exists the currency is fixed, as on Android.
    private(set) var currency: String
    var groupChoice: GroupChoice
    var newGroupName: String
    var paymentDay: Int?
    /// Credit cards: the last day of the interest-free period.
    var graceUntil: LocalDate?
    /// Nil until the switch is touched; until then the switch follows the type.
    private var includeInFreeChoice: Bool?

    /// How much is there now (or owed, for a debt), as typed. The big field groups thousands
    /// while typing (`AmountInput`); reading ignores the grouping.
    var openingText: String

    /// Yearly percent, as typed.
    var rateText: String

    /// A debt's monthly payment, as typed. A plain field, as Android's, so no grouping.
    var paymentText: String

    // MARK: Building

    /// The form for [editing], or for a new account when it is nil, over the open profile's books.
    init(data: AppData, editing: Account?, accountId: UUID = UUID()) {
        self.init(accounts: data.accounts, settings: data.settings, editing: editing, accountId: accountId)
    }

    init(accounts: [Account], settings: Settings, editing: Account?, accountId: UUID = UUID()) {
        self.editing = editing
        self.accountId = editing?.id ?? accountId
        var groups: [String] = []
        for group in accounts.compactMap(\.groupName) where !group.isBlank && !groups.contains(group) {
            groups.append(group)
        }
        // A list read a moment before the account got its group still offers that group.
        if let own = editing?.groupName, !own.isBlank, !groups.contains(own) { groups.append(own) }
        existingGroups = groups
        preferredCurrencies = CurrencyDisplay.currencyChoices(settings: settings, extra: editing.map { [$0.currency] } ?? [])
        nextSort = (accounts.map(\.sort).max() ?? -1) + 1

        name = editing?.name ?? ""
        type = editing?.type ?? .card
        currency = editing?.currency ?? settings.localCurrency
        if let group = editing?.groupName, !group.isBlank {
            groupChoice = .existing(group)
        } else {
            // With no group to pick from, the field to type one is all there is.
            groupChoice = groups.isEmpty ? .new : .none
        }
        newGroupName = ""
        includeInFreeChoice = editing?.includeInFree
        openingText = ""
        rateText = editing?.interestRate.map { Fmt.number($0) } ?? ""
        paymentText = editing.flatMap { account in account.paymentMinor.map { Fmt.editable($0, account.currency) } } ?? ""
        paymentDay = editing?.paymentDay
        graceUntil = editing?.graceUntil.map { LocalDate(epochDay: Int($0)) }
    }

    // MARK: What the type brings

    var isNew: Bool { editing == nil }

    var isDebt: Bool { type == .credit || type == .loan }

    /// Savings earn a rate and debts cost one.
    var hasRate: Bool { type == .savings || isDebt }

    /// Only a credit card has an interest-free period.
    var hasGracePeriod: Bool { type == .credit }

    /// Cards and cash are money to spend; savings and debts stay out of "Можно сегодня" unless the
    /// switch says otherwise.
    static func countsInBudgetByDefault(_ type: AccountType) -> Bool {
        type == .card || type == .cash
    }

    /// Counts towards "Можно сегодня". Follows the type until it is set; once set, it stays through
    /// a change of type.
    var includeInFree: Bool {
        get { includeInFreeChoice ?? Self.countsInBudgetByDefault(type) }
        set { includeInFreeChoice = newValue }
    }

    /// Changes the currency of a new account; an existing one keeps its own. Whatever was typed
    /// stays as typed and is read in the new currency.
    mutating func pickCurrency(_ code: String) {
        guard isNew else { return }
        currency = code
    }

    /// Turns the interest-free period on (starting today, the day a picker opens on) or off.
    mutating func setGracePeriod(_ on: Bool, today: LocalDate) {
        graceUntil = on ? (graceUntil ?? today) : nil
    }

    /// The group the account will be saved in.
    var groupName: String? {
        switch groupChoice {
        case .none: nil
        case .existing(let name): name
        case .new: newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
    }

    // MARK: Reading what was typed

    /// A field's content: nothing, something the form can read, or something it cannot.
    enum Parsed<Value: Equatable & Sendable>: Equatable, Sendable {
        case empty
        case value(Value)
        case invalid

        var value: Value? {
            if case .value(let value) = self { return value }
            return nil
        }
    }

    /// The opening balance as typed, always positive.
    var opening: Parsed<Int64> { Self.amount(openingText, currency) }

    var rate: Parsed<Double> {
        if rateText.isBlank { return .empty }
        return Fmt.parseDouble(rateText).map(Parsed.value) ?? .invalid
    }

    var payment: Parsed<Int64> { Self.amount(paymentText, currency) }

    /// Fields the account uses whose text cannot be read. A field the type hides does not count:
    /// it is not saved.
    var invalidFields: Set<Field> {
        var fields: Set<Field> = []
        if isNew, opening == .invalid { fields.insert(.opening) }
        if hasRate, rate == .invalid { fields.insert(.rate) }
        if isDebt, payment == .invalid { fields.insert(.payment) }
        return fields
    }

    var canSave: Bool { output != nil }

    /// What saving writes; nil while the name is empty or a field cannot be read.
    var output: Output? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, invalidFields.isEmpty else { return nil }
        let account = Account(
            id: editing?.id ?? accountId,
            name: trimmedName,
            currency: currency,
            type: type,
            groupName: groupName,
            includeInFree: includeInFree,
            interestRate: hasRate ? rate.value : nil,
            sort: editing?.sort ?? nextSort,
            paymentDay: isDebt ? paymentDay : nil,
            paymentMinor: isDebt ? payment.value : nil,
            graceUntil: hasGracePeriod ? graceUntil.map { Int64($0.epochDay) } : nil,
            // The repository keeps the stored stamp whatever comes here; this only spares the
            // reader a wrong-looking value.
            reconciledAt: editing?.reconciledAt
        )
        guard isNew else { return Output(account: account, openingMinor: nil) }
        // How much is owed is typed as a positive amount; the ledger keeps a debt negative.
        let typed = opening.value ?? 0
        return Output(account: account, openingMinor: isDebt ? -typed : typed)
    }

    private static func amount(_ text: String, _ currency: String) -> Parsed<Int64> {
        if text.isBlank { return .empty }
        return Fmt.parseMinor(text, currency).map(Parsed.value) ?? .invalid
    }

    // MARK: Text

    /// The short name a type tile has room for.
    static func typeTitle(_ type: AccountType) -> LocalizedStringResource {
        switch type {
        case .card: LocalizedStringResource("Card", table: "AccountForm", comment: "Account type tile: a bank card.")
        case .cash: LocalizedStringResource("Cash", table: "AccountForm", comment: "Account type tile: cash.")
        case .savings: LocalizedStringResource("Savings", table: "AccountForm", comment: "Account type tile: a savings account.")
        case .credit: LocalizedStringResource("Credit", table: "AccountForm", comment: "Account type tile: a credit card.")
        case .loan: LocalizedStringResource("Loan", table: "AccountForm", comment: "Account type tile: a loan.")
        }
    }

    /// "₾ GEL", or the code alone when the currency has no symbol of its own.
    static func currencyLabel(_ code: String) -> String {
        let symbol = Currencies.symbol(code)
        return symbol == code ? code : "\(symbol) \(code)"
    }

    var title: LocalizedStringResource {
        isNew
            ? LocalizedStringResource("New account", table: "AccountForm", comment: "Title of the account form when creating one.")
            : LocalizedStringResource("Account", table: "AccountForm", comment: "Title of the account form when editing one.")
    }

    /// The main action: "Add" for a new account, "Save" for a change, as on Android.
    var saveTitle: LocalizedStringResource {
        isNew
            ? LocalizedStringResource("Add", table: "AccountForm", comment: "Account form: the main action that creates the account.")
            : LocalizedStringResource("Save", table: "AccountForm", comment: "Account form: the main action that saves the changes.")
    }

    var openingCaption: LocalizedStringResource {
        isDebt
            ? LocalizedStringResource("How much you owe now", table: "AccountForm", comment: "Account form: caption over the opening balance of a debt.")
            : LocalizedStringResource("How much is there now", table: "AccountForm", comment: "Account form: caption over the opening balance.")
    }

    var rateTitle: LocalizedStringResource {
        isDebt
            ? LocalizedStringResource("Rate", table: "AccountForm", comment: "Account form: a debt's yearly interest rate.")
            : LocalizedStringResource("Rate on balance", table: "AccountForm", comment: "Account form: the yearly rate a savings account pays.")
    }

    var paymentTitle: LocalizedStringResource {
        type == .loan
            ? LocalizedStringResource("Payment", table: "AccountForm", comment: "A loan's monthly payment.")
            : LocalizedStringResource("Minimum payment", table: "AccountForm", comment: "A credit card's monthly minimum payment.")
    }

    /// "Delete “Кредитка”?"
    func deleteQuestion(in locale: Locale) -> String {
        let name = editing?.name ?? name
        return LocalizedStringResource("Delete “\(name)”?", table: "AccountForm", comment: "Title of the confirmation before an account is deleted, with its name.").text(in: locale)
    }

    static let deleteWarning = LocalizedStringResource(
        "All operations with this account go too, transfers included.", table: "AccountForm",
        comment: "Account form: what deleting an account takes with it."
    )
}

/// What an amount field does to the text while it is typed: "1500" reads "1 500", with the narrow
/// no-break spaces `Fmt` writes between thousands (and `Fmt.parseMinor` ignores). The port of
/// Android's `Grouping`, applied to the text itself since a SwiftUI field has no visual transform.
enum AmountInput {
    private static let thousands: Character = "\u{202F}"

    /// [text] with its whole part grouped by thousands; text that is not a plain amount comes back
    /// without spaces but otherwise as typed, so the form can say it cannot read it.
    static func grouped(_ text: String) -> String {
        let bare = text.filter { $0 != " " && $0 != thousands && $0 != "\u{00A0}" }
        guard let match = bare.wholeMatch(of: /([0-9]+)([.,][0-9]*)?/) else { return bare }
        let digits = String(match.output.1)
        let fraction = match.output.2.map(String.init) ?? ""
        var out = ""
        for (offset, digit) in digits.enumerated() {
            if offset > 0, (digits.count - offset) % 3 == 0 { out.append(thousands) }
            out.append(digit)
        }
        return out + fraction
    }

    /// One keystroke in a grouped field: [current] with [replacement] put over [range] (UTF-16, as
    /// UIKit gives it), regrouped, and the caret's UTF-16 offset after it, which stands after as
    /// many digits and separators as stood before it. Deleting a group space deletes the digit
    /// before it, or the key would seem to do nothing.
    static func edit(_ current: String, range: NSRange, replacement: String) -> (text: String, caret: Int) {
        let source = current as NSString
        var range = range
        if replacement.isEmpty, range.length > 0, range.location > 0,
           source.substring(with: range).allSatisfy(isGroupSpace) {
            range = NSRange(location: range.location - 1, length: range.length + 1)
        }
        let before = source.substring(to: range.location) + replacement
        let grouped = grouped(source.replacingCharacters(in: range, with: replacement))
        let kept = before.filter { !isGroupSpace($0) }.count
        var seen = 0
        var index = grouped.startIndex
        while index < grouped.endIndex, seen < kept {
            if !isGroupSpace(grouped[index]) { seen += 1 }
            index = grouped.index(after: index)
        }
        return (grouped, grouped[..<index].utf16.count)
    }

    private static func isGroupSpace(_ character: Character) -> Bool {
        character == " " || character == thousands || character == "\u{00A0}"
    }
}

extension String {
    /// Kotlin's `isBlank()`: empty or whitespace only.
    fileprivate var isBlank: Bool { allSatisfy(\.isWhitespace) }

    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
