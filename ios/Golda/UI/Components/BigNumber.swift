import GoldaCore
import SwiftUI

// MARK: - Parts of an amount

/// An amount in the pieces a big number needs: the whole units that get the size, the fraction that
/// may go quiet, and the currency symbol that rides on the digits' baseline.
struct AmountParts: Equatable, Sendable {
    /// "4 210", or "−4 210" for a negative amount.
    var whole: String
    /// ",50" with its separator, or "" when there is none.
    var fraction: String
    /// "₽", or "" for a plain number.
    var symbol: String

    init(whole: String, fraction: String = "", symbol: String = "") {
        self.whole = whole
        self.fraction = fraction
        self.symbol = symbol
    }

    /// Takes apart what `Fmt.amount` writes ("−4 210,50 ₽"): thousands are narrow no-break spaces,
    /// the decimal separator is always a comma (D13), and the symbol follows the last ordinary space.
    init(parsing amount: String) {
        var rest = Substring(amount)
        if let space = rest.lastIndex(of: " ") {
            let tail = rest[rest.index(after: space)...]
            if !tail.isEmpty, !tail.contains(where: \.isNumber) {
                symbol = String(tail)
                rest = rest[..<space]
            } else {
                symbol = ""
            }
        } else {
            symbol = ""
        }
        if let comma = rest.firstIndex(of: ",") {
            whole = String(rest[..<comma])
            fraction = String(rest[comma...])
        } else {
            whole = String(rest)
            fraction = ""
        }
    }

    /// What the amount reads as in one piece: "4 210,50 ₽".
    var text: String { whole + fraction + (symbol.isEmpty ? "" : " " + symbol) }

    /// How much of the fraction a big number shows.
    enum FractionStyle: Sendable {
        /// Whole units only: "1 849 ₽".
        case hidden
        /// The fraction only when there is one, the way `Fmt.amount` writes it: "4 210 ₽", "4 210,50 ₽".
        case automatic
        /// Always, even ",00": "4 210,00 ₽".
        case always
    }

    /// The pieces of `minor` in `currency`, made by the domain's own formatter so the digits are exact.
    init(minor: Int64, currency: String, fraction style: FractionStyle) {
        switch style {
        case .automatic:
            self.init(parsing: Fmt.amount(minor, currency))
        case .hidden, .always:
            let split = Fmt.split(minor, currency)
            self.init(
                whole: split.whole,
                fraction: style == .always ? split.fraction : "",
                symbol: Currencies.symbol(currency)
            )
        }
    }
}

// MARK: - View

/// A whole-unit amount that fills the width it is given up to a maximum size, in one line, with
/// tabular figures. The size comes from `@ScaledMetric` (so it follows Dynamic Type) and shrinks to
/// fit down to `minimumScale`. When the value changes the digits roll (`.numericText`).
///
/// The symbol is part of the same text run as the digits, so it sits on their baseline whatever
/// font the symbol falls back to. The fraction can take a quieter colour.
struct BigNumber: View {
    var parts: AmountParts
    /// The number the digits roll to; the text alone cannot say whether the amount grew or shrank.
    var value: Double
    /// Defaults to the foreground style of whatever it sits on.
    var color: Color?
    /// The colour of the fraction. Nil keeps it the same as the whole units.
    var quietColor: Color?
    var alignment: Alignment
    /// The amount as VoiceOver should say it ("пятнадцать лари"). Nil reads the text.
    var spokenText: String?

    @ScaledMetric private var maxSize: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The smallest the text may shrink to, as a share of `maxSize` (DESIGN.md: 0.5; smaller here
    /// so that a seven-figure total with a symbol still fits a narrow hero).
    static let minimumScale: CGFloat = 0.35

    init(
        _ parts: AmountParts,
        value: Double,
        color: Color? = nil,
        quietColor: Color? = nil,
        maxSize: CGFloat = 88,
        alignment: Alignment = .leading,
        spokenText: String? = nil
    ) {
        self.parts = parts
        self.value = value
        self.color = color
        self.quietColor = quietColor
        self.alignment = alignment
        self.spokenText = spokenText
        _maxSize = ScaledMetric(wrappedValue: maxSize, relativeTo: .largeTitle)
    }

    /// An amount in minor units of `currency`: the parts and the rolling value come from the amount itself.
    init(
        minor: Int64,
        currency: String,
        fraction: AmountParts.FractionStyle = .hidden,
        color: Color? = nil,
        quietColor: Color? = nil,
        maxSize: CGFloat = 88,
        alignment: Alignment = .leading,
        spokenText: String? = nil
    ) {
        self.init(
            AmountParts(minor: minor, currency: currency, fraction: fraction),
            value: Currencies.toMajor(minor, currency),
            color: color,
            quietColor: quietColor,
            maxSize: maxSize,
            alignment: alignment,
            spokenText: spokenText
        )
    }

    var body: some View {
        Text(attributed)
            .font(.system(size: maxSize, weight: .semibold).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(Self.minimumScale)
            .contentTransition(.numericText(value: value))
            .animation(reduceMotion ? nil : .snappy, value: parts)
            .frame(maxWidth: .infinity, alignment: alignment)
            .accessibilityLabel(spokenText ?? parts.text.replacingOccurrences(of: "\u{202F}", with: ""))
    }

    /// Three runs, so the fraction can be quieter. A run without a colour takes the foreground style
    /// of whatever the number sits on.
    private var attributed: AttributedString {
        func run(_ text: String, _ color: Color?) -> AttributedString {
            var run = AttributedString(text)
            if let color { run.foregroundColor = color }
            return run
        }
        return run(parts.whole, color)
            + run(parts.fraction, quietColor ?? color)
            + run(parts.symbol.isEmpty ? "" : " " + parts.symbol, color)
    }
}

// MARK: - Previews

private struct BigNumberGallery: View {
    var body: some View {
        VStack(spacing: Theme.Gap.m) {
            HeroCard {
                VStack(alignment: .leading, spacing: Theme.Gap.xs) {
                    Text(verbatim: "Hero").font(.subheadline).foregroundStyle(.secondary)
                    BigNumber(minor: 184_900, currency: "RUB")
                }
            }
            HeroCard {
                VStack(alignment: .leading, spacing: Theme.Gap.xs) {
                    Text(verbatim: "Quiet cents").font(.subheadline).foregroundStyle(.secondary)
                    BigNumber(
                        minor: 17_475, currency: "USD", fraction: .always,
                        quietColor: Theme.Color.muted
                    )
                }
            }
            HeroCard {
                VStack(alignment: .leading, spacing: Theme.Gap.xs) {
                    Text(verbatim: "A long one").font(.subheadline).foregroundStyle(.secondary)
                    BigNumber(minor: 123_456_789_000, currency: "RUB", fraction: .always, quietColor: Theme.Color.muted)
                }
            }
            HeroCard(isError: true) {
                VStack(alignment: .leading, spacing: Theme.Gap.xs) {
                    Text(verbatim: "Overspent").font(.subheadline).foregroundStyle(.secondary)
                    BigNumber(minor: -32_000, currency: "RUB")
                }
            }
            HeroCard {
                BigNumber(minor: 800, currency: "GEL", alignment: .center)
            }
        }
        .padding(Theme.Gap.m)
        .background(Theme.Color.page)
    }
}

#Preview("Light") { BigNumberGallery() }
#Preview("Dark") { BigNumberGallery().preferredColorScheme(.dark) }
#Preview("Accessibility XXL") { BigNumberGallery().dynamicTypeSize(.accessibility3) }
