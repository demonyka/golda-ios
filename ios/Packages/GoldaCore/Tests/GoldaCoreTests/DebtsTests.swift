import Foundation
import Testing

@testable import GoldaCore

/// Port of DebtsTest.kt. The advice is checked by its case, where Kotlin looked for "дороже" in the text.
@Suite struct DebtsTests {
    // 300 000 ₽ at 24.9 % paid 10 000 ₽ a month.
    let balance: Int64 = 30_000_000
    let rate = 24.9
    let payment: Int64 = 1_000_000

    @Test func monthsLeftOnAnAnnuity() {
        expectClose(Debts.monthsLeft(balance, rate, payment)!, 47.4, 0.1)
        #expect(Debts.monthsLeft(balance, rate, 500_000) == nil) // 5 000 ₽ does not even cover the interest
        expectClose(Debts.monthsLeft(balance, 0, payment)!, 30, 1e-9)
    }

    @Test func prepayingShortensTheTermOrLowersThePayment() {
        let p = Debts.prepay(balance, rate, payment, extra: 5_000_000, savingsPercent: 12.0)!
        #expect(p.monthsNow == 48)
        #expect(p.monthsAfter == 36)
        // Keeping the payment saves more interest than lowering it.
        #expect(p.savedByTermMinor > p.savedByPaymentMinor)
        #expect(p.savedByPaymentMinor > 0)
        #expect((800_000...850_000).contains(p.paymentAfterMinor))
        // 50 000 ₽ at 12 % for 48 months earns less than the loan's interest saved.
        #expect(p.savingsWouldEarnMinor! < p.savedByTermMinor)
    }

    @Test func interestLeftIsWhatIsPaidOnTopOfTheDebt() {
        let interest = Debts.interestLeft(balance, rate, payment)!
        expectClose(Double(interest), 1_000_000 * Debts.monthsLeft(balance, rate, payment)! - Double(balance), 1.0)
    }

    @Test func debtPaymentsBecomeObligations() {
        let loan = Account(id: uid(1), name: "Кредит", currency: "RUB", type: .loan, includeInFree: false, interestRate: 24.9, paymentDay: 10, paymentMinor: 750_000)
        let card = Account(id: uid(2), name: "Карта", currency: "RUB", type: .card, includeInFree: true, paymentDay: 5, paymentMinor: 1)
        let obligations = Debts.obligations([loan, card])
        #expect(obligations.count == 1)
        #expect(obligations[0].amountMinor == 750_000)
        #expect(obligations[0].dayOfMonth == 10)
    }

    @Test func adviceComparesWithSavings() {
        let loan = Account(id: uid(1), name: "Кредит", currency: "RUB", type: .loan, includeInFree: false, interestRate: 24.9)
        let savings = Account(id: uid(2), name: "Накопительный", currency: "RUB", type: .savings, includeInFree: false, interestRate: 12.0)
        let owing = Ledger.states([loan, savings], [Posting(accountId: loan.id, amountMinor: -balance, rubMinor: -balance)])
        #expect(Debts.advice([loan, savings], owing) == .payOffInsteadOfSaving(debt: "Кредит", debtRate: 24.9, savings: "Накопительный", savingsRate: 12.0))
        // Nothing owed, nothing to advise.
        #expect(Debts.advice([loan, savings], Ledger.states([loan, savings], [])) == nil)
    }
}
