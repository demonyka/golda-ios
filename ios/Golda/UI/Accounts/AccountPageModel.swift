import Foundation
import GoldaCore

/// What an account's page shows, the way Android's `AccountScreen` works it out: the type and the
/// bank, the balance, the other currencies, the rate it was bought at, the interest, and the
/// operations that touched it, each with this account's own side.
struct AccountPageModel: Equatable, Sendable {
    let state: AccountState
    /// "78,01 $", in the account's own currency.
    let balance: String
    /// What the balance cost, in the other shown currencies: "7 177 ₽ · 2 664 ₾"; may be empty.
    let others: String
    /// "92,5 ₽/$": rubles one unit cost on average. Only for a foreign account with money on it.
    let purchaseRate: String?
    let interest: InterestForecast?
    let days: [OperationDay]

    var account: Account { state.account }

    /// Nil when the account is not in [data], say deleted while its page was open.
    init?(data: AppData, accountId: UUID, today: LocalDate) {
        guard let state = data.states[accountId] else { return nil }
        self.state = state
        balance = Fmt.amount(state.balanceMinor, state.currency)
        others = data.others(rubMinor: state.rubMinor, exclude: state.currency)
        // Android compares with the ruble, not the main currency: the cost basis is kept in rubles.
        if state.currency != "RUB", let basis = state.costBasis {
            purchaseRate = Fmt.number(basis, decimals: 2) + " ₽/" + Currencies.symbol(state.currency)
        } else {
            purchaseRate = nil
        }
        interest = InterestForecast(state.account, operations: data.operations, today: today, zone: data.zone)
        let operations = data.visibleOperations.filter { full in full.postings.contains { $0.accountId == accountId } }
        days = OperationDay.group(operations, in: data, today: today, accountId: accountId)
    }

    /// "Карта · Мультивалютная": the type, and the bank when there is one.
    func caption(in locale: Locale) -> String {
        let type = AccountTypeTitle.resource(account.type).text(in: locale)
        guard let group = account.groupName, !group.allSatisfy(\.isWhitespace) else { return type }
        return type + " · " + group
    }

    /// "курс покупки 92,5 ₽/$", "bought at 92,5 ₽/$".
    func purchaseRateText(in locale: Locale) -> String? {
        purchaseRate.map { rate in
            LocalizedStringResource("bought at \(rate)", comment: "Account page: the average rate a foreign currency was bought at, “bought at 92,5 ₽/$”.").text(in: locale)
        }
    }

    /// The hero as one sentence for VoiceOver.
    func accessibilityLabel(in locale: Locale) -> String {
        var sentences = [caption(in: locale), SpokenAmount.text(balance, locale: locale)]
        if !others.isEmpty {
            sentences.append(others.components(separatedBy: " · ").map { SpokenAmount.text($0, locale: locale) }.joined(separator: ", "))
        }
        if let rate = purchaseRateText(in: locale) { sentences.append(rate) }
        if let interest { sentences.append(interest.text(in: locale, spoken: true)) }
        return sentences.joined(separator: ". ")
    }
}

/// The reconcile sheet's arithmetic, Android's `ReconcileSheet`: what the bank shows against what
/// the account holds, and what reconciling will record.
struct ReconcileEntry: Equatable, Sendable {
    let balanceMinor: Int64
    let currency: String
    /// What the field holds. It starts as the balance itself, so the number in the field can be
    /// erased and changed; emptied, it still means "the same as the balance".
    var text: String
    /// The decimal pad has no minus key, so the sign is a switch of its own. It starts as the
    /// balance's, so a debt is typed as the number the bank shows and stays a debt.
    var isNegative: Bool

    init(balanceMinor: Int64, currency: String) {
        self.balanceMinor = balanceMinor
        self.currency = currency
        isNegative = balanceMinor < 0
        // The magnitude only: the sign is the switch's.
        text = Fmt.editable(Int64(clamping: balanceMinor.magnitude), currency)
    }

    init(_ state: AccountState) {
        self.init(balanceMinor: state.balanceMinor, currency: state.currency)
    }

    /// The real balance: the account's own while nothing is typed, nil while the text is not an
    /// amount. A minus typed or pasted in front makes it negative, as on Android.
    var actualMinor: Int64? {
        let typed = text.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return balanceMinor }
        let minus = typed.hasPrefix("-") || typed.hasPrefix("−")
        guard let magnitude = Fmt.parseMinor(minus ? String(typed.dropFirst()) : typed, currency) else { return nil }
        return isNegative || minus ? -magnitude : magnitude
    }

    /// What goes in as an adjustment; nil while there is no amount, or past what an amount can hold.
    var differenceMinor: Int64? {
        guard let actualMinor else { return nil }
        let (difference, overflow) = actualMinor.subtractingReportingOverflow(balanceMinor)
        return overflow ? nil : difference
    }

    /// The bank shows the same: reconciling only notes the time.
    var matches: Bool { differenceMinor == 0 }

    var canSave: Bool { differenceMinor != nil }

    /// "Сходится" while nothing differs, "Записать −50 ₽" once something does. [spoken] says the
    /// amount in words, for VoiceOver.
    func actionTitle(in locale: Locale, spoken: Bool = false) -> String {
        guard let difference = differenceMinor, difference != 0 else {
            return LocalizedStringResource("It matches", comment: "Reconcile sheet's button while the typed balance is the same as the account's.").text(in: locale)
        }
        let written = Fmt.amount(difference, currency, signed: true)
        let amount = spoken ? SpokenAmount.text(written, locale: locale) : written
        return LocalizedStringResource("Record \(amount)", comment: "Reconcile sheet's button: record the difference, “Record −50 ₽”.").text(in: locale)
    }

    /// "Разница −50 ₽ запишется корректировкой"; nil while nothing differs.
    func differenceText(in locale: Locale, spoken: Bool = false) -> String? {
        guard let difference = differenceMinor, difference != 0 else { return nil }
        let written = Fmt.amount(difference, currency, signed: true)
        let amount = spoken ? SpokenAmount.text(written, locale: locale) : written
        return LocalizedStringResource(
            "Difference \(amount) goes in as an adjustment",
            comment: "Reconcile sheet: the typed balance differs from the account's; the difference is recorded as an adjustment."
        ).text(in: locale)
    }

    /// The balance as the field shows it before anything is typed: "15 000,00", always with the
    /// fraction, and its sign.
    var placeholder: String {
        let split = Fmt.split(balanceMinor, currency)
        return split.whole + split.fraction
    }
}
