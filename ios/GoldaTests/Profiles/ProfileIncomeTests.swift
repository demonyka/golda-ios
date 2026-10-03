import Foundation
import GoldaCore
import GoldaData
import Testing

@testable import Golda

/// The "Доход" and "Наценка" rows of a profile's screen, as Android's settings write them: the rate
/// or salary, tax and hours, payday, an hour after tax and last month's pay, all in rubles.
@Suite struct ProfileIncomeTests {
    static let ru = Locale(identifier: "ru")
    static let en = Locale(identifier: "en")
    static let today = LocalDate(2026, 10, 2)
    /// The made-up person of the samples: 1 000 ₽ an hour, 10 % tax, 40 hours, paid on the 10th.
    static let hourly = ProfileSettings(
        incomeHourly: true, hourlyRate: 1000, monthlySalary: 0, taxPercent: 10, hoursPerWeek: 40, payday: 10, markup: 0.1
    )
    static let monthly = ProfileSettings(
        incomeHourly: false, hourlyRate: 1000, monthlySalary: 150_000, taxPercent: 13, hoursPerWeek: 40, payday: 5, markup: 0.1
    )

    private let ru = ProfileIncomeTests.ru
    private let en = ProfileIncomeTests.en

    @Test func anHourlyRateReadsAsAndroidWritesIt() {
        let income = ProfileIncome(Self.hourly, today: Self.today)
        #expect(income.isHourly)
        #expect(income.rateTitle.text(in: ru) == "Ставка")
        #expect(income.rateTitle.text(in: en) == "Rate")
        #expect(income.rateText(in: ru) == "1\u{202F}000 ₽/ч")
        #expect(income.rateText(in: en) == "1\u{202F}000 ₽/h")
        #expect(income.taxHoursText(in: ru) == "10 % · 40 ч/нед")
        #expect(income.taxHoursText(in: en) == "10 % · 40 h/wk")
        #expect(income.paydayText(in: ru) == "10-го")
        #expect(income.paydayText(in: en) == "day 10")
    }

    @Test func anHourAfterTaxAndLastMonthsPay() {
        let income = ProfileIncome(Self.hourly, today: Self.today)
        // 1 000 ₽ less 10 %.
        #expect(income.hourNet == "900 ₽")
        // September 2026 has 22 weekdays: 22 × 8 h × 900 ₽.
        #expect(income.lastMonth == YearMonth(2026, 9))
        #expect(income.lastMonthPay == "158\u{202F}400 ₽")
        #expect(income.lastMonthText(in: ru) == "за сентябрь ≈ 158\u{202F}400 ₽")
        #expect(income.lastMonthText(in: en) == "September ≈ 158\u{202F}400 ₽")
    }

    @Test func aMonthlySalaryCountsItsHoursOverAMonth() {
        let income = ProfileIncome(Self.monthly, today: Self.today)
        #expect(!income.isHourly)
        #expect(income.rateTitle.text(in: ru) == "Зарплата")
        #expect(income.rateTitle.text(in: en) == "Salary")
        #expect(income.rateText(in: ru) == "150\u{202F}000 ₽/мес")
        #expect(income.rateText(in: en) == "150\u{202F}000 ₽/mo")
        // 130 500 ₽ after tax over 40 × 52 / 12 hours.
        #expect(income.hourNet == "753 ₽")
        #expect(income.lastMonthPay == "130\u{202F}500 ₽")
        #expect(income.taxHoursText(in: ru) == "13 % · 40 ч/нед")
    }

    @Test func fractionsKeepOneDecimalWithAComma() {
        var settings = Self.hourly
        settings.taxPercent = 12.5
        settings.hoursPerWeek = 37.5
        settings.hourlyRate = 85.5
        let income = ProfileIncome(settings, today: Self.today)
        #expect(income.taxHoursText(in: ru) == "12,5 % · 37,5 ч/нед")
        #expect(income.rateText(in: en) == "85,5 ₽/h")
        // Under a hundred the approximate amount keeps a decimal: 85,5 × 0,875 = 74,8.
        #expect(income.hourNet == "74,8 ₽")
    }

    @Test func noIncomeYetIsZero() {
        let income = ProfileIncome(ProfileSettings(), today: Self.today)
        #expect(income.hourNet == "0 ₽")
        #expect(income.lastMonthPay == "0 ₽")
        #expect(income.rateText(in: en) == "0 ₽/h")
        // The domain's default payday.
        #expect(income.paydayText(in: ru) == "15-го")
    }

    @Test func januaryLooksBackToDecemberOfTheYearBefore() {
        let income = ProfileIncome(Self.hourly, today: LocalDate(2027, 1, 15))
        #expect(income.lastMonth == YearMonth(2026, 12))
        #expect(income.lastMonthText(in: ru).hasPrefix("за декабрь ≈ "))
        #expect(income.lastMonthText(in: en).hasPrefix("December ≈ "))
    }

    @Test func paydaysAtBothEndsOfTheMonth() {
        #expect(ProfileIncome.paydayText(1, in: ru) == "1-го")
        #expect(ProfileIncome.paydayText(31, in: ru) == "31-го")
        #expect(ProfileIncome.paydayText(31, in: en) == "day 31")
    }

    @Test func theMarkupIsAPercentWithOneDecimal() {
        #expect(ProfileIncome.markupText(0.1) == "10 %")
        #expect(ProfileIncome.markupText(0.125) == "12,5 %")
        // A markup learned from an exchange is rarely round.
        #expect(ProfileIncome.markupText(0.0734) == "7,3 %")
        #expect(ProfileIncome.markupText(0) == "0 %")
    }
}
