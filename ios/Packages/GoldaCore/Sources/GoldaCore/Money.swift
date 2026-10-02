import Foundation

public enum Money {
    /// Kotlin's `Double.roundToLong()`: ties go toward positive infinity (-2.5 gives -2, where
    /// Swift's `.rounded()` gives -3), NaN becomes 0 and out-of-range values clamp.
    public static func roundHalfUp(_ x: Double) -> Int64 {
        if x.isNaN { return 0 }
        let limit = 9.223372036854775807e18
        if x >= limit { return .max }
        if x <= -limit { return .min }
        // `x - floor` is exact, so a tie is detected exactly and 0.49999999999999994 stays 0.
        let floor = x.rounded(.down)
        let rounded = x - floor >= 0.5 ? floor + 1 : floor
        return rounded >= limit ? .max : Int64(rounded)
    }
}

public enum Currencies {
    /// Offered in pickers. Any code the CBR publishes works.
    public static let common = ["RUB", "USD", "EUR", "GEL", "THB", "TRY", "KZT", "AMD", "CNY", "AED", "VND", "IDR"]

    private static let symbols: [String: String] = [
        "RUB": "₽", "USD": "$", "EUR": "€", "GEL": "₾", "THB": "฿", "TRY": "₺",
        "KZT": "₸", "AMD": "֏", "CNY": "¥", "VND": "₫", "GBP": "£",
    ]

    /// ISO 4217 minor units, as `java.util.Currency` reports them. Everything not listed has 2, and
    /// the pseudo-currencies Java reports as -1 (metals, XDR, XXX) count as 0.
    private static let fractionDigits: [String: Int] = {
        var table: [String: Int] = [:]
        for code in ["BIF", "CLP", "DJF", "GNF", "ISK", "JPY", "KMF", "KRW", "PYG", "RWF", "UGX", "UYI", "VND", "VUV", "XAF", "XOF", "XPF"] { table[code] = 0 }
        for code in ["XAG", "XAU", "XBA", "XBB", "XBC", "XBD", "XDR", "XPD", "XPT", "XSU", "XTS", "XUA", "XXX"] { table[code] = 0 }
        for code in ["BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND"] { table[code] = 3 }
        for code in ["CLF", "UYW"] { table[code] = 4 }
        return table
    }()

    public static func symbol(_ code: String) -> String { symbols[code] ?? code }

    public static func digits(_ code: String) -> Int { fractionDigits[code] ?? 2 }

    public static func factor(_ code: String) -> Double {
        var f = 1.0
        for _ in 0..<digits(code) { f *= 10 }
        return f
    }

    static func integerFactor(_ code: String) -> UInt64 {
        var f: UInt64 = 1
        for _ in 0..<digits(code) { f *= 10 }
        return f
    }

    public static func toMajor(_ minor: Int64, _ code: String) -> Double { Double(minor) / factor(code) }

    public static func toMinor(_ major: Double, _ code: String) -> Int64 { Money.roundHalfUp(major * factor(code)) }
}

/// Amounts are written the Russian way in every language (decision D13): a narrow no-break space
/// between thousands, a comma for decimals, a real minus sign, "4 210,50 ₽".
public enum Fmt {
    private static let thousands: Character = "\u{202F}"
    private static let minus = "−"
    private static let comma: Character = ","

    /// "4 210,50 ₽"; whole amounts drop ",00". Built from the integer minor units, so it is exact.
    public static func amount(_ minor: Int64, _ code: String, signed: Bool = false) -> String {
        let (whole, fraction) = parts(minor, code, alwaysFraction: false)
        let sign = minor < 0 ? minus : (signed && minor > 0 ? "+" : "")
        return sign + whole + fraction + " " + Currencies.symbol(code)
    }

    /// Integer part and fraction part separately, for the big numbers ("4 210", ",00").
    public static func split(_ minor: Int64, _ code: String) -> (whole: String, fraction: String) {
        let (whole, fraction) = parts(minor, code, alwaysFraction: true)
        return ((minor < 0 ? minus : "") + whole, fraction)
    }

    /// Converted, approximate values: "510 ₽", "5,5 $".
    public static func approx(_ major: Double, _ code: String) -> String {
        let decimals = (abs(major) >= 100 || Currencies.digits(code) == 0) ? 0 : 1
        var text = fixed(major, decimals: decimals, grouping: true)
        if text.hasSuffix(",0") { text.removeLast(2) }
        return text + " " + Currencies.symbol(code)
    }

    public static func percent(_ value: Double, signed: Bool = false) -> String {
        var text = fixed(value * 100, decimals: 1, grouping: false)
        if text.hasSuffix(",0") { text.removeLast(2) }
        return (signed && value > 0 ? "+" : "") + text + " %"
    }

    /// At most [decimals] decimals, no grouping: "2,5", "3".
    public static func number(_ value: Double, decimals: Int = 2) -> String {
        var text = fixed(value, decimals: decimals, grouping: false)
        if decimals > 0, text.contains(comma) {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(String(comma)) { text.removeLast() }
        }
        return text
    }

    /// Accepts "15", "15,5", "1 500.25". Nil for anything that is not a non-negative amount, and for
    /// amounts too big to hold.
    public static func parseMinor(_ text: String, _ code: String) -> Int64? {
        let clean = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard !clean.isEmpty, clean.wholeMatch(of: /[+-]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][+-]?[0-9]+)?/) != nil,
              let value = Decimal(string: clean, locale: Locale(identifier: "en_US_POSIX")),
              !value.isNaN, value >= 0
        else { return nil }
        var scaled = value * Decimal(Currencies.integerFactor(code))
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain) // half up, like BigDecimal's HALF_UP
        guard !rounded.isNaN, rounded <= Decimal(Int64.max) else { return nil }
        return NSDecimalNumber(decimal: rounded).int64Value
    }

    /// Nil for anything Double can't read, and for NaN and infinity.
    public static func parseDouble(_ text: String) -> Double? {
        let clean = text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: ".")
        guard let value = Double(clean), value.isFinite else { return nil }
        return value
    }

    /// The text a field starts with for an existing amount: "15", "2,5", "-3,05".
    public static func editable(_ minor: Int64, _ code: String) -> String {
        let digits = Currencies.digits(code)
        let factor = Currencies.integerFactor(code)
        let magnitude = minor.magnitude
        var fraction = digits > 0 ? padded(magnitude % factor, digits) : ""
        while fraction.hasSuffix("0") { fraction.removeLast() }
        return (minor < 0 ? "-" : "") + String(magnitude / factor) + (fraction.isEmpty ? "" : "," + fraction)
    }

    // MARK: Pieces

    private static func parts(_ minor: Int64, _ code: String, alwaysFraction: Bool) -> (String, String) {
        let digits = Currencies.digits(code)
        let factor = Currencies.integerFactor(code)
        let magnitude = minor.magnitude
        let remainder = magnitude % factor
        let showFraction = digits > 0 && (alwaysFraction || remainder != 0)
        return (group(String(magnitude / factor)), showFraction ? String(comma) + padded(remainder, digits) : "")
    }

    /// `String(format:)` expands the binary value exactly and breaks exact ties to even, which is
    /// what Java's DecimalFormat does since JDK 8; `x * 10 / 10` tricks would not.
    private static func fixed(_ value: Double, decimals: Int, grouping: Bool) -> String {
        let raw = String(format: "%.\(decimals)f", value)
        let negative = raw.hasPrefix("-")
        let body = negative ? String(raw.dropFirst()) : raw
        let pieces = body.split(separator: ".", omittingEmptySubsequences: false)
        let whole = grouping ? group(String(pieces[0])) : String(pieces[0])
        let fraction = pieces.count > 1 ? String(comma) + pieces[1] : ""
        return (negative ? minus : "") + whole + fraction
    }

    private static func group(_ digits: String) -> String {
        var out = ""
        for (offset, char) in digits.enumerated() {
            if offset > 0, (digits.count - offset) % 3 == 0 { out.append(thousands) }
            out.append(char)
        }
        return out
    }

    private static func padded(_ value: UInt64, _ width: Int) -> String {
        let text = String(value)
        return String(repeating: "0", count: max(0, width - text.count)) + text
    }
}
