import Foundation

/// What paying [extraMinor] early does to an annuity loan, both ways banks offer it.
public struct Prepay: Equatable, Sendable {
    public let extraMinor: Int64
    public let monthsNow: Int
    /// Keep the payment, finish sooner.
    public let monthsAfter: Int
    public let savedByTermMinor: Int64
    /// Keep the term, pay less each month.
    public let paymentAfterMinor: Int64
    public let savedByPaymentMinor: Int64
    /// What the same money would earn on a savings account over the remaining term, if one is given.
    public let savingsWouldEarnMinor: Int64?
}

/// Which debt to pay off first and whether it beats keeping the money on a savings account. The
/// screen turns it into a sentence in the app's language.
public enum DebtAdvice: Equatable, Sendable {
    /// The most expensive debt costs more than the best savings account earns.
    case payOffInsteadOfSaving(debt: String, debtRate: Double, savings: String, savingsRate: Double)
    /// The best savings account earns more than the debts cost.
    case savingBeatsPayingOff(savings: String, savingsRate: Double)
    /// Several debts and no savings: the highest rate goes first.
    case payHighestRateFirst(debt: String, rate: Double)
}

public extension Account {
    var isDebt: Bool { type == .credit || type == .loan }
}

/// A credit card's limit against its balance (D62): what can still be spent is the limit less what
/// is owed, and more when the card was paid in over its debt. Below zero the card is over its limit.
public struct CreditLine: Equatable, Sendable {
    public let limitMinor: Int64
    public let availableMinor: Int64

    public init(limitMinor: Int64, availableMinor: Int64) {
        self.limitMinor = limitMinor
        self.availableMinor = availableMinor
    }

    /// Nil unless [account] is a credit card with a limit.
    public init?(_ account: Account, balanceMinor: Int64) {
        guard account.type == .credit, let limit = account.creditLimitMinor, limit > 0 else { return nil }
        let (available, overflow) = limit.addingReportingOverflow(balanceMinor)
        self.init(limitMinor: limit, availableMinor: overflow ? (balanceMinor < 0 ? .min : .max) : available)
    }

    /// What is owed, or zero when nothing is.
    public var owedMinor: Int64 { max(limitMinor - availableMinor, 0) }

    public var isOverLimit: Bool { availableMinor < 0 }
}

public enum Debts {
    /// Months left on an annuity: n = −ln(1 − rB/P) / ln(1 + r). Nil when the payment does not even
    /// cover the interest.
    public static func monthsLeft(_ balanceMinor: Int64, _ ratePercent: Double, _ paymentMinor: Int64) -> Double? {
        if balanceMinor <= 0 { return 0 }
        if paymentMinor <= 0 { return nil }
        let r = ratePercent / 100 / 12
        if r == 0 { return Double(balanceMinor) / Double(paymentMinor) }
        let k = 1 - r * Double(balanceMinor) / Double(paymentMinor)
        if k <= 0 { return nil }
        return -log(k) / log(1 + r)
    }

    /// Interest still to be paid: everything paid minus what is owed.
    public static func interestLeft(_ balanceMinor: Int64, _ ratePercent: Double, _ paymentMinor: Int64) -> Int64? {
        guard let n = monthsLeft(balanceMinor, ratePercent, paymentMinor) else { return nil }
        return max(truncated(Double(paymentMinor) * n - Double(balanceMinor)), 0)
    }

    public static func prepay(
        _ balanceMinor: Int64, _ ratePercent: Double, _ paymentMinor: Int64, extra extraMinor: Int64, savingsPercent: Double?
    ) -> Prepay? {
        guard let n = monthsLeft(balanceMinor, ratePercent, paymentMinor) else { return nil }
        let extra = min(extraMinor, balanceMinor)
        let rest = balanceMinor - extra
        guard let nAfter = monthsLeft(rest, ratePercent, paymentMinor) else { return nil }
        let r = ratePercent / 100 / 12
        let total = Double(paymentMinor) * n - Double(balanceMinor)
        let byTerm = total - (Double(paymentMinor) * nAfter - Double(rest))
        let paymentAfter: Double
        if rest <= 0 {
            paymentAfter = 0
        } else if r == 0 {
            paymentAfter = Double(rest) / n
        } else {
            paymentAfter = Double(rest) * r / (1 - pow(1 + r, -n))
        }
        let byPayment = total - (paymentAfter * n - Double(rest))
        let savings = savingsPercent.map { Double(extra) * (pow(1 + $0 / 100 / 12, n) - 1) }
        return Prepay(
            extraMinor: extra,
            monthsNow: Int(n.rounded(.up)),
            monthsAfter: Int(nAfter.rounded(.up)),
            savedByTermMinor: max(truncated(byTerm), 0),
            paymentAfterMinor: truncated(paymentAfter),
            savedByPaymentMinor: max(truncated(byPayment), 0),
            savingsWouldEarnMinor: savings.map(truncated)
        )
    }

    /// Monthly debt payments set aside before payday like any other obligation. A derived
    /// obligation carries its account's id. Unlike Android (D64), only a debt counted in "Можно
    /// сегодня" sets its payment aside, only while something is owed, and no more than is owed:
    /// a credit card with nothing on it, or a debt kept out of the budget, takes nothing from it.
    public static func obligations(_ accounts: [Account], _ states: [UUID: AccountState]) -> [Obligation] {
        accounts.compactMap { account in
            guard account.isDebt, account.includeInFree, let day = account.paymentDay, let payment = account.paymentMinor, payment > 0,
                  let balance = states[account.id]?.balanceMinor, balance < 0
            else { return nil }
            // −Int64.min does not fit; a debt that big is owed more than any payment anyway.
            let owed = balance == .min ? Int64.max : -balance
            return Obligation(id: account.id, name: account.name, amountMinor: min(payment, owed), currency: account.currency, dayOfMonth: day)
        }
    }

    public static func advice(_ accounts: [Account], _ states: [UUID: AccountState]) -> DebtAdvice? {
        let debts = accounts
            .filter { $0.isDebt && $0.interestRate != nil && (states[$0.id]?.balanceMinor ?? 0) < 0 }
            .stableSorted { $0.interestRate! > $1.interestRate! }
        guard let top = debts.first else { return nil }
        let rate = top.interestRate!
        var savings: Account?
        for candidate in accounts where candidate.type == .savings && candidate.interestRate != nil {
            if savings == nil || candidate.interestRate! > savings!.interestRate! { savings = candidate }
        }
        if let savings {
            let savingsRate = savings.interestRate!
            return rate > savingsRate
                ? .payOffInsteadOfSaving(debt: top.name, debtRate: rate, savings: savings.name, savingsRate: savingsRate)
                : .savingBeatsPayingOff(savings: savings.name, savingsRate: savingsRate)
        }
        return debts.count > 1 ? .payHighestRateFirst(debt: top.name, rate: rate) : nil
    }

    /// Kotlin's `Double.toLong()`: toward zero.
    private static func truncated(_ x: Double) -> Int64 {
        x.isNaN ? 0 : Int64(max(min(x, 9.2e18), -9.2e18))
    }
}
