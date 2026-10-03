import Foundation
import GoldaCore
import GoldaData

/// The currency choices of "Где я", the port of Android's `LocalCurrencyChoice`,
/// `BaseCurrencyChoice` and `DisplayCurrencyToggles`. Changes come back as new device settings, so
/// the screen hands them to the model and a test checks them without one.
enum SettingsCurrencies {
    /// "₾ GEL", or the code alone when the currency has no symbol of its own.
    static func label(_ code: String) -> String {
        let symbol = Currencies.symbol(code)
        return symbol == code ? code : "\(symbol) \(code)"
    }

    /// "₽ $ ₾": the shown currencies by their symbols, in their order.
    static func symbols(_ codes: [String]) -> String {
        codes.map(Currencies.symbol).joined(separator: " ")
    }

    /// The local and the main currency are picked out of the shown ones, as on Android. One that is
    /// not among them (an old file can say so) is still listed, so the tick has a row to stand on.
    static func pickOptions(_ device: DeviceSettings, selected: String) -> [String] {
        let shown = device.displayCurrencies.uniqued()
        return shown.contains(selected) ? shown : shown + [selected]
    }

    /// One switch per currency in the fixed order of `Currencies.common`, so nothing jumps when one
    /// is flipped; a shown currency outside that list comes last, so it can still be turned off.
    struct ShownOption: Equatable, Identifiable, Sendable {
        let code: String
        let isOn: Bool
        /// The ruble is always shown: the books are kept in it.
        let isLocked: Bool

        var id: String { code }
    }

    static func shownOptions(_ device: DeviceSettings) -> [ShownOption] {
        let extra = device.displayCurrencies.uniqued().filter { !Currencies.common.contains($0) }
        return (Currencies.common + extra).map { code in
            ShownOption(code: code, isOn: device.displayCurrencies.contains(code), isLocked: code == "RUB")
        }
    }

    /// [device] with [code] shown or hidden by `CurrencyDisplay.toggleDisplayCurrency`: the ruble
    /// stays, and a hidden local or main currency falls back to the ruble.
    static func toggling(_ code: String, in device: DeviceSettings) -> DeviceSettings {
        let before = Settings(
            displayCurrencies: device.displayCurrencies, localCurrency: device.localCurrency, baseCurrency: device.baseCurrency
        )
        let after = CurrencyDisplay.toggleDisplayCurrency(before, code)
        var result = device
        result.displayCurrencies = after.displayCurrencies
        result.localCurrency = after.localCurrency
        result.baseCurrency = after.baseCurrency
        return result
    }
}

/// One line of "Курс": "1 $ = 91,57 ₽" at the profile's display rate, and the official rate.
struct RateRow: Equatable, Identifiable, Sendable {
    let code: String
    /// "1 $ = 91,57 ₽".
    let shown: String
    /// "83,25", the Bank of Russia's rate without the markup.
    let official: String

    var id: String { code }

    /// A row for every shown currency but the ruble that has a rate, in the order they are shown.
    static func rows(_ settings: Settings, _ rates: Rates) -> [RateRow] {
        settings.displayCurrencies.uniqued().compactMap { code in
            guard code != "RUB", let official = rates.official(code), let display = rates.display(code) else { return nil }
            return RateRow(
                code: code,
                shown: "1 \(Currencies.symbol(code)) = \(Fmt.number(display, decimals: 2)) ₽",
                official: Fmt.number(official, decimals: 2)
            )
        }
    }
}

enum RatesDay {
    /// "ЦБ на 2 октября" for the newest rate's day (`yyyy-MM-dd`), as Android's "d MMMM"; nil before
    /// there is a rate, and the text as stored when it is not a day.
    static func text(_ iso: String?, locale: Locale) -> String? {
        guard let iso else { return nil }
        guard let day = LocalDate(iso: iso) else { return SettingsText.ratesOf(iso).text(in: locale) }
        let utc = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        // Noon, so no zone can move it to another day.
        let instant = Date(timeIntervalSince1970: Double(day.epochDay) * 86_400 + 12 * 3_600)
        let written = instant.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: utc).day().month(.wide))
        return SettingsText.ratesOf(written).text(in: locale)
    }
}

/// What came back from a backup, as the message after restoring says it: "Восстановлено: 3 счёта,
/// 14 операций". The profiles are named only when there is more than one, since a phone with a
/// single profile has nothing to count there.
struct RestoreMessage: Equatable, Sendable {
    let profiles: Int
    let accounts: Int
    let operations: Int

    init(profiles: Int, accounts: Int, operations: Int) {
        self.profiles = profiles
        self.accounts = accounts
        self.operations = operations
    }

    init(_ summary: BackupSummary) {
        self.init(profiles: summary.profiles, accounts: summary.accounts, operations: summary.operations)
    }

    func text(in locale: Locale) -> String {
        var parts: [String] = []
        if profiles > 1 { parts.append(SettingsText.profilesCount(profiles).text(in: locale)) }
        parts.append(SettingsText.accountsCount(accounts).text(in: locale))
        parts.append(SettingsText.operationsCount(operations).text(in: locale))
        return SettingsText.restored(parts.joined(separator: ", ")).text(in: locale)
    }
}

enum GeminiModelText {
    /// What a fresh install uses, and what "Вернуть …" puts back.
    static let defaultName = DeviceSettings().geminiModel

    /// The model's name, marked when it is the default one.
    static func row(_ name: String, in locale: Locale) -> String {
        name == defaultName ? SettingsText.defaultModel(name).text(in: locale) : name
    }

    /// The name a model sheet can save: trimmed, and nil when nothing is left.
    static func saveable(_ typed: String) -> String? {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum BackupFile {
    /// "golda-2026-10-03.json", the day it was made, as on Android.
    static func name(on day: LocalDate) -> String {
        "golda-\(day).json"
    }
}

enum AppVersion {
    /// "0.1.0 (1)": the version and, in brackets, the build, from the app's Info.plist.
    static func text(_ info: [String: Any]?) -> String {
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        guard let build = info?["CFBundleVersion"] as? String, !build.isEmpty else { return version }
        return "\(version) (\(build))"
    }
}

enum AppLanguageName {
    /// The interface's language in its own words, capitalized: "Русский", "English".
    static func text(_ locale: Locale) -> String {
        let code = locale.language.languageCode?.identifier ?? "en"
        let own = Locale(identifier: code)
        let name = own.localizedString(forLanguageCode: code) ?? code
        return name.prefix(1).uppercased(with: own) + name.dropFirst()
    }
}

extension Array where Element: Hashable {
    /// The elements in their order, each once.
    fileprivate func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
