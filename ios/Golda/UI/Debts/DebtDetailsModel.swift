import Foundation
import GoldaCore

/// What a debt's page says about its terms, worked out the way Android's `DebtDetails` does: the
/// rate, the payment and when it is next due, and for a loan how long it has to go, the interest
/// still to pay and the month of the last payment; for a credit card, its limit and what is left of
/// it (D62) and its interest-free period.
/// Plain values; `rows(in:)` writes them in the interface language for the view and for VoiceOver.
struct DebtDetailsModel: Equatable, Sendable {
    /// How a loan ends at its current payment.
    enum Payoff: Equatable, Sendable {
        /// [months] payments to go (the estimate rounded up), [interestMinor] of interest in them,
        /// the last one in [lastPayment].
        case estimate(months: Int, interestMinor: Int64, lastPayment: YearMonth)
        /// The payment does not even cover the interest: the debt only grows.
        case neverEnds
    }

    /// The credit card's interest-free period.
    enum Grace: Equatable, Sendable {
        /// It ends within a week and something is owed: Home's warning.
        case warning(GraceWarning)
        /// It runs on until the day; no hurry yet.
        case until(LocalDate)
    }

    let account: Account
    /// What is owed, positive; zero or less when the debt is paid up.
    let owedMinor: Int64
    /// The next time the payment is due, today included; nil without a payment day or amount.
    let nextPayment: LocalDate?
    /// Loans only, while something is owed and the rate and payment are known.
    let payoff: Payoff?
    let grace: Grace?
    /// A credit card's limit against its balance; nil without one.
    let credit: CreditLine?
    let today: LocalDate

    /// Nil for an account that is not a debt.
    init?(state: AccountState, today: LocalDate) {
        let account = state.account
        guard account.isDebt else { return nil }
        self.account = account
        self.today = today
        owedMinor = -state.balanceMinor
        credit = CreditLine(account, balanceMinor: state.balanceMinor)
        if let day = account.paymentDay, account.paymentMinor != nil {
            nextPayment = Budget.nextDue(day, today)
        } else {
            nextPayment = nil
        }

        if account.type == .loan, let rate = account.interestRate, let payment = account.paymentMinor, owedMinor > 0 {
            if let months = Debts.monthsLeft(owedMinor, rate, payment), let interest = Debts.interestLeft(owedMinor, rate, payment) {
                let count = Int(months.rounded(.up))
                // The payments go monthly from the next due one; without a day, a month from today.
                let last = nextPayment.map { $0.plusMonths(count - 1) } ?? today.plusMonths(count)
                payoff = .estimate(months: count, interestMinor: interest, lastPayment: YearMonth(from: last))
            } else {
                payoff = .neverEnds
            }
        } else {
            payoff = nil
        }

        if let warning = GraceWarning(state, today: today) {
            grace = .warning(warning)
        } else if account.type == .credit, let until = account.graceUntil.map({ LocalDate(epochDay: Int($0)) }), !until.isBefore(today) {
            grace = .until(until)
        } else {
            grace = nil
        }
    }

    /// The early-repayment calculator opens for a loan whose end can be worked out, as on Android.
    var canPrepay: Bool {
        if case .estimate = payoff { return true }
        return false
    }

    // MARK: Text

    /// One line of the details: a title with its value, or a sentence of its own.
    struct Row: Identifiable, Equatable, Sendable {
        enum Kind: Hashable, Sendable {
            case limit, available, rate, payment, nextPayment, monthsLeft, interestLeft, lastPayment, notCovering, grace
        }

        let kind: Kind
        let title: String
        /// Nil for a row that is a sentence of its own.
        let value: String?
        /// The value as VoiceOver should say it: amounts in words, "≈" as a word.
        let spokenValue: String?
        /// Bad news, in red.
        let isWarning: Bool

        var id: Kind { kind }
    }

    static let header = LocalizedStringResource("Terms", table: "AccountForm", comment: "Debt details: the header over a debt's rate, payment and term.")

    static let prepayTitle = LocalizedStringResource("Pay off early…", table: "AccountForm", comment: "Debt details: opens the early repayment calculator.")

    /// The rows in the order the page shows them, in the language of [locale].
    func rows(in locale: Locale) -> [Row] {
        let code = account.currency
        var rows: [Row] = []
        if let credit {
            let limit = Fmt.amount(credit.limitMinor, code)
            rows.append(Row(
                kind: .limit, title: AccountFormModel.limitTitle.text(in: locale), value: limit,
                spokenValue: SpokenAmount.text(limit, locale: locale), isWarning: false
            ))
            let title = credit.isOverLimit
                ? LocalizedStringResource("Over the limit", table: "AccountForm", comment: "Debt details: how far a credit card is past its limit.")
                : LocalizedStringResource("Available", table: "AccountForm", comment: "Debt details: what is left to spend on a credit card.")
            let amount = Fmt.amount(credit.isOverLimit ? CreditLineText.over(credit) : credit.availableMinor, code)
            rows.append(Row(
                kind: .available, title: title.text(in: locale), value: amount,
                spokenValue: SpokenAmount.text(amount, locale: locale), isWarning: credit.isOverLimit
            ))
        }
        if let rate = account.interestRate {
            let percent = Fmt.number(rate, decimals: 1) + " %"
            rows.append(Row(
                kind: .rate,
                title: LocalizedStringResource("Rate", table: "AccountForm").text(in: locale),
                value: LocalizedStringResource("\(percent) a year", table: "AccountForm", comment: "Debt details: a yearly interest rate, “24,9 % a year”.").text(in: locale),
                spokenValue: nil, isWarning: false
            ))
        }
        if let payment = account.paymentMinor {
            let amount = Fmt.amount(payment, code)
            let title = account.type == .loan
                ? LocalizedStringResource("Payment", table: "AccountForm")
                : LocalizedStringResource("Minimum payment", table: "AccountForm")
            rows.append(Row(kind: .payment, title: title.text(in: locale), value: amount, spokenValue: SpokenAmount.text(amount, locale: locale), isWarning: false))
        }
        if let nextPayment {
            rows.append(Row(
                kind: .nextPayment,
                title: LocalizedStringResource("Next payment", table: "AccountForm", comment: "Debt details: when the next monthly payment is due.").text(in: locale),
                value: DayLabel(nextPayment, today: today).text(in: locale),
                spokenValue: nil, isWarning: false
            ))
        }
        switch payoff {
        case .estimate(let months, let interestMinor, let lastPayment):
            let monthsText = Self.months(months, in: locale)
            rows.append(Row(
                kind: .monthsLeft,
                title: LocalizedStringResource("Left to pay", table: "AccountForm", comment: "Debt details: how many months of payments are left.").text(in: locale),
                value: "≈ " + monthsText,
                spokenValue: Self.about(monthsText, in: locale), isWarning: false
            ))
            let interest = Fmt.approx(Currencies.toMajor(interestMinor, code), code)
            rows.append(Row(
                kind: .interestLeft,
                title: LocalizedStringResource("Interest left", table: "AccountForm", comment: "Debt details: the interest still to be paid on a loan.").text(in: locale),
                value: "≈ " + interest,
                spokenValue: Self.about(SpokenAmount.text(interest, locale: locale), in: locale), isWarning: false
            ))
            rows.append(Row(
                kind: .lastPayment,
                title: LocalizedStringResource("Last payment", table: "AccountForm", comment: "Debt details: the month the loan's last payment falls in.").text(in: locale),
                value: Self.month(lastPayment, in: locale),
                spokenValue: nil, isWarning: false
            ))
        case .neverEnds:
            rows.append(Row(
                kind: .notCovering,
                title: LocalizedStringResource("The payment does not even cover the interest; the debt grows", table: "AccountForm", comment: "Debt details: the payment is smaller than the monthly interest.").text(in: locale),
                value: nil, spokenValue: nil, isWarning: true
            ))
        case nil:
            break
        }
        switch grace {
        case .warning(let warning):
            rows.append(Row(kind: .grace, title: warning.text(in: locale), value: nil, spokenValue: warning.text(in: locale, spoken: true), isWarning: true))
        case .until(let until):
            rows.append(Row(
                kind: .grace,
                title: LocalizedStringResource("Interest-free until", table: "AccountForm").text(in: locale),
                value: DayLabel.date(until).text(in: locale),
                spokenValue: nil, isWarning: false
            ))
        case nil:
            break
        }
        return rows
    }

    /// "48 months", with the Russian forms of "month".
    static func months(_ count: Int, in locale: Locale) -> String {
        LocalizedStringResource("\(count) months", table: "AccountForm", comment: "A number of months, “48 months”; used inside longer lines.").text(in: locale)
    }

    /// "about 48 months", for VoiceOver, which reads "≈" as a symbol.
    static func about(_ text: String, in locale: Locale) -> String {
        LocalizedStringResource("about \(text)", table: "AccountForm", comment: "VoiceOver: an estimate, “about 48 months”.").text(in: locale)
    }

    /// "September 2030", "Сентябрь 2030": the month on its own, so the nominative in Russian.
    static func month(_ month: YearMonth, in locale: Locale) -> String {
        let utc = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = utc
        formatter.locale = locale
        formatter.dateFormat = "LLLL yyyy"
        let text = formatter.string(from: Date(timeIntervalSince1970: Double(month.atDay(15).epochDay) * 86_400))
        // A value of its own starts with a capital, as a Russian month name on its own does not.
        return text.prefix(1).uppercased(with: locale) + text.dropFirst()
    }
}
