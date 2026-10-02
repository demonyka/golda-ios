import Foundation
import GoldaCore

public extension GoldaCore.Settings {
    /// What the domain reads while [profileId] is open: income, payday and markup from the profile,
    /// so its members all count the same "можно сегодня"; currencies from this phone; and the
    /// account this phone used last in that profile (D16, D21).
    init(profile: ProfileSettings, device: DeviceSettings, profileId: UUID) {
        self.init(
            incomeHourly: profile.incomeHourly,
            hourlyRate: profile.hourlyRate,
            monthlySalary: profile.monthlySalary,
            taxPercent: profile.taxPercent,
            hoursPerWeek: profile.hoursPerWeek,
            payday: profile.payday,
            displayCurrencies: device.displayCurrencies,
            localCurrency: device.localCurrency,
            baseCurrency: device.baseCurrency,
            markup: profile.markup,
            lastAccountId: device.lastAccountId[profileId]
        )
    }
}
