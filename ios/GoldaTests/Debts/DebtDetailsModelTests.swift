import Foundation
import GoldaCore
import Testing

@testable import Golda

/// A debt's terms on its page, on the numbers of `DebtsTests` (300 000 ₽ at 24,9 % paid 10 000 ₽ a
/// month: 47,4 payments, 174 340,85 ₽ of interest) with today 2026-10-02.
@Suite struct DebtDetailsModelTests {
    static let today = LocalDate(2026, 10, 2)
    static let ru = Locale(identifier: "ru")
    static let en = Locale(identifier: "en")

    let loan = Account(name: "Кредит", currency: "RUB", type: .loan, includeInFree: false, interestRate: 24.9, paymentDay: 5, paymentMinor: 1_000_000)

    private func state(_ account: Account, owed: Int64) -> AccountState {
        AccountState(account: account, balanceMinor: -owed, rubMinor: -owed)
    }

    private func details(_ account: Account, owed: Int64 = 30_000_000) throws -> DebtDetailsModel {
        try #require(DebtDetailsModel(state: state(account, owed: owed), today: Self.today))
    }

    private func values(_ rows: [DebtDetailsModel.Row]) -> [DebtDetailsModel.Row.Kind: String] {
        Dictionary(uniqueKeysWithValues: rows.map { ($0.kind, $0.value ?? $0.title) })
    }

    @Test func aLoanSaysHowLongItHasToGoAndWhatItStillCosts() throws {
        let details = try details(loan)
        #expect(details.owedMinor == 30_000_000)
        #expect(details.nextPayment == LocalDate(2026, 10, 5))
        // 48 payments from October 5: the last one falls in September 2030.
        #expect(details.payoff == .estimate(months: 48, interestMinor: 17_434_085, lastPayment: YearMonth(2030, 9)))
        #expect(details.grace == nil)
        #expect(details.canPrepay)

        let russian = details.rows(in: Self.ru)
        #expect(russian.map(\.kind) == [.rate, .payment, .nextPayment, .monthsLeft, .interestLeft, .lastPayment])
        #expect(russian.map(\.title) == ["Ставка", "Платёж", "Следующий платёж", "Осталось платить", "Переплата", "Последний платёж"])
        #expect(russian.compactMap(\.value) == [
            "24,9 % годовых", "10\u{202F}000 ₽", "5 октября", "≈ 48 месяцев", "≈ 174\u{202F}341 ₽", "Сентябрь 2030",
        ])
        #expect(russian.allSatisfy { !$0.isWarning })

        let english = details.rows(in: Self.en)
        #expect(english.map(\.title) == ["Rate", "Payment", "Next payment", "Left to pay", "Interest left", "Last payment"])
        #expect(english.compactMap(\.value) == [
            "24,9 % a year", "10\u{202F}000 ₽", "October 5", "≈ 48 months", "≈ 174\u{202F}341 ₽", "September 2030",
        ])
    }

    @Test func voiceOverHearsEstimatesAndAmountsInWords() throws {
        let rows = try details(loan).rows(in: Self.en)
        let spoken = Dictionary(uniqueKeysWithValues: rows.map { ($0.kind, $0.spokenValue) })
        #expect(spoken[.monthsLeft] == "about 48 months")
        #expect(try #require(spoken[.interestLeft] ?? nil).hasPrefix("about 174341 "))
        #expect(try #require(spoken[.payment] ?? nil).hasPrefix("10000 "))
        let russian = try details(loan).rows(in: Self.ru)
        #expect(russian.first { $0.kind == .monthsLeft }?.spokenValue == "примерно 48 месяцев")
    }

    @Test func todaysPaymentIsTheNextOne() throws {
        var dueToday = loan
        dueToday.paymentDay = 2
        let details = try details(dueToday)
        #expect(details.nextPayment == Self.today)
        // The first of the 48 payments is today's.
        #expect(details.payoff == .estimate(months: 48, interestMinor: 17_434_085, lastPayment: YearMonth(2030, 9)))
        #expect(values(details.rows(in: Self.en))[.nextPayment] == "Today")
    }

    @Test func withoutAPaymentDayTheTermRunsFromToday() throws {
        var noDay = loan
        noDay.paymentDay = nil
        let details = try details(noDay)
        #expect(details.nextPayment == nil)
        #expect(details.payoff == .estimate(months: 48, interestMinor: 17_434_085, lastPayment: YearMonth(2030, 10)))
        #expect(!details.rows(in: Self.en).map(\.kind).contains(.nextPayment))
    }

    @Test func aFreeLoanCostsNothingMore() throws {
        var free = loan
        free.interestRate = 0
        let details = try details(free)
        // 300 000 ₽ in payments of 10 000 ₽: 30 of them, from October 2026 to March 2029.
        #expect(details.payoff == .estimate(months: 30, interestMinor: 0, lastPayment: YearMonth(2029, 3)))
        let english = values(details.rows(in: Self.en))
        #expect(english[.rate] == "0 % a year")
        #expect(english[.interestLeft] == "≈ 0 ₽")
        #expect(english[.lastPayment] == "March 2029")
    }

    @Test func aPaymentBelowTheInterestIsBadNews() throws {
        var small = loan
        small.paymentMinor = 500_000
        let details = try details(small)
        #expect(details.payoff == .neverEnds)
        #expect(!details.canPrepay)
        let rows = details.rows(in: Self.ru)
        let warning = try #require(rows.last)
        #expect(warning.kind == .notCovering)
        #expect(warning.isWarning)
        #expect(warning.value == nil)
        #expect(warning.title == "Платёж не покрывает даже проценты — долг растёт")
        #expect(details.rows(in: Self.en).last?.title == "The payment does not even cover the interest; the debt grows")
    }

    @Test func aPaidUpLoanOnlyShowsItsTerms() throws {
        let details = try details(loan, owed: 0)
        #expect(details.payoff == nil)
        #expect(!details.canPrepay)
        #expect(details.rows(in: Self.en).map(\.kind) == [.rate, .payment, .nextPayment])
    }

    @Test func aLoanWithoutARateOrPaymentHasNoEstimate() throws {
        var bare = loan
        bare.interestRate = nil
        #expect(try details(bare).payoff == nil)
        bare = loan
        bare.paymentMinor = nil
        let details = try details(bare)
        #expect(details.payoff == nil)
        // Without an amount there is no payment to be due either.
        #expect(details.nextPayment == nil)
        #expect(details.rows(in: Self.en).map(\.kind) == [.rate])
    }

    @Test func aCreditCardShowsItsMinimumAndItsInterestFreePeriod() throws {
        let card = Account(
            name: "Кредитка", currency: "RUB", type: .credit, includeInFree: false, interestRate: 29.9, paymentDay: 25,
            paymentMinor: 300_000, graceUntil: Int64(Self.today.plusDays(40).epochDay)
        )
        let details = try details(card, owed: 1_500_000)
        // A card's minimum changes with what is owed, so it has no payoff estimate, as on Android.
        #expect(details.payoff == nil)
        #expect(!details.canPrepay)
        #expect(details.grace == .until(LocalDate(2026, 11, 11)))
        let russian = details.rows(in: Self.ru)
        #expect(russian.map(\.title) == ["Ставка", "Минимальный платёж", "Следующий платёж", "Льгота до"])
        #expect(russian.compactMap(\.value) == ["29,9 % годовых", "3\u{202F}000 ₽", "25 октября", "11 ноября"])
        #expect(details.rows(in: Self.en).last?.title == "Interest-free until")
        #expect(details.rows(in: Self.en).last?.value == "November 11")
    }

    /// D62: the limit and what is left of it come first; past the limit is bad news.
    @Test func aCreditCardWithALimitSaysWhatIsAvailable() throws {
        let card = Account(
            name: "Кредитка", currency: "RUB", type: .credit, includeInFree: false, interestRate: 29.9, creditLimitMinor: 15_000_000
        )
        let russian = try details(card, owed: 1_500_000).rows(in: Self.ru)
        #expect(russian.map(\.kind) == [.limit, .available, .rate])
        #expect(russian.map(\.title) == ["Кредитный лимит", "Доступно", "Ставка"])
        #expect(russian.compactMap(\.value) == ["150\u{202F}000 ₽", "135\u{202F}000 ₽", "29,9 % годовых"])
        #expect(russian.allSatisfy { !$0.isWarning })
        let english = try details(card, owed: 1_500_000).rows(in: Self.en)
        #expect(english.prefix(2).map(\.title) == ["Credit limit", "Available"])
        #expect(english[1].spokenValue == "135000 Russian rubles")

        // Nothing owed: the whole limit.
        let free = values(try details(card, owed: 0).rows(in: Self.ru))
        #expect(free[.available] == "150\u{202F}000 ₽")

        let overDetails = try details(card, owed: 15_500_000)
        let row = try #require(overDetails.rows(in: Self.ru).first { $0.kind == .available })
        #expect(row.title == "Сверх лимита" && row.value == "5\u{202F}000 ₽" && row.isWarning)
        #expect(overDetails.rows(in: Self.en)[1].title == "Over the limit")
    }

    @Test func aGracePeriodRunningOutWithMoneyOwedIsHomesWarning() throws {
        let card = Account(
            name: "Кредитка", currency: "RUB", type: .credit, includeInFree: false, graceUntil: Int64(Self.today.plusDays(3).epochDay)
        )
        let owing = state(card, owed: 4_800_000)
        let warned = try #require(DebtDetailsModel(state: owing, today: Self.today))
        let warning = try #require(GraceWarning(owing, today: Self.today))
        #expect(warned.grace == .warning(warning))
        let row = try #require(warned.rows(in: Self.ru).last)
        #expect(row.isWarning)
        #expect(row.title == "«Кредитка»: льготный период кончается через 3 дня — погаси 48\u{202F}000 ₽")
        #expect(row.spokenValue == warning.text(in: Self.ru, spoken: true))

        // Nothing owed: no hurry, only the day.
        #expect(try details(card, owed: 0).grace == .until(Self.today.plusDays(3)))
    }

    @Test func aGracePeriodThatEndedIsNotShown() throws {
        let card = Account(
            name: "Кредитка", currency: "RUB", type: .credit, includeInFree: false, graceUntil: Int64(Self.today.minusDays(1).epochDay)
        )
        let details = try details(card, owed: 100_000)
        #expect(details.grace == nil)
        #expect(details.rows(in: Self.en).isEmpty)
    }

    @Test func anAccountThatIsNotADebtHasNoDetails() {
        for type in [AccountType.card, .cash, .savings] {
            let account = Account(name: "Счёт", currency: "RUB", type: type, includeInFree: true, interestRate: 12)
            #expect(DebtDetailsModel(state: state(account, owed: 0), today: Self.today) == nil)
        }
    }

    @Test func theHeaderAndTheButtonSpeakBothLanguages() {
        #expect(DebtDetailsModel.header.text(in: Self.ru) == "Условия")
        #expect(DebtDetailsModel.header.text(in: Self.en) == "Terms")
        #expect(DebtDetailsModel.prepayTitle.text(in: Self.ru) == "Погасить досрочно…")
        #expect(DebtDetailsModel.prepayTitle.text(in: Self.en) == "Pay off early…")
    }
}
