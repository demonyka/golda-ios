import Foundation
import GoldaCore
import Testing

@testable import Golda

/// The early-repayment calculator on the numbers of `DebtsTests`: 300 000 ₽ at 24,9 % paid
/// 10 000 ₽ a month, and 50 000 ₽ paid early, compared with savings at 12 %.
@Suite struct PrepayModelTests {
    static let ru = Locale(identifier: "ru")
    static let en = Locale(identifier: "en")

    let loan = Account(name: "Кредит", currency: "RUB", type: .loan, includeInFree: false, interestRate: 24.9, paymentDay: 5, paymentMinor: 1_000_000)
    let savings = Account(name: "Накопительный", currency: "RUB", type: .savings, includeInFree: false, interestRate: 12.0)

    private var owing: AccountState { AccountState(account: loan, balanceMinor: -30_000_000, rubMinor: -30_000_000) }

    private func calculator(_ accounts: [Account]? = nil) throws -> PrepayModel {
        try #require(PrepayModel(state: owing, accounts: accounts ?? [loan, savings]))
    }

    @Test func bothOptionsWithWhatEachSaves() throws {
        let result = try #require(try calculator().result(for: "50 000"))
        #expect(result.prepay.extraMinor == 5_000_000)
        #expect(result.prepay.monthsNow == 48)
        #expect(result.prepay.monthsAfter == 36)
        #expect(result.monthsSooner == 12)
        // Keeping the payment saves more interest than lowering it.
        #expect(result.prepay.savedByTermMinor == 6_822_983)
        #expect(result.prepay.paymentAfterMinor == 833_333)
        #expect(result.prepay.savedByPaymentMinor == 2_905_680)

        #expect(result.sooner(in: Self.ru) == "на 12 месяцев раньше")
        #expect(result.sooner(in: Self.en) == "12 months sooner")
        #expect(result.money(result.prepay.savedByTermMinor) == "68\u{202F}230 ₽")
        #expect(result.paymentAfter(in: Self.ru) == "8\u{202F}333 ₽ в месяц")
        #expect(result.paymentAfter(in: Self.en) == "8\u{202F}333 ₽ a month")
        #expect(result.money(result.prepay.savedByPaymentMinor) == "29\u{202F}057 ₽")
    }

    @Test func payingOffBeatsSavingsAtTwelvePercent() throws {
        let result = try #require(try calculator().result(for: "50000"))
        // 50 000 ₽ at 12 % for 48 months earns less than the loan's interest saved.
        #expect(result.prepay.savingsWouldEarnMinor == 3_015_865)
        #expect(result.payingOffIsBetter == true)
        #expect(result.savingsLine(in: Self.ru) == "На «Накопительный» эти деньги за то же время принесли бы 30\u{202F}159 ₽.")
        #expect(result.savingsLine(in: Self.en) == "On “Накопительный” the same money would earn 30\u{202F}159 ₽ over that time.")
        #expect(result.verdict(in: Self.ru) == "Гасить выгоднее на 38\u{202F}071 ₽.")
        #expect(result.verdict(in: Self.en) == "Paying off is better by 38\u{202F}071 ₽.")
        #expect(try #require(result.verdict(in: Self.en, spoken: true)).hasPrefix("Paying off is better by 38071 "))
    }

    @Test func aRicherSavingsAccountWinsAndIsTheOneComparedWith() throws {
        let rich = Account(name: "Вклад 30", currency: "RUB", type: .savings, includeInFree: false, interestRate: 30.0)
        let unrated = Account(name: "Копилка", currency: "RUB", type: .savings, includeInFree: false)
        let calculator = try calculator([loan, savings, unrated, rich])
        #expect(calculator.savings == rich)
        let result = try #require(calculator.result(for: "50000"))
        #expect(result.prepay.savingsWouldEarnMinor == 11_130_460)
        #expect(result.payingOffIsBetter == false)
        #expect(result.verdict(in: Self.ru) == "Выгоднее оставить на счёте: +43\u{202F}075 ₽.")
        #expect(result.verdict(in: Self.en) == "Keeping it saved is better by 43\u{202F}075 ₽.")
    }

    @Test func ofTwoEqualSavingsTheFirstIsComparedWith() throws {
        let twin = Account(name: "Второй", currency: "RUB", type: .savings, includeInFree: false, interestRate: 12.0)
        #expect(try calculator([loan, savings, twin]).savings == savings)
    }

    @Test func withoutSavingsThereIsNothingToCompare() throws {
        let result = try #require(try calculator([loan]).result(for: "50000"))
        #expect(result.prepay.savingsWouldEarnMinor == nil)
        #expect(result.payingOffIsBetter == nil)
        #expect(result.savingsLine(in: Self.en) == nil)
        #expect(result.verdict(in: Self.en) == nil)
    }

    @Test func payingMoreThanIsOwedPaysItAllOff() throws {
        let result = try #require(try calculator().result(for: "400 000"))
        #expect(result.prepay.extraMinor == 30_000_000)
        #expect(result.prepay.monthsAfter == 0)
        #expect(result.monthsSooner == 48)
        #expect(result.prepay.savedByTermMinor == 17_434_085)
        #expect(result.paymentAfter(in: Self.en) == "0 ₽ a month")
    }

    @Test func nothingUntilAnAmountAboveZero() throws {
        let calculator = try calculator()
        for text in ["", " ", "0", "0,00", "abc", "-100"] {
            #expect(calculator.result(for: text) == nil, "“\(text)”")
        }
    }

    @Test func onlyALoanThatOwesWithARateAndAPaymentHasACalculator() {
        var credit = loan
        credit.type = .credit
        #expect(PrepayModel(state: AccountState(account: credit, balanceMinor: -100, rubMinor: -100), accounts: []) == nil)
        var noRate = loan
        noRate.interestRate = nil
        #expect(PrepayModel(state: AccountState(account: noRate, balanceMinor: -100, rubMinor: -100), accounts: []) == nil)
        var noPayment = loan
        noPayment.paymentMinor = nil
        #expect(PrepayModel(state: AccountState(account: noPayment, balanceMinor: -100, rubMinor: -100), accounts: []) == nil)
        #expect(PrepayModel(state: AccountState(account: loan, balanceMinor: 0, rubMinor: 0), accounts: []) == nil)
    }

    @Test func theLoanAsItStandsAndTheLabelsSpeakBothLanguages() throws {
        let calculator = try calculator()
        #expect(calculator.owedLine(in: Self.ru) == "Долг 300\u{202F}000 ₽ под 24,9 %, платёж 10\u{202F}000 ₽ в месяц.")
        #expect(calculator.owedLine(in: Self.en) == "Owed 300\u{202F}000 ₽ at 24,9 %, 10\u{202F}000 ₽ a month.")
        #expect(PrepayModel.title.text(in: Self.ru) == "Досрочное погашение")
        #expect(PrepayModel.title.text(in: Self.en) == "Early repayment")
        #expect(PrepayModel.shortenTitle.text(in: Self.ru) == "Сократить срок")
        #expect(PrepayModel.lowerTitle.text(in: Self.ru) == "Уменьшить платёж")
        #expect(PrepayModel.note.text(in: Self.ru) == "Расчёт по аннуитетной схеме; точные цифры — в графике банка.")
    }
}
