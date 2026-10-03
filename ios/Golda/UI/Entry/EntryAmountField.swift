import GoldaCore
import SwiftUI
import UIKit

/// The amount is the whole point of the operation form: a bare, big, centred number with its
/// currency after it, the iOS side of Android's `HeroAmountField`. When the price can be in any
/// currency (an expense) the symbol is a glass button with the menu of currencies; otherwise it is
/// quiet ink, since it only says what the number is in.
struct EntryAmountField: View {
    @Binding var text: String
    let currency: String
    /// The currencies to pick from; nil when the currency is the account's and cannot change.
    let choices: [String]?
    var onPick: (String) -> Void
    var isInvalid: Bool
    @Binding var isFocused: Bool
    /// What VoiceOver calls the field and the menu.
    let label: String
    let currencyLabel: String

    @ScaledMetric(relativeTo: .largeTitle) private var baseSize: CGFloat = 64

    var body: some View {
        let font = UIFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
        HStack(alignment: .firstTextBaseline, spacing: Theme.Gap.s) {
            Spacer(minLength: 0)
            GroupedAmountField(
                text: $text, isFocused: $isFocused, font: font, isInvalid: isInvalid, label: label, identifier: "entry.amount"
            )
            // A UIKit field has no baseline SwiftUI can see; the text sits centred in its height.
            .alignmentGuide(.firstTextBaseline) { d in (d.height - font.lineHeight) / 2 + font.ascender }
            symbol(font)
            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.Gap.xs)
    }

    @ViewBuilder private func symbol(_ font: UIFont) -> some View {
        let symbol = Text(verbatim: Currencies.symbol(currency))
        if let choices {
            Menu {
                Picker(selection: Binding(get: { currency }, set: { onPick($0) })) {
                    ForEach(choices, id: \.self) { code in
                        Text(verbatim: AccountFormModel.currencyLabel(code)).tag(code)
                    }
                } label: {
                    Text(verbatim: currencyLabel)
                }
            } label: {
                // Smaller than the digits, so the glass around it stays within the line.
                symbol
                    .font(Font(font.withSize(font.pointSize * 0.5)))
                    .foregroundStyle(Theme.Color.text)
                    .frame(minWidth: Theme.minimumTarget, minHeight: Theme.minimumTarget)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel(Text(verbatim: currencyLabel))
            .accessibilityValue(Text(verbatim: AccountFormModel.currencyLabel(currency)))
            .accessibilityIdentifier("entry.currency")
        } else {
            symbol
                .font(Font(font))
                .foregroundStyle(Theme.Color.muted)
                .lineLimit(1)
                .accessibilityHidden(true)
        }
    }

    /// Shrinks with the length rather than with a measured width: a field cannot shrink its own
    /// text to fit, and these steps keep a seven-figure amount with kopecks on one line.
    private var size: CGFloat {
        let capped = min(baseSize, 80)
        switch text.count {
        case ...5: return capped
        case ...7: return capped * 0.8
        case ...10: return capped * 0.62
        default: return capped * 0.5
        }
    }
}
