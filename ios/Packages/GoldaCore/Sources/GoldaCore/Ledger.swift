import Foundation

/// Official rates plus the personal markup. "Display" rates are what money in that currency really
/// costs you, and every multi-currency line uses them.
public struct Rates: Sendable {
    private let rubPerUnit: [String: Double]
    public let markup: Double

    /// Visa/Mastercard conversion plus the bank's cut, until we learn better.
    public static let cardMarkup = 0.02

    public init(_ rubPerUnit: [String: Double], markup: Double) {
        self.rubPerUnit = rubPerUnit
        self.markup = markup
    }

    public func official(_ code: String) -> Double? { code == "RUB" ? 1.0 : rubPerUnit[code] }

    public func display(_ code: String) -> Double? {
        code == "RUB" ? 1.0 : official(code).map { $0 * (1 + markup) }
    }

    /// Kopecks that [minor] of [code] are worth at the display rate.
    public func rubMinor(_ minor: Int64, _ code: String) -> Int64? {
        display(code).map { Money.roundHalfUp(Currencies.toMajor(minor, code) * $0 * 100) }
    }

    /// [rubMinor] kopecks expressed in [code], major units.
    public func fromRub(_ rubMinor: Int64, _ code: String) -> Double? {
        display(code).map { Double(rubMinor) / 100.0 / $0 }
    }

    /// Same money in another currency at display rates (cross rates keep the markup out).
    public func convert(_ minor: Int64, from: String, to: String) -> Int64? {
        guard let a = display(from), let b = display(to) else { return nil }
        return Currencies.toMinor(Currencies.toMajor(minor, from) * a / b, to)
    }

    /// What a card in [account] currency is charged for a purchase in [purchase] currency.
    public func cardCharge(_ minor: Int64, purchase: String, account: String, cardMarkup: Double = Rates.cardMarkup) -> Int64? {
        guard let a = official(purchase), let b = official(account) else { return nil }
        return Currencies.toMinor(Currencies.toMajor(minor, purchase) * a / b * (1 + cardMarkup), account)
    }
}

public struct AccountState: Equatable, Sendable {
    public let account: Account
    public let balanceMinor: Int64
    public let rubMinor: Int64

    public init(account: Account, balanceMinor: Int64, rubMinor: Int64) {
        self.account = account
        self.balanceMinor = balanceMinor
        self.rubMinor = rubMinor
    }

    public var currency: String { account.currency }

    /// Rubles one unit on this account cost on average; nil when there is nothing to average.
    public var costBasis: Double? {
        if currency == "RUB" { return 1.0 }
        if balanceMinor > 0 { return Double(rubMinor) / 100.0 / Currencies.toMajor(balanceMinor, currency) }
        return nil
    }
}

/// Everything a new operation needs; [amountMinor] is in the (from) account's currency.
public struct Draft: Equatable, Sendable {
    public var type: OpType
    public var timestamp: Int64
    public var accountId: UUID
    /// Positive for expense, income and transfer; signed for adjustment and opening.
    public var amountMinor: Int64
    public var toAccountId: UUID?
    public var toAmountMinor: Int64?
    public var categoryKey: String?
    public var note: String
    public var purchaseAmountMinor: Int64?
    public var purchaseCurrency: String?
    public var isEstimate: Bool
    public var voiceText: String?
    /// The operation being replaced; nil for a new one.
    public var id: UUID?

    public init(
        type: OpType, timestamp: Int64, accountId: UUID, amountMinor: Int64, toAccountId: UUID? = nil,
        toAmountMinor: Int64? = nil, categoryKey: String? = nil, note: String = "", purchaseAmountMinor: Int64? = nil,
        purchaseCurrency: String? = nil, isEstimate: Bool = false, voiceText: String? = nil, id: UUID? = nil
    ) {
        self.type = type
        self.timestamp = timestamp
        self.accountId = accountId
        self.amountMinor = amountMinor
        self.toAccountId = toAccountId
        self.toAmountMinor = toAmountMinor
        self.categoryKey = categoryKey
        self.note = note
        self.purchaseAmountMinor = purchaseAmountMinor
        self.purchaseCurrency = purchaseCurrency
        self.isEstimate = isEstimate
        self.voiceText = voiceText
        self.id = id
    }
}

public enum LedgerError: Error, Equatable, Sendable {
    /// A draft names an account that is not in the states (Kotlin throws NoSuchElementException).
    case unknownAccount(UUID)
    /// A transfer without a destination account.
    case missingDestination
}

public enum Ledger {
    public static func states(_ accounts: [Account], _ postings: [Posting]) -> [UUID: AccountState] {
        let byAccount = Dictionary(grouping: postings, by: \.accountId)
        var result: [UUID: AccountState] = [:]
        for account in accounts {
            let own = byAccount[account.id] ?? []
            result[account.id] = AccountState(
                account: account,
                // Held at ±Int64.max: a stored row too big to add up shows a wrong figure, not a crash (D59).
                balanceMinor: own.moneySum(\.amountMinor),
                rubMinor: own.moneySum(\.rubMinor)
            )
        }
        return result
    }

    /// Ruble value of money leaving [state]: at its average cost while it lasts, then at the display rate.
    public static func outflowRub(_ state: AccountState, _ minor: Int64, _ rates: Rates) -> Int64 {
        if state.currency == "RUB" { return minor }
        let balance = state.balanceMinor
        let covered = balance > 0 ? min(minor, balance) : 0
        let fromBasis = covered > 0 ? Money.roundHalfUp(Double(state.rubMinor) * Double(covered) / Double(balance)) : 0
        let rest = minor - covered
        return Money.add(fromBasis, rest > 0 ? rates.rubMinor(rest, state.currency) ?? 0 : 0)
    }

    public static func inflowRub(_ account: Account, _ minor: Int64, _ rates: Rates) -> Int64 {
        account.currency == "RUB" ? minor : rates.rubMinor(minor, account.currency) ?? 0
    }

    /// Turns a draft into postings, valuing each side in rubles against the current balances.
    public static func postings(_ draft: Draft, _ states: [UUID: AccountState], _ rates: Rates) throws -> [Posting] {
        guard let from = states[draft.accountId] else { throw LedgerError.unknownAccount(draft.accountId) }
        let amount = draft.amountMinor
        switch draft.type {
        case .expense:
            return [Posting(accountId: from.account.id, amountMinor: -amount, rubMinor: -outflowRub(from, amount, rates))]
        case .income:
            return [Posting(accountId: from.account.id, amountMinor: amount, rubMinor: inflowRub(from.account, amount, rates))]
        case .adjustment, .opening:
            let rub = amount >= 0 ? inflowRub(from.account, amount, rates) : -outflowRub(from, -amount, rates)
            return [Posting(accountId: from.account.id, amountMinor: amount, rubMinor: rub)]
        case .transfer:
            guard let toId = draft.toAccountId else { throw LedgerError.missingDestination }
            guard let to = states[toId] else { throw LedgerError.unknownAccount(toId) }
            let received = draft.toAmountMinor ?? amount
            let paid = outflowRub(from, amount, rates)
            // Rubles that arrive are worth exactly what they are; anything else carries the cost of what was paid.
            let carried = to.currency == "RUB" ? received : paid
            return [
                Posting(accountId: from.account.id, amountMinor: -amount, rubMinor: -paid),
                Posting(accountId: to.account.id, amountMinor: received, rubMinor: carried),
            ]
        }
    }

    /// The markup a ruble-to-currency transfer reveals: 46 000 ₽ for 500 $ at a CBR rate of 83.25
    /// means +10.5 %. Nil when the transfer says nothing about it.
    public static func learnedMarkup(_ draft: Draft, _ states: [UUID: AccountState], _ rates: Rates) -> Double? {
        guard draft.type == .transfer, !draft.isEstimate,
              let from = states[draft.accountId],
              let toId = draft.toAccountId, let to = states[toId],
              from.currency == "RUB", to.currency != "RUB",
              let received = draft.toAmountMinor, received > 0,
              let official = rates.official(to.currency)
        else { return nil }
        let paid = Double(draft.amountMinor) / 100.0 / Currencies.toMajor(received, to.currency)
        let markup = paid / official - 1
        return (-0.2...0.6).contains(markup) ? markup : nil
    }

    public static func localDate(_ timestamp: Int64, _ zone: TimeZone) -> LocalDate {
        LocalDate(epochMillis: timestamp, in: zone)
    }
}

public struct Today: Equatable, Sendable {
    public let freeRub: Int64
    /// Monthly payments due before payday, already set aside.
    public let obligationsRub: Int64
    public let spentTodayRub: Int64
    public let daysLeft: Int
    public let perDayRub: Int64
    public let leftTodayRub: Int64
    public let nextPayday: LocalDate
}

public enum Budget {
    /// "Можно сегодня": free money at the start of the day split evenly over the days left until
    /// payday, minus what is already spent today.
    public static func today(
        states: [UUID: AccountState],
        operations: [OperationFull],
        settings: Settings,
        today: LocalDate,
        zone: TimeZone,
        obligations: [Obligation] = [],
        rates: Rates? = nil
    ) -> Today {
        let free = states.values.filter(\.account.includeInFree)
        let freeIds = Set(free.map(\.account.id))
        let freeRub = free.moneySum(\.rubMinor)
        let spentToday = operations
            .filter { $0.op.type == .expense && Ledger.localDate($0.op.timestamp, zone) == today }
            .flatMap(\.postings)
            .filter { freeIds.contains($0.accountId) }
            .reduce(0) { Money.subtract($0, $1.rubMinor) }
        let payday = settings.nextPayday(today)
        let days = max(LocalDate.daysBetween(today, payday), 1)
        let due = dueRub(obligations, before: payday, from: today, rates: rates)
        let perDay = Money.subtract(Money.add(freeRub, spentToday), due) / Int64(days)
        return Today(
            freeRub: freeRub, obligationsRub: due, spentTodayRub: spentToday, daysLeft: days,
            perDayRub: perDay, leftTodayRub: Money.subtract(perDay, spentToday), nextPayday: payday
        )
    }

    /// Whether the pay period is going to plan: today's per-day budget minus the one the period
    /// started with. That baseline is the free money as of the end of the last payday (so the salary
    /// booked that day counts), less the payments due before the next payday, spread over the whole
    /// period. Positive means spending slower than the period allows.
    ///
    /// Nil when there is nothing to compare with: payday is today, or no free money had been
    /// recorded before the last payday (a new user).
    public static func pace(
        today: Today,
        accounts: [Account],
        operations: [OperationFull],
        settings: Settings,
        date: LocalDate,
        zone: TimeZone,
        obligations: [Obligation] = [],
        rates: Rates? = nil
    ) -> Int64? {
        let next = settings.nextPayday(date)
        let last = settings.nextPayday(next.minusMonths(1).minusDays(1))
        if last == date { return nil }
        let freeIds = Set(accounts.filter(\.includeInFree).map(\.id))
        let start = last.startOfDayMillis(in: zone)
        let end = last.plusDays(1).startOfDayMillis(in: zone)
        let free = operations.flatMap { full in
            full.postings.filter { freeIds.contains($0.accountId) }.map { (time: full.op.timestamp, posting: $0) }
        }
        if !free.contains(where: { $0.time < start }) { return nil }
        let freeThen = free.filter { $0.time < end }.moneySum(\.posting.rubMinor)
        let due = dueRub(obligations, before: next, from: last, rates: rates)
        let days = max(LocalDate.daysBetween(last, next), 1)
        return Money.subtract(today.perDayRub, Money.subtract(freeThen, due) / Int64(days))
    }

    private static func dueRub(_ obligations: [Obligation], before limit: LocalDate, from date: LocalDate, rates: Rates?) -> Int64 {
        obligations
            .filter { nextDue($0.dayOfMonth, date).isBefore(limit) }
            .moneySum { o in
                (o.currency == "RUB" ? o.amountMinor : rates?.rubMinor(o.amountMinor, o.currency) ?? 0)
            }
    }

    /// The next time a monthly payment on [day] comes, today included.
    public static func nextDue(_ day: Int, _ today: LocalDate) -> LocalDate {
        func inMonth(_ month: YearMonth) -> LocalDate { month.atDay(min(max(day, 1), month.lengthOfMonth)) }
        let thisMonth = inMonth(YearMonth(from: today))
        return thisMonth.isBefore(today) ? inMonth(YearMonth(from: today).plusMonths(1)) : thisMonth
    }

    /// This month's interest on a savings account that pays on the monthly minimum. Opening
    /// balances count as if they were there since the 1st.
    public static func interestForecast(_ account: Account, _ operations: [OperationFull], today: LocalDate, zone: TimeZone) -> Int64? {
        guard let rate = account.interestRate else { return nil }
        let monthStart = today.withDayOfMonth(1)
        let moves = operations
            .flatMap { full in full.postings.filter { $0.accountId == account.id }.map { (op: full.op, posting: $0) } }
            .stableSorted { $0.op.timestamp < $1.op.timestamp }
        var balance: Int64 = 0
        var minimum: Int64?
        for (op, posting) in moves {
            let before = op.type == .opening || Ledger.localDate(op.timestamp, zone) < monthStart
            let previous = balance
            balance = Money.add(balance, posting.amountMinor)
            if !before { minimum = min(minimum ?? previous, balance) }
        }
        let base = max(min(minimum ?? balance, balance), 0)
        return Money.roundHalfUp(Double(base) * rate / 100 * Double(today.lengthOfMonth) / 365)
    }
}
