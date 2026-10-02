import Foundation

/// What the domain reads from the settings. It is assembled for the active profile: the income,
/// payday and markup come from the profile, the currencies and the last-used account from the
/// device. Everything else the Android `Settings` held (onboarding flag, Gemini model, reminder
/// switch, celebrated goal, reconcile times) is not domain logic and lives with the app.
public struct Settings: Equatable, Sendable {
    /// Paid by the hour (true) or a fixed monthly salary (false).
    public var incomeHourly: Bool
    public var hourlyRate: Double
    public var monthlySalary: Double
    public var taxPercent: Double
    public var hoursPerWeek: Double
    /// Day of month the salary arrives.
    public var payday: Int
    public var displayCurrencies: [String]
    /// Currency of the country you are in; voice input falls back to it.
    public var localCurrency: String
    /// The currency the big numbers and totals are shown in; the ledger itself stays in rubles.
    public var baseCurrency: String
    /// How much more than the CBR rate rubles cost you abroad.
    public var markup: Double
    public var lastAccountId: UUID?

    public init(
        incomeHourly: Bool = true, hourlyRate: Double = 0, monthlySalary: Double = 0, taxPercent: Double = 0,
        hoursPerWeek: Double = 40, payday: Int = 15, displayCurrencies: [String] = ["RUB", "USD"],
        localCurrency: String = "RUB", baseCurrency: String = "RUB", markup: Double = 0.10, lastAccountId: UUID? = nil
    ) {
        self.incomeHourly = incomeHourly
        self.hourlyRate = hourlyRate
        self.monthlySalary = monthlySalary
        self.taxPercent = taxPercent
        self.hoursPerWeek = hoursPerWeek
        self.payday = payday
        self.displayCurrencies = displayCurrencies
        self.localCurrency = localCurrency
        self.baseCurrency = baseCurrency
        self.markup = markup
        self.lastAccountId = lastAccountId
    }

    /// One hour of work after tax, in rubles.
    public var hourNet: Double {
        if incomeHourly {
            return hourlyRate * (1 - taxPercent / 100)
        }
        let hoursPerMonth = hoursPerWeek * 52 / 12
        return hoursPerMonth > 0 ? monthlySalary * (1 - taxPercent / 100) / hoursPerMonth : 0
    }

    /// Expected salary after tax for the work done in [month].
    public func salaryFor(_ month: YearMonth) -> Double {
        if incomeHourly {
            let workdays = (1...month.lengthOfMonth).filter { !month.atDay($0).dayOfWeek.isWeekend }.count
            return Double(workdays) * hoursPerWeek / 5 * hourlyRate * (1 - taxPercent / 100)
        }
        return monthlySalary * (1 - taxPercent / 100)
    }

    public func nextPayday(_ today: LocalDate) -> LocalDate {
        func inMonth(_ month: YearMonth) -> LocalDate { month.atDay(min(max(payday, 1), month.lengthOfMonth)) }
        let thisMonth = inMonth(YearMonth(from: today))
        return thisMonth.isAfter(today) ? thisMonth : inMonth(YearMonth(from: today).plusMonths(1))
    }
}
