import Foundation

/// The main currency the big figures and totals are shown in ("Основная валюта").
///
/// Only presentation: the ledger, the budget and the analytics keep counting in rubles (each
/// posting's ruble cost basis), and an aggregate is converted here, at today's display rate
/// (CBR × (1 + markup)), just before it is shown. With rubles every method gives exactly what the
/// ruble formatting gave before. A currency without a rate falls back to rubles.
public struct Base: Sendable {
    private let rates: Rates

    /// The currency actually used: the wanted one, or rubles when there is no rate for it.
    public let code: String

    public init(_ rates: Rates, _ wanted: String) {
        self.rates = rates
        self.code = (wanted == "RUB" || rates.display(wanted) != nil) ? wanted : "RUB"
    }

    /// The main currency of [settings].
    public static func of(_ settings: Settings, _ rates: Rates) -> Base { Base(rates, settings.baseCurrency) }

    public var symbol: String { Currencies.symbol(code) }

    public var isRub: Bool { code == "RUB" }

    /// [rubMinor] kopecks in the main currency, major units.
    public func major(_ rubMinor: Int64) -> Double {
        isRub ? Double(rubMinor) / 100.0 : rates.fromRub(rubMinor, code)!
    }

    /// [rubMinor] kopecks in the main currency's minor units.
    public func minor(_ rubMinor: Int64) -> Int64 { isRub ? rubMinor : Currencies.toMinor(major(rubMinor), code) }

    /// An approximate amount, "510 ₽" or "5,5 $", as `Fmt.approx` writes converted values.
    public func approx(_ rubMinor: Int64) -> String { Fmt.approx(major(rubMinor), code) }

    /// Whole units for a big number: "1 849 ₽", "20 $".
    public func whole(_ rubMinor: Int64) -> String { Fmt.split(minor(rubMinor), code).whole + " " + symbol }
}

/// The currency lists and the "others" line. They sit in the domain because what they return
/// depends only on the settings and the rates, and the settings-effects tests pin them down.
public enum CurrencyDisplay {
    /// "≈ 45,8 $ · 124 ₾ · 1 498 ฿": [rubMinor] in every display currency but [exclude]. The currency
    /// of where you are comes first: that is the one you pay in today.
    public static func others(rubMinor: Int64, exclude: String, settings: Settings, rates: Rates) -> String {
        ([settings.localCurrency] + settings.displayCurrencies).distinct()
            .filter { $0 != exclude }
            .compactMap { code -> String? in
                let value = code == "RUB" ? Double(rubMinor) / 100.0 : rates.fromRub(rubMinor, code)
                return value.map { Fmt.approx($0, code) }
            }
            .joined(separator: " · ")
    }

    /// Currencies to pick from, in one order everywhere: the local one, then the display currencies
    /// as set, then [extra] (say, an account's own currency). Picking a chip never moves it.
    public static func currencyChoices(settings: Settings, extra: [String] = []) -> [String] {
        ([settings.localCurrency] + settings.displayCurrencies + extra).distinct()
    }

    /// Toggling a currency in the shown ones; the ruble always stays, and the local and main
    /// currencies fall back to rubles when hidden. The list keeps the catalogue's order, so where a
    /// currency stands does not depend on when it was turned on.
    public static func toggleDisplayCurrency(_ settings: Settings, _ code: String) -> Settings {
        if code == "RUB" { return settings }
        let list = settings.displayCurrencies.contains(code)
            ? settings.displayCurrencies.filter { $0 != code }
            : settings.displayCurrencies + [code]
        var result = settings
        result.displayCurrencies = Currencies.ordered(list)
        result.localCurrency = list.contains(settings.localCurrency) ? settings.localCurrency : "RUB"
        result.baseCurrency = list.contains(settings.baseCurrency) ? settings.baseCurrency : "RUB"
        return result
    }
}
