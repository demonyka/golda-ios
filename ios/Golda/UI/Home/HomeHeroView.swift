import GoldaCore
import SwiftUI

/// The hero card of Home: the caption, the big number in the main currency, the other currencies,
/// the wavy bar of what is left today, then the day's share, the pace and the days to payday, any
/// grace-period warnings and the money set aside. Overspent, the whole card turns red.
struct HomeHeroView: View {
    let hero: HomeHero

    @Environment(\.locale) private var locale

    private var tone: Theme.CardTone { hero.isOverspent ? .error : .normal }

    var body: some View {
        HeroCard(tone: tone) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: HomeHero.caption.text(in: locale))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                BigNumber(minor: hero.leftMinor, currency: hero.currency)
                    .padding(.top, Theme.Gap.xs)
                if !hero.others.isEmpty {
                    Text(verbatim: ("≈ " + hero.others).keepingMarksOnTheLine)
                        .font(.body)
                        .tabularDigits()
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // The tile's graphite, not its black ink: a black line with no visible track reads as a divider.
                WavyBar(progress: hero.progress, hero: true, ink: barInk, flat: hero.isBarFlat)
                    .padding(.top, Theme.Gap.m)
                // In a list row a long line was cut to "7 days to payd…" at the largest sizes
                // instead of taking a third line; these lines take the height they need.
                Text(budgetLine)
                    .font(.subheadline)
                    .tabularDigits()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Theme.Gap.s)
                ForEach(Array(hero.graceWarnings.enumerated()), id: \.offset) { _, warning in
                    Text(verbatim: warning.text(in: locale).keepingMarksOnTheLine)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Theme.Gap.xs)
                }
                if let setAside = hero.setAsideText(in: locale) {
                    Text(verbatim: setAside.keepingMarksOnTheLine)
                        .font(.subheadline)
                        .tabularDigits()
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Theme.Gap.xs)
                }
            }
        }
        // One stop for VoiceOver: the whole card as a sentence, amounts in words.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: hero.accessibilityLabel(in: locale)))
        .accessibilityIdentifier("home.hero")
    }

    private var barInk: Color {
        hero.isOverspent ? Theme.Color.onDangerSoft : Theme.Color.graphite
    }

    /// "2 648 ₽ a day ▲120 · 8 days to payday": the pace in the card's main ink when ahead, quiet
    /// when behind, as on Android. One text, so it wraps as a sentence at large type sizes.
    private var budgetLine: AttributedString {
        var line = AttributedString(hero.perDayText(in: locale).keepingMarksOnTheLine)
        if let pace = hero.pace, let paceText = hero.paceText {
            var arrow = AttributedString(paceText)
            if pace.isAhead { arrow.foregroundColor = tone.ink }
            line += arrow
        }
        // A no-break space before the dot, so a wrapped line never starts with it.
        line += AttributedString("\u{00A0}· " + hero.paydayText(in: locale).keepingMarksOnTheLine)
        return line
    }
}
