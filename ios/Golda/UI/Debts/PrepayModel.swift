import Foundation
import GoldaCore

/// The early-repayment calculator of a loan, the logic of Android's `PrepayDialog`: an amount paid
/// early, then both ways a bank takes it (finish sooner, or pay less each month), each with the
/// interest it saves, and how that compares with keeping the money on the best savings account.
/// `Debts.prepay` does the sums; this only feeds it and writes the results.
struct PrepayModel: Equatable, Sendable {
    let owedMinor: Int64
    let rate: Double
    let paymentMinor: Int64
    let currency: String
    /// The savings account with the highest rate, the first of equals as on Android; nil when none
    /// has a rate.
    let savings: Account?

    /// Nil unless [state] is a loan with a rate and a payment that still owes something.
    init?(state: AccountState, accounts: [Account]) {
        let account = state.account
        guard account.type == .loan, let rate = account.interestRate, let payment = account.paymentMinor, state.balanceMinor < 0 else {
            return nil
        }
        owedMinor = -state.balanceMinor
        self.rate = rate
        paymentMinor = payment
        currency = account.currency
        var best: Account?
        for candidate in accounts where candidate.type == .savings {
            guard let candidateRate = candidate.interestRate else { continue }
            if best == nil || candidateRate > best!.interestRate! { best = candidate }
        }
        savings = best
    }

    init?(state: AccountState, data: AppData) {
        self.init(state: state, accounts: data.accounts)
    }

    /// What paying [text] early does; nil until the text is an amount above zero, or when the
    /// payment does not cover the interest.
    func result(for text: String) -> Result? {
        guard let extra = Fmt.parseMinor(text, currency), extra > 0,
              let prepay = Debts.prepay(owedMinor, rate, paymentMinor, extra: extra, savingsPercent: savings?.interestRate)
        else { return nil }
        return Result(prepay: prepay, currency: currency, savingsName: savings?.name)
    }

    /// The two options and the comparison, as numbers and as text.
    struct Result: Equatable, Sendable {
        let prepay: Prepay
        let currency: String
        /// The savings account the money is compared with.
        let savingsName: String?

        /// Keeping the payment: how much sooner the loan is paid off.
        var monthsSooner: Int { prepay.monthsNow - prepay.monthsAfter }

        /// Paying off beats saving: the interest saved by finishing sooner is more than the
        /// savings account would earn on the same money over the remaining term.
        var payingOffIsBetter: Bool? {
            prepay.savingsWouldEarnMinor.map { prepay.savedByTermMinor > $0 }
        }

        /// A rounded amount of the loan's currency: "68 230 ₽".
        func money(_ minor: Int64) -> String {
            Fmt.approx(Currencies.toMajor(minor, currency), currency)
        }

        /// "12 months sooner".
        func sooner(in locale: Locale) -> String {
            LocalizedStringResource("\(monthsSooner) months sooner", table: "AccountForm", comment: "Early repayment: how much sooner the loan is paid off, “12 months sooner”.").text(in: locale)
        }

        /// "8 333 ₽ a month".
        func paymentAfter(in locale: Locale) -> String {
            let amount = money(prepay.paymentAfterMinor)
            return LocalizedStringResource("\(amount) a month", table: "AccountForm", comment: "Early repayment: the lower monthly payment, “8 333 ₽ a month”.").text(in: locale)
        }

        /// "On “Накопительный” the same money would earn 30 159 ₽ over that time."; nil without a
        /// savings account to compare with. [spoken] says the amount in words.
        func savingsLine(in locale: Locale, spoken: Bool = false) -> String? {
            guard let savingsName, let earn = prepay.savingsWouldEarnMinor else { return nil }
            let amount = spoken ? SpokenAmount.text(money(earn), locale: locale) : money(earn)
            return LocalizedStringResource(
                "On “\(savingsName)” the same money would earn \(amount) over that time.", table: "AccountForm",
                comment: "Early repayment: what the savings account would pay on the same money. The account's name, then the amount."
            ).text(in: locale)
        }

        /// "Paying off is better by 38 071 ₽." or "Keeping it saved is better by 43 075 ₽.".
        func verdict(in locale: Locale, spoken: Bool = false) -> String? {
            guard let earn = prepay.savingsWouldEarnMinor, let better = payingOffIsBetter else { return nil }
            let difference = money(better ? prepay.savedByTermMinor - earn : earn - prepay.savedByTermMinor)
            let amount = spoken ? SpokenAmount.text(difference, locale: locale) : difference
            return better
                ? LocalizedStringResource("Paying off is better by \(amount).", table: "AccountForm", comment: "Early repayment: paying the loan off early beats saving, by this much.").text(in: locale)
                : LocalizedStringResource("Keeping it saved is better by \(amount).", table: "AccountForm", comment: "Early repayment: keeping the money on savings beats paying off, by this much.").text(in: locale)
        }
    }

    // MARK: Text

    static let title = LocalizedStringResource("Early repayment", table: "AccountForm", comment: "Title of the early repayment calculator.")

    static let amountCaption = LocalizedStringResource("How much to pay", table: "AccountForm", comment: "Early repayment: caption over the amount paid early.")

    static let shortenTitle = LocalizedStringResource("Shorten the term", table: "AccountForm", comment: "Early repayment: the option that keeps the payment and ends the loan sooner.")

    static let lowerTitle = LocalizedStringResource("Lower the payment", table: "AccountForm", comment: "Early repayment: the option that keeps the term and lowers the payment.")

    static let paidOffTitle = LocalizedStringResource("Paid off", table: "AccountForm", comment: "Early repayment: when the loan ends, “12 months sooner”.")

    static let newPaymentTitle = LocalizedStringResource("New payment", table: "AccountForm", comment: "Early repayment: the monthly payment after paying early.")

    static let interestSavedTitle = LocalizedStringResource("Interest saved", table: "AccountForm", comment: "Early repayment: the interest an option saves.")

    static let comparisonTitle = LocalizedStringResource("Or keep it saved", table: "AccountForm", comment: "Early repayment: the header over the comparison with a savings account.")

    static let note = LocalizedStringResource(
        "Annuity estimate; the bank's schedule has the exact figures.", table: "AccountForm",
        comment: "Early repayment: the figures are an estimate."
    )

    static let prompt = LocalizedStringResource(
        "Type an amount to see both options.", table: "AccountForm", comment: "Early repayment: shown until an amount is typed."
    )

    /// "Owed 200 000 ₽ at 19,9 %, 10 000 ₽ a month."
    func owedLine(in locale: Locale) -> String {
        let owed = Fmt.amount(owedMinor, currency)
        let percent = Fmt.number(rate, decimals: 1) + " %"
        let payment = Fmt.amount(paymentMinor, currency)
        return LocalizedStringResource(
            "Owed \(owed) at \(percent), \(payment) a month.", table: "AccountForm",
            comment: "Early repayment: the loan as it stands. What is owed, the yearly rate, the payment."
        ).text(in: locale)
    }
}
