import SwiftUI

/// An SF Symbol in a circle of the page colour, cut into the card: the icon at the start of a row
/// (a category, a transfer, an account type).
struct GlyphCircle: View {
    var symbol: String
    /// Spoken by VoiceOver. Nil keeps the glyph decorative, which is right when the row's own text
    /// already says what it is.
    var accessibilityLabel: Text?

    @ScaledMetric(relativeTo: .body) private var scaledDiameter: CGFloat = 40

    init(_ symbol: String, accessibilityLabel: Text? = nil) {
        self.symbol = symbol
        self.accessibilityLabel = accessibilityLabel
    }

    /// The circle grows with Dynamic Type, but not past a point where a row of text would be
    /// squeezed out by its own icon.
    private var diameter: CGFloat { min(scaledDiameter, 72) }

    var body: some View {
        glyph
            .accessibilityHidden(accessibilityLabel == nil)
    }

    @ViewBuilder private var glyph: some View {
        let image = Image(systemName: symbol)
            .font(.system(size: diameter * 0.45, weight: .regular))
            .foregroundStyle(Theme.Color.muted)
            .frame(width: diameter, height: diameter)
            .background(Theme.Color.page, in: Circle())
        if let accessibilityLabel {
            image.accessibilityLabel(accessibilityLabel)
        } else {
            image
        }
    }
}

// MARK: - Previews

private struct GlyphGallery: View {
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Gap.s) {
                HStack(spacing: Theme.Gap.m) {
                    ForEach(["fork.knife", "cart", "bus", "pills", "tshirt", "shippingbox"], id: \.self) { GlyphCircle($0) }
                }
                HStack(spacing: Theme.Gap.m) {
                    GlyphCircle(Symbols.category("eating_out"))
                    Text(verbatim: "Coffee").font(.body)
                    Spacer()
                    Text(verbatim: "−8 ₾").font(.body).tabularDigits()
                }
            }
        }
        .padding(Theme.Gap.m)
        .background(Theme.Color.page)
    }
}

#Preview("Light") { GlyphGallery() }
#Preview("Dark") { GlyphGallery().preferredColorScheme(.dark) }
#Preview("Accessibility XXL") { GlyphGallery().dynamicTypeSize(.accessibility3) }
