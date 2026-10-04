import Foundation
import GoldaCore

extension LocalizedStringResource {
    /// The catalog's text in the language of [locale]. Screens pass the environment's locale, tests
    /// a fixed one, so both languages are checked without changing the simulator.
    func text(in locale: Locale) -> String {
        var resource = self
        resource.locale = locale
        return String(localized: resource)
    }
}

/// What VoiceOver should say for an amount the screen writes the Russian way (D13): "1 849 ₽" is
/// read digit group by digit group and "₽" as a sign, so it becomes "1849 Russian rubles" in the
/// language of the interface. The figures stay exact; only the words around them change.
enum SpokenAmount {
    /// Currencies whose symbol `Fmt` writes instead of the code. A code with no symbol of its own
    /// is written as the code, and that is read back as the code.
    private static let knownCodes = Currencies.popular

    /// [display] as written by `Fmt.amount`, `Fmt.approx` or `Base` ("−4 210,50 ₽", "52,2 ₾",
    /// "+150 000 ₽"), spoken in [locale]. Text that is not an amount comes back without the narrow
    /// spaces, which is still better read than with them.
    static func text(_ display: String, locale: Locale) -> String {
        let parts = AmountParts(parsing: display)
        let sign = parts.whole.first.map { $0 == "−" || $0 == "-" ? -1 : 1 } ?? 1
        let digits = parts.whole.filter(\.isNumber)
        let fraction = parts.fraction.filter(\.isNumber)
        guard !digits.isEmpty, let code = code(forSymbol: parts.symbol),
              let magnitude = Decimal(string: fraction.isEmpty ? digits : digits + "." + fraction, locale: Locale(identifier: "en_US_POSIX"))
        else { return display.replacingOccurrences(of: "\u{202F}", with: "") }
        let value = sign < 0 ? -magnitude : magnitude
        // No grouping: VoiceOver reads "1849" as one number, while a group separator makes it pause.
        let style = Decimal.FormatStyle.Currency(code: code, locale: locale)
            .presentation(.fullName)
            .precision(.fractionLength(fraction.count))
            .grouping(.never)
        return value.formatted(style)
    }

    static func code(forSymbol symbol: String) -> String? {
        guard !symbol.isEmpty else { return nil }
        if let code = knownCodes.first(where: { Currencies.symbol($0) == symbol }) { return code }
        // Fmt writes the code itself when a currency has no symbol ("150 AED").
        return symbol.count == 3 && symbol.allSatisfy(\.isUppercase) ? symbol : nil
    }
}
