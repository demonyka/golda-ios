import Foundation
import GoldaCore
import GoldaData

/// The "Доход" group of a profile's screen, the rows of Android's settings: the rate or the salary,
/// tax and hours, payday, and an hour of work after tax with last month's pay beside it. Everything
/// is in rubles, as on Android: the income is earned in rubles whatever the phone shows.
struct ProfileIncome: Equatable, Sendable {
    let isHourly: Bool
    /// "1 000 ₽": the rate an hour or the salary a month, before tax.
    let amount: String
    /// "10", "12,5".
    let taxPercent: String
    /// "40", "37,5".
    let hoursPerWeek: String
    let payday: Int
    /// "900 ₽": one hour of work after tax, what purchases are measured in.
    let hourNet: String
    /// The month before today's.
    let lastMonth: YearMonth
    /// "158 400 ₽": last month's work after tax.
    let lastMonthPay: String

    init(_ settings: ProfileSettings, today: LocalDate) {
        let domain = settings.domain
        isHourly = settings.incomeHourly
        amount = Fmt.approx(settings.incomeHourly ? settings.hourlyRate : settings.monthlySalary, "RUB")
        taxPercent = Fmt.number(settings.taxPercent, decimals: 1)
        hoursPerWeek = Fmt.number(settings.hoursPerWeek, decimals: 1)
        payday = settings.payday
        hourNet = Fmt.approx(domain.hourNet, "RUB")
        lastMonth = YearMonth(from: today).minusMonths(1)
        lastMonthPay = Fmt.approx(domain.salaryFor(lastMonth), "RUB")
    }

    // MARK: Text

    var rateTitle: LocalizedStringResource { Self.rateTitle(hourly: isHourly) }

    static func rateTitle(hourly: Bool) -> LocalizedStringResource {
        hourly
            ? LocalizedStringResource("Rate", table: "Profiles", comment: "Profile screen, income: the hourly rate row.")
            : LocalizedStringResource("Salary", table: "Profiles", comment: "Profile screen, income: the monthly salary row.")
    }

    /// "1 000 ₽/ч", "150 000 ₽/мес".
    func rateText(in locale: Locale) -> String {
        isHourly
            ? LocalizedStringResource("\(amount)/h", table: "Profiles", comment: "Profile screen: an hourly rate, “1 000 ₽/h”.").text(in: locale)
            : LocalizedStringResource("\(amount)/mo", table: "Profiles", comment: "Profile screen: a monthly salary, “150 000 ₽/mo”.").text(in: locale)
    }

    /// "10 % · 40 ч/нед". The percent sign stays out of the catalog, where it would read as a format.
    func taxHoursText(in locale: Locale) -> String {
        taxPercent + " % · " + LocalizedStringResource(
            "\(hoursPerWeek) h/wk", table: "Profiles", comment: "Profile screen: hours of work a week, “40 h/wk”."
        ).text(in: locale)
    }

    func paydayText(in locale: Locale) -> String {
        Self.paydayText(payday, in: locale)
    }

    /// "15-го", "day 15": a day of the month, for payday and payments.
    static func paydayText(_ day: Int, in locale: Locale) -> String {
        LocalizedStringResource("day \(day)", table: "Profiles", comment: "A day of the month: payday or a payment's day, “day 15”.").text(in: locale)
    }

    /// "за сентябрь ≈ 158 400 ₽".
    func lastMonthText(in locale: Locale) -> String {
        let month = Self.monthName(lastMonth, in: locale)
        return LocalizedStringResource(
            "\(month) ≈ \(lastMonthPay)", table: "Profiles",
            comment: "Profile screen, under “An hour after tax”: last month by name and what its work brought, “September ≈ 158 400 ₽”."
        ).text(in: locale)
    }

    /// "сентябрь", "September": the month on its own, as Android's `LLLL` pattern writes it.
    static func monthName(_ month: YearMonth, in locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        return calendar.standaloneMonthSymbols[month.month - 1]
    }

    /// "10 %", "7,3 %": the markup over the CBR rate.
    static func markupText(_ markup: Double) -> String {
        Fmt.number(markup * 100, decimals: 1) + " %"
    }

    static let title = LocalizedStringResource("Income", table: "Profiles", comment: "Profile screen: the header of the income group.")
    static let taxHoursTitle = LocalizedStringResource("Tax and hours", table: "Profiles", comment: "Profile screen, income: the tax and hours a week row.")
    static let paydayTitle = LocalizedStringResource("Payday", table: "Profiles", comment: "Profile screen, income: the day of the month the salary comes.")
    static let hourNetTitle = LocalizedStringResource("An hour after tax", table: "Profiles", comment: "Profile screen, income: what one hour of work brings after tax.")
}

extension ProfileSettings {
    /// The domain's settings with this profile's income, payday and markup, for the sums only the
    /// domain makes (an hour after tax, a month's pay). The currencies are the domain's defaults:
    /// none of those sums reads them.
    var domain: Settings {
        Settings(
            incomeHourly: incomeHourly, hourlyRate: hourlyRate, monthlySalary: monthlySalary, taxPercent: taxPercent,
            hoursPerWeek: hoursPerWeek, payday: payday, markup: markup
        )
    }
}
