import Foundation
import GoldaCore

/// Everything the operation form knows and decides: the state and rules of Android's `EntrySheet`
/// without the views. The defaults a new operation starts with, what changing the type, the
/// account or the currency does, when a second amount appears and whether it is an estimate, what
/// makes the form valid and the `Draft` that saving hands over. "Сомневаюсь" is a second state of
/// a new expense: the same amount, weighed up as a `Consider`.
///
/// The sheet only lays it out; tests drive it with a fixed day and clock.
struct EntryFormModel: Sendable {
    /// From where to where a transfer goes.
    struct Route: Equatable, Sendable {
        let from: UUID
        let to: UUID?
    }

    /// The one line under the big number.
    enum UnderLine: Equatable, Sendable {
        /// Income says nothing there, and neither does a transfer before it has an amount: its
        /// balances are in the tiles above.
        case none
        /// Before an amount is typed: "Можно сегодня 1 849 ₽", in the main currency.
        case safeToday(String)
        /// A purchase in another currency than the account's: what the card is charged,
        /// "≈ 5,87 $ со счёта". Nil while the text cannot be read; a tap corrects it.
        case charged(amount: String?, isEstimate: Bool)
        /// A transfer that changes currency: what the other account receives, "→ ≈ 109,21 $".
        case received(amount: String?, isEstimate: Bool)
        /// What the amount comes to in the other shown currencies, "45,8 $ · 124 ₾"; the amount
        /// itself when no other currency is shown (`approximate` is then false).
        case others(String, approximate: Bool)
    }

    /// One of the facts "Сомневаюсь" lays out.
    struct Fact: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            case hoursOfWork, goalShare, daysOfBudget
        }

        let kind: Kind
        /// "2,6", "12,5 %", "3,6"; a dash until the facts are known.
        let value: String
    }

    let data: AppData
    let request: EntryRequest
    /// The day the form opened on, where "today" and "yesterday" are counted from.
    let today: LocalDate
    /// Where a new purchase is paid from: where voice would pay it (`VoiceMapper.pick`).
    let defaultAccountId: UUID?
    /// The latest transfer's route: the next one is usually the same trip.
    let lastTransfer: Route?

    private(set) var type: OpType
    private(set) var accountId: UUID?
    private(set) var toAccountId: UUID?
    /// The currency the price is in. Only an expense picks it; the others follow the account.
    private(set) var purchaseCurrency: String
    /// The big number as typed, grouped by thousands.
    var amountText: String
    /// The second amount as last typed; while it is not `secondEdited` the estimate stands instead.
    private var secondInput: String
    /// The second amount was typed (or stored from the bank), not estimated.
    private(set) var secondEdited: Bool
    /// The second amount is open as a field.
    var isEditingSecond = false
    private(set) var categoryKey: String?
    var note: String
    var date: LocalDate
    /// "Сомневаюсь": the form below the amount turns into what the price means.
    var isDeciding: Bool

    // MARK: Building

    /// The form for [request] over the open profile's books, on [today].
    init(data: AppData, request: EntryRequest, today: LocalDate) {
        self.data = data
        self.request = request
        self.today = today
        let editing = request.editing
        let op = editing?.op
        let asked = request.consider
        let accounts = data.accounts
        let out = editing.flatMap { full in full.postings.first { $0.amountMinor < 0 } ?? full.postings.first }
        let into = editing.flatMap { full in full.postings.first { $0.amountMinor > 0 && $0.id != out?.id } }

        // A new purchase is paid from where voice would pay it: the last account if it is in the
        // purchase's currency (the local one, or what is being decided on), else a free-money
        // account in that currency, else the last one anyway, and the charge is converted. So
        // changing the local currency moves the default account too, not only the currency.
        defaultAccountId = VoiceMapper.pick(accounts, asked?.currency ?? data.settings.localCurrency, data.settings)?.id
        lastTransfer = data.operations.first { $0.op.type == .transfer }.flatMap { full in
            full.postings.first { $0.amountMinor < 0 }.map { from in
                Route(from: from.accountId, to: full.postings.first { $0.amountMinor > 0 }?.accountId)
            }
        }

        let accountId = out?.accountId ?? defaultAccountId
        let account = accountId.flatMap { data.accountById[$0] }
        let toAccountId = into?.accountId ?? accounts.first { $0.id != accountId }?.id
        let toAccount = toAccountId.flatMap { data.accountById[$0] }
        type = op?.type ?? .expense
        self.accountId = accountId
        self.toAccountId = toAccountId
        // A new purchase starts in the local currency, as voice does; an edit keeps what was stored.
        purchaseCurrency = op?.purchaseCurrency
            ?? (op != nil ? account?.currency ?? "RUB" : asked?.currency ?? data.settings.localCurrency)

        if let asked {
            amountText = AmountInput.grouped(Fmt.editable(asked.amountMinor, asked.currency))
        } else if let price = op?.purchaseAmountMinor, let code = op?.purchaseCurrency {
            amountText = AmountInput.grouped(Fmt.editable(price, code))
        } else if let out, let account {
            amountText = AmountInput.grouped(Fmt.editable(Int64(clamping: out.amountMinor.magnitude), account.currency))
        } else {
            amountText = ""
        }
        // The second amount: what the card was charged, or what the other account received.
        if op?.purchaseCurrency != nil, let out, let account {
            secondInput = Fmt.editable(-out.amountMinor, account.currency)
        } else if let into, let toAccount {
            secondInput = Fmt.editable(into.amountMinor, toAccount.currency)
        } else {
            secondInput = ""
        }
        secondEdited = op.map { !$0.isEstimate } ?? false
        categoryKey = op?.categoryKey
        note = op?.note ?? asked?.title ?? ""
        date = op.map { Ledger.localDate($0.timestamp, data.zone) } ?? today
        isDeciding = asked != nil
    }

    /// Opening balances and reconciliation adjustments have nothing to edit, only to remove:
    /// they open the bookkeeping sheet instead of the form.
    static func isBookkeeping(_ request: EntryRequest) -> Bool {
        guard let type = request.editing?.op.type else { return false }
        return type != .expense && type != .income && type != .transfer
    }

    // MARK: What it is

    var isNew: Bool { request.editing == nil }

    var account: Account? { accountId.flatMap { data.accountById[$0] } }

    var toAccount: Account? { toAccountId.flatMap { data.accountById[$0] } }

    /// Every account of the profile can pay or be paid into, in their order.
    var accounts: [Account] { data.accounts }

    /// Where a transfer can go: anywhere but where it comes from.
    var destinations: [Account] { data.accounts.filter { $0.id != accountId } }

    /// The currency the big number is typed in: the price's for an expense, the account's otherwise.
    var amountCode: String {
        type == .expense ? purchaseCurrency : account?.currency ?? "RUB"
    }

    /// The big number, when it is a positive amount.
    var amount: Int64? {
        Fmt.parseMinor(amountText, amountCode).flatMap { $0 > 0 ? $0 : nil }
    }

    /// Something is typed that cannot be read as an amount: the number turns red.
    var isAmountInvalid: Bool {
        !amountText.allSatisfy(\.isWhitespace) && amount == nil
    }

    /// The currencies the price can be in, in the app's one order, the account's own included.
    var currencyChoices: [String] {
        data.currencyChoices(extra: account.map { [$0.currency] } ?? [])
    }

    /// Only an expense picks its currency: income and transfers are in the account's.
    var picksCurrency: Bool { type == .expense }

    // MARK: The second amount

    /// The second amount appears when the money changes currency on its way: a purchase charged
    /// to an account in another currency, a transfer between currencies.
    var secondCode: String? {
        switch type {
        case .expense:
            account.flatMap { $0.currency != purchaseCurrency ? $0.currency : nil }
        case .transfer:
            toAccount.flatMap { $0.currency != account?.currency ? $0.currency : nil }
        default:
            nil
        }
    }

    /// What the second amount would be at today's rates: the card's charge with the payment
    /// system's cut, or the conversion at display rates.
    var estimate: Int64? {
        guard let amount, let secondCode, let account else { return nil }
        if type == .expense {
            return data.rates.cardCharge(amount, purchase: purchaseCurrency, account: account.currency)
        }
        return data.rates.convert(amount, from: account.currency, to: secondCode)
    }

    /// The second amount's text: as typed once it is edited, the estimate until then.
    var secondText: String {
        if secondEdited { return secondInput }
        guard let estimate, let secondCode else { return "" }
        return Fmt.editable(estimate, secondCode)
    }

    var second: Int64? {
        secondCode.flatMap { Fmt.parseMinor(secondText, $0) }
    }

    /// The bank's real figure typed over the estimate.
    mutating func typeSecond(_ text: String) {
        secondInput = text
        secondEdited = true
    }

    // MARK: Changes

    /// A new transfer starts where the last one did; anything else from the usual account. The
    /// category, the second amount and its field start over; income and transfers are in their
    /// account's currency.
    mutating func pickType(_ value: OpType) {
        if isNew, value != type {
            if value == .transfer {
                accountId = lastTransfer?.from ?? data.accounts.first { $0.currency == "RUB" }?.id ?? accountId
                toAccountId = lastTransfer?.to.flatMap { $0 != accountId ? $0 : nil }
                    ?? data.accounts.first { $0.id != accountId }?.id
            } else if type == .transfer {
                accountId = defaultAccountId
            }
        }
        type = value
        categoryKey = nil
        isEditingSecond = false
        secondEdited = false
        if value != .expense { purchaseCurrency = account?.currency ?? purchaseCurrency }
    }

    /// Paying from (or sending from) another account. A price in the old account's currency moves
    /// to the new one's; a price in a currency of its own stays. The destination steps aside when
    /// it is the account picked.
    mutating func pickAccount(_ id: UUID) {
        guard let picked = data.accountById[id] else { return }
        if purchaseCurrency == account?.currency || type != .expense { purchaseCurrency = picked.currency }
        accountId = id
        if toAccountId == id { toAccountId = data.accounts.first { $0.id != id }?.id }
        secondEdited = false
    }

    mutating func pickDestination(_ id: UUID) {
        guard data.accountById[id] != nil else { return }
        toAccountId = id
        secondEdited = false
    }

    mutating func swapRoute() {
        (accountId, toAccountId) = (toAccountId, accountId)
        secondEdited = false
    }

    /// The price's currency; whatever was typed is read in it, and the charge is estimated afresh.
    mutating func pickCurrency(_ code: String) {
        purchaseCurrency = code
        secondEdited = false
    }

    /// A second tap on the picked category clears it.
    mutating func pickCategory(_ key: String) {
        categoryKey = categoryKey == key ? nil : key
    }

    // MARK: Saving

    var isValid: Bool {
        guard let account, amount != nil else { return false }
        if secondCode != nil, (second ?? 0) <= 0 { return false }
        if type == .transfer, toAccount == nil || toAccount?.id == account.id { return false }
        return true
    }

    /// What saving writes, at [now]; nil while the form is not valid. The time stays as stored
    /// while the day does not change; today is now, and another day is its noon.
    func draft(now: Int64) -> Draft? {
        guard isValid, let account, let amount else { return nil }
        let op = request.editing?.op
        let zone = data.zone
        let timestamp: Int64
        if let op, Ledger.localDate(op.timestamp, zone) == date {
            timestamp = op.timestamp
        } else if date == LocalDate(epochMillis: now, in: zone) {
            timestamp = now
        } else {
            timestamp = date.atTimeMillis(hour: 12, in: zone)
        }
        let foreignPurchase = type == .expense && secondCode != nil
        return Draft(
            type: type,
            timestamp: timestamp,
            accountId: account.id,
            amountMinor: foreignPurchase ? second ?? amount : amount,
            toAccountId: type == .transfer ? toAccount?.id : nil,
            toAmountMinor: type == .transfer ? second ?? amount : nil,
            categoryKey: type == .transfer ? nil : categoryKey,
            note: note,
            purchaseAmountMinor: foreignPurchase ? amount : nil,
            purchaseCurrency: foreignPurchase ? purchaseCurrency : nil,
            isEstimate: secondCode != nil && !secondEdited,
            voiceText: op?.voiceText,
            id: op?.id
        )
    }

    /// "Беру" records the expense as the form has it; with neither a note nor a category it is
    /// called [unnamed] ("Покупка"), so the list does not show an empty row.
    func purchaseDraft(now: Int64, unnamed: String) -> Draft? {
        guard var draft = draft(now: now) else { return nil }
        if draft.note.allSatisfy(\.isWhitespace), draft.categoryKey == nil { draft.note = unnamed }
        return draft
    }

    // MARK: "Сомневаюсь"

    /// A new expense can be weighed up instead of recorded.
    var offersConsider: Bool { isNew && type == .expense && !isDeciding }

    /// "Подумаю" only for something not yet thought about: a waiting wish has been.
    var offersThink: Bool { request.wishId == nil }

    /// "Back" returns to the form only when "Сомневаюсь" was opened from it; a purchase that came
    /// to be decided on (voice, the wishlist) has no form behind it.
    var returnsToForm: Bool { isDeciding && request.consider == nil }

    /// The purchase being weighed up, named by its note, else its category, else [unnamed].
    func consider(categoryName: (String) -> String, unnamed: String) -> Consider? {
        guard let amount else { return nil }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = !trimmed.isEmpty ? trimmed : categoryKey.map(categoryName) ?? unnamed
        return Consider(title: title, amountMinor: amount, currency: purchaseCurrency)
    }

    /// What asks the repository for fresh facts: they depend on the price, not on the name.
    struct FactsKey: Equatable, Sendable {
        let isDeciding: Bool
        let amount: Int64?
        let currency: String
    }

    var factsKey: FactsKey { FactsKey(isDeciding: isDeciding, amount: amount, currency: purchaseCurrency) }

    /// The facts as tiles: hours of work first and big, then the share of the main goal and the
    /// days of budget. Dashes while the facts are not known, only for what can be known: hours
    /// need an income, a share needs a main goal.
    func facts(_ known: Facts?) -> [Fact] {
        guard let known else {
            return [
                data.settings.hourNet > 0 ? Fact(kind: .hoursOfWork, value: "—") : nil,
                data.goals.contains(where: \.isMain) ? Fact(kind: .goalShare, value: "— %") : nil,
                Fact(kind: .daysOfBudget, value: "—"),
            ].compactMap { $0 }
        }
        return [
            known.hoursValue.map { Fact(kind: .hoursOfWork, value: Fmt.number($0, decimals: 1)) },
            known.goalShare.map { Fact(kind: .goalShare, value: Fmt.percent($0)) },
            known.daysValue.map { Fact(kind: .daysOfBudget, value: Fmt.number($0, decimals: 1)) },
        ].compactMap { $0 }
    }

    // MARK: What the screen shows

    var underLine: UnderLine {
        if type == .income { return .none }
        guard let amount else {
            if type == .transfer { return .none }
            let budget = Budget.today(
                states: data.states, operations: data.operations, settings: data.settings, today: today,
                zone: data.zone, obligations: data.allObligations, rates: data.rates
            )
            return .safeToday(data.base.approx(budget.leftTodayRub))
        }
        if let secondCode {
            let written = Fmt.parseMinor(secondText, secondCode).map { Fmt.amount($0, secondCode) }
            if type == .transfer { return .received(amount: written, isEstimate: !secondEdited) }
            if type == .expense, !isDeciding { return .charged(amount: written, isEstimate: !secondEdited) }
        }
        let rub = amountCode == "RUB" ? amount : data.rates.rubMinor(amount, amountCode)
        let others = rub.map { data.others(rubMinor: $0, exclude: amountCode) } ?? ""
        return others.isEmpty ? .others(Fmt.amount(amount, amountCode), approximate: false) : .others(others, approximate: true)
    }

    /// The categories of the type, every one at once, the most used first.
    var categories: [GoldaCore.Category] {
        guard type != .transfer else { return [] }
        let kind: CategoryKind = type == .income ? .income : .expense
        var uses: [String: Int] = [:]
        for full in data.operations {
            if let key = full.op.categoryKey { uses[key, default: 0] += 1 }
        }
        return data.categories.categories(kind)
            .enumerated()
            .sorted { l, r in
                let a = uses[l.element.key] ?? 0, b = uses[r.element.key] ?? 0
                if a != b { return a > b }
                if l.element.sort != r.element.sort { return l.element.sort < r.element.sort }
                return l.offset < r.offset
            }
            .map(\.element)
    }

    /// An account's balance in its own currency, for the route tiles.
    func balance(of account: Account) -> String {
        Fmt.amount(data.states[account.id]?.balanceMinor ?? 0, account.currency)
    }
}
