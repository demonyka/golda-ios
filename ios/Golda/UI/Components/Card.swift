import SwiftUI

/// A secondary tile: 28 pt continuous corners, 16 pt inside. Use it for anything that is a card
/// but not the one big tile of the screen.
struct Card<Content: View>: View {
    var tone: Theme.CardTone = .normal
    var padding: CGFloat = Theme.Gap.m
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground(tone)
    }
}

/// The one big tile of a screen (Home, Accounts, Goals): a card like the rest, set apart by its
/// size and its number rather than by colour. When the budget is overspent it takes the error tone:
/// `dangerSoft` fill with `onDangerSoft` ink.
struct HeroCard<Content: View>: View {
    var tone: Theme.CardTone = .normal
    @ViewBuilder var content: Content

    init(tone: Theme.CardTone = .normal, @ViewBuilder content: () -> Content) {
        self.tone = tone
        self.content = content()
    }

    /// `isError` reads better at a call site that has a Bool ("overspent") rather than a tone.
    init(isError: Bool, @ViewBuilder content: () -> Content) {
        self.init(tone: isError ? .error : .normal, content: content)
    }

    var body: some View {
        content
            .padding(Theme.Gap.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground(tone)
    }
}

// MARK: - Previews

private struct CardGallery: View {
    var body: some View {
        VStack(spacing: Theme.Gap.m) {
            HeroCard {
                VStack(alignment: .leading, spacing: Theme.Gap.s) {
                    Text(verbatim: "Hero card").font(.subheadline).foregroundStyle(.secondary)
                    Text(verbatim: "1 849 ₽").font(.largeTitle.weight(.semibold)).tabularDigits()
                    WavyBar(progress: 0.65, hero: true)
                }
            }
            HeroCard(isError: true) {
                VStack(alignment: .leading, spacing: Theme.Gap.s) {
                    Text(verbatim: "Hero card, error").font(.subheadline).foregroundStyle(.secondary)
                    Text(verbatim: "−320 ₽").font(.largeTitle.weight(.semibold)).tabularDigits()
                    WavyBar(progress: 1, hero: true, flat: false)
                }
            }
            Card {
                Text(verbatim: "A plain card").font(.body)
            }
            Card(tone: .error) {
                Text(verbatim: "A plain card, error").font(.body)
            }
        }
        .padding(Theme.Gap.m)
        .background(Theme.Color.page)
    }
}

#Preview("Light") { CardGallery() }
#Preview("Dark") { CardGallery().preferredColorScheme(.dark) }
#Preview("Accessibility XXL") { CardGallery().dynamicTypeSize(.accessibility2) }
