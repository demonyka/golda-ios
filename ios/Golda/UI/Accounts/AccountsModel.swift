import Foundation
import GoldaCore

// Everything the Accounts tab shows, worked out from one `AppData` and the day it is, the way
// Android's `AccountsScreen` does it. Plain values: the views only lay them out, and tests check
// them in both languages with a fixed clock.

/// The hero of Accounts: everything there is, in the main currency, and the advice on debts.
struct AccountsHero: Equatable, Sendable {
    /// The main currency the total is in.
    let currency: String
    /// Every account's ruble worth added up, in minor units of [currency].
    let totalMinor: Int64
    /// "145 381 ₽", the big number as written, for VoiceOver.
    let total: String
    /// The other shown currencies: "4 103 ₾ · 1 576 $"; empty when only the main one is shown.
    let others: String
    /// Which debt to pay off first; nil when there is nothing to say.
    let advice: DebtAdvice?

    init(data: AppData) {
        let totalRub = data.states.values.reduce(Int64(0)) { $0 + $1.rubMinor }
        currency = data.base.code
        totalMinor = data.base.minor(totalRub)
        total = data.base.whole(totalRub)
        others = data.others(rubMinor: totalRub, exclude: data.base.code)
        advice = Debts.advice(data.accounts, data.states)
    }

    static let caption = LocalizedStringResource("Total", comment: "Accounts hero caption over the big number: everything on all accounts.")

    /// The advice as a sentence: «Кредитка» стоит 29,9 % — дороже, чем приносит «Накопительный» (12 %)…
    func adviceText(in locale: Locale) -> String? {
        advice.map { Self.sentence($0, in: locale) }
    }

    /// The rates go in with their sign, "29,9 %", one decimal at most, as Android writes them. The
    /// space before the sign does not break: at large text sizes "%" alone started a line.
    static func sentence(_ advice: DebtAdvice, in locale: Locale) -> String {
        func percent(_ rate: Double) -> String { Fmt.number(rate, decimals: 1) + "\u{00A0}%" }
        switch advice {
        case let .payOffInsteadOfSaving(debt, debtRate, savings, savingsRate):
            let costs = percent(debtRate), earns = percent(savingsRate)
            return LocalizedStringResource(
                "“\(debt)” costs \(costs), more than “\(savings)” earns (\(earns)). Spare money does more paying it off.",
                comment: "Accounts hero: the dearest debt costs more than the best savings account earns. Debt name, its rate, savings name, its rate."
            ).text(in: locale)
        case let .savingBeatsPayingOff(savings, savingsRate):
            let earns = percent(savingsRate)
            return LocalizedStringResource(
                "“\(savings)” earns \(earns), more than your debts cost. Paying early does not pay.",
                comment: "Accounts hero: the best savings account earns more than the debts cost. Savings name, its rate."
            ).text(in: locale)
        case let .payHighestRateFirst(debt, rate):
            let costs = percent(rate)
            return LocalizedStringResource(
                "Pay off “\(debt)” first: it has the highest rate, \(costs).",
                comment: "Accounts hero: several debts and no savings; the dearest goes first. Debt name, its rate."
            ).text(in: locale)
        }
    }

    /// The hero as one sentence for VoiceOver, every amount in words.
    func accessibilityLabel(in locale: Locale) -> String {
        var sentences = [Self.caption.text(in: locale), SpokenAmount.text(total, locale: locale)]
        if !others.isEmpty {
            sentences.append(others.components(separatedBy: " · ").map { SpokenAmount.text($0, locale: locale) }.joined(separator: ", "))
        }
        if let advice = adviceText(in: locale) { sentences.append(advice) }
        return sentences.joined(separator: ". ")
    }
}

/// A run of accounts that shares one inset-grouped section.
struct AccountBlock: Equatable, Sendable {
    /// The bank the accounts share; nil for neighbours without one.
    let group: String?
    let accounts: [Account]

    /// Android's `accountBlocks`: the accounts in their order, a bank's accounts pulled together
    /// where the first of them stands, and neighbours without a bank in one list. A group of one is
    /// not a group.
    static func blocks(_ accounts: [Account]) -> [AccountBlock] {
        var members: [String: [Account]] = [:]
        for account in accounts {
            guard let group = account.groupName, !group.allSatisfy(\.isWhitespace) else { continue }
            members[group, default: []].append(account)
        }
        let groups = members.filter { $0.value.count > 1 }
        var seen: Set<String> = []
        var blocks: [(group: String?, accounts: [Account])] = []
        for account in accounts {
            if let group = account.groupName, let together = groups[group] {
                if seen.insert(group).inserted { blocks.append((group, together)) }
            } else if let last = blocks.last, last.group == nil {
                blocks[blocks.count - 1].accounts.append(account)
            } else {
                blocks.append((nil, [account]))
            }
        }
        return blocks.map { AccountBlock(group: $0.group, accounts: $0.accounts) }
    }
}

/// An account's type in the interface language: "Карта", "Credit card".
enum AccountTypeTitle {
    static func resource(_ type: AccountType) -> LocalizedStringResource {
        switch type {
        case .card: LocalizedStringResource("Card", comment: "Account type: a bank card or a current account.")
        case .cash: LocalizedStringResource("Cash", comment: "Account type: cash in hand.")
        case .savings: LocalizedStringResource("Savings", comment: "Account type: a savings account that earns interest.")
        case .credit: LocalizedStringResource("Credit card", comment: "Account type: a credit card; a negative balance is a debt.")
        case .loan: LocalizedStringResource("Loan", comment: "Account type: a loan paid off monthly.")
        }
    }
}

/// "+1 605 ₽ за октябрь": a savings account's interest this month, in its own currency.
struct InterestForecast: Equatable, Sendable {
    /// "1 605 ₽", as `Fmt.approx` writes it.
    let amount: String
    /// Any day of the month the interest is for.
    let month: LocalDate

    /// Nil unless [account] is savings with a rate.
    init?(_ account: Account, operations: [OperationFull], today: LocalDate, zone: TimeZone) {
        guard account.type == .savings, account.interestRate != nil,
              let minor = Budget.interestForecast(account, operations, today: today, zone: zone)
        else { return nil }
        amount = Fmt.approx(Currencies.toMajor(minor, account.currency), account.currency)
        month = today
    }

    /// "+1 605 ₽ за октябрь", "+1 605 ₽ for October". [spoken] says the amount in words.
    func text(in locale: Locale, spoken: Bool = false) -> String {
        let figure = spoken ? SpokenAmount.text(amount, locale: locale) : amount
        let monthName = Self.monthName(month, locale: locale)
        return LocalizedStringResource(
            "+\(figure) for \(monthName)",
            comment: "A savings account's interest forecast this month, “+1 605 ₽ for October”. The amount, then the month's name."
        ).text(in: locale)
    }

    /// The month on its own, as Android's "LLLL": "октябрь" (nominative), "October".
    static func monthName(_ date: LocalDate, locale: Locale) -> String {
        let utc = TimeZone(secondsFromGMT: 0)!
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = locale
        formatter.timeZone = utc
        formatter.dateFormat = "LLLL"
        return formatter.string(from: Date(timeIntervalSince1970: Double(date.epochDay) * 86_400 + 12 * 3_600))
    }
}

/// The line under an account's name: what the account is, and what it is worth in the main
/// currency when it is in another one ("Карта · ≈ 16 001 ₽"). A savings account with a rate says
/// what it earns instead of its type: that says what it is.
struct AccountSubline: Equatable, Sendable {
    enum Lead: Equatable, Sendable {
        case interest(InterestForecast)
        case type(AccountType)
    }

    let lead: Lead
    /// "16 001 ₽", the main currency's worth; nil when the account is in the main currency.
    let approxBase: String?

    init(_ state: AccountState, in data: AppData, today: LocalDate) {
        if let forecast = InterestForecast(state.account, operations: data.operations, today: today, zone: data.zone) {
            lead = .interest(forecast)
        } else {
            lead = .type(state.account.type)
        }
        approxBase = state.currency == data.base.code ? nil : data.base.approx(state.rubMinor)
    }

    func text(in locale: Locale) -> String {
        ([leadText(in: locale, spoken: false)] + (approxBase.map { ["≈ " + $0] } ?? [])).joined(separator: " · ")
    }

    /// The same for VoiceOver: amounts in words, "about" for the approximate one.
    func accessibilityText(in locale: Locale) -> String {
        var parts = [leadText(in: locale, spoken: true)]
        if let approxBase {
            let spoken = SpokenAmount.text(approxBase, locale: locale)
            parts.append(LocalizedStringResource("about \(spoken)", comment: "VoiceOver: an approximate amount, “about 1849 Russian rubles”.").text(in: locale))
        }
        return parts.joined(separator: ", ")
    }

    private func leadText(in locale: Locale, spoken: Bool) -> String {
        switch lead {
        case .interest(let forecast): forecast.text(in: locale, spoken: spoken)
        case .type(let type): AccountTypeTitle.resource(type).text(in: locale)
        }
    }
}

/// One account's row: the name with the budget dot, the subline and the balance.
struct AccountRowModel: Identifiable, Equatable, Sendable {
    let state: AccountState
    let subline: AccountSubline
    /// "78,01 $", in the account's own currency; the view quiets the cents.
    let balance: String

    var id: UUID { state.account.id }
    var account: Account { state.account }
    var name: String { state.account.name }
    /// Counts towards "Можно сегодня": marked with a dot, not painted.
    var isInBudget: Bool { state.account.includeInFree }

    init(_ state: AccountState, in data: AppData, today: LocalDate) {
        self.state = state
        subline = AccountSubline(state, in: data, today: today)
        balance = Fmt.amount(state.balanceMinor, state.currency)
    }

    static let inBudgetLabel = LocalizedStringResource(
        "Counts in “Safe to spend today”",
        comment: "VoiceOver: the dot after an account's name; the account's money counts towards today's budget."
    )

    /// The row as VoiceOver reads it: the name, the dot, the subline, then the balance in words.
    func accessibilityLabel(in locale: Locale) -> String {
        var parts = [name]
        if isInBudget { parts.append(Self.inBudgetLabel.text(in: locale)) }
        parts.append(subline.accessibilityText(in: locale))
        parts.append(SpokenAmount.text(balance, locale: locale))
        return parts.joined(separator: ", ")
    }
}

/// One section of the accounts list: a bank's accounts under its name, or a plain run.
struct AccountSection: Identifiable, Equatable, Sendable {
    /// "Мультивалютная · 15 309 ₽": the bank and what its accounts are worth together, in the main
    /// currency, as Android writes it; nil for a plain run.
    let label: String?
    let rows: [AccountRowModel]

    /// The bank's name, or the first account's id for a plain run: stable while accounts come and go.
    let id: String
}

/// The Accounts tab for the open profile: the hero, then the sections.
struct AccountsContent: Equatable, Sendable {
    let hero: AccountsHero
    let sections: [AccountSection]

    init(data: AppData, today: LocalDate) {
        hero = AccountsHero(data: data)
        sections = AccountBlock.blocks(data.accounts).map { block in
            let states = block.accounts.map { data.states[$0.id] ?? AccountState(account: $0, balanceMinor: 0, rubMinor: 0) }
            let label = block.group.map { group in
                "\(group) · " + data.base.approx(states.reduce(Int64(0)) { $0 + $1.rubMinor })
            }
            return AccountSection(
                label: label,
                rows: states.map { AccountRowModel($0, in: data, today: today) },
                id: block.group.map { "group:" + $0 } ?? "plain:" + (block.accounts.first?.id.uuidString ?? "")
            )
        }
    }

    /// "+ Счёт" closes the last plain list; after a bank's group, or with no accounts at all, it
    /// stands in a section of its own.
    var addRowJoinsLastSection: Bool {
        guard let last = sections.last else { return false }
        return last.label == nil
    }
}

/// The Sunday round of reconcile mode: which accounts have been checked against the bank, and
/// whether each one matched.
struct ReconcileRound: Equatable, Sendable {
    private(set) var checked: [UUID: Bool] = [:]

    /// [accountId] was checked: [matched] when the bank showed the same balance.
    mutating func check(_ accountId: UUID, matched: Bool) {
        checked[accountId] = matched
    }

    func isChecked(_ accountId: UUID) -> Bool { checked[accountId] != nil }

    /// Every one of [accounts] has been checked, as Android's `containsAll`. Nothing to check is
    /// not a finished round: the callback comes only after a check.
    func isComplete(_ accounts: [Account]) -> Bool {
        !accounts.isEmpty && accounts.allSatisfy { isChecked($0.id) }
    }
}
