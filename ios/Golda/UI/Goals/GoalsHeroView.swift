import GoldaCore
import SwiftUI

/// The hero of Goals: the main goal, or the empty tile that asks for one. The tile opens the goal
/// (or a new one); a reached goal adds the screen's only "Купить" under it.
struct GoalsHeroView: View {
    let hero: GoalsHero
    /// The form for the main goal, or for a new goal when there is none.
    var onOpen: () -> Void
    /// "Купить" on a reached goal; the screen asks first.
    var onBuy: (Goal) -> Void
    /// The reached goal has been celebrated; the phone remembers it.
    var onCelebrated: (UUID) -> Void

    var body: some View {
        switch hero {
        case .noGoals(let skipped):
            EmptyGoalTile(title: GoalsHero.setGoalTitle, text: GoalsHero.setGoalText, skipped: skipped, label: hero, onOpen: onOpen)
        case .noMainGoal(let skipped):
            EmptyGoalTile(title: GoalsHero.pickMainTitle, text: GoalsHero.pickMainText, skipped: skipped, label: hero, onOpen: onOpen)
        case .main(let main):
            MainGoalTile(hero: main, onOpen: onOpen, onBuy: onBuy, onCelebrated: onCelebrated)
                // Another main goal is another tile: its celebration starts afresh.
                .id(main.goal.id)
        }
    }
}

/// "Копилка · Поставь цель", or "Выбери главную цель" when goals exist but none is main, with what
/// refusals put aside under it all the same.
private struct EmptyGoalTile: View {
    let title: LocalizedStringResource
    let text: LocalizedStringResource
    let skipped: SkippedTotal
    let label: GoalsHero
    var onOpen: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        HeroCard {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: GoalsHero.caption.text(in: locale))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    // Inside a button a line is cut rather than wrapped; these wrap.
                    Text(verbatim: title.text(in: locale))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.Color.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Theme.Gap.s)
                    Text(verbatim: text.text(in: locale))
                        .font(.body)
                        .foregroundStyle(Theme.Color.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Theme.Gap.xs)
                    Text(verbatim: skipped.text(in: locale).keepingMarksOnTheLine)
                        .font(.subheadline)
                        .tabularDigits()
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Theme.Gap.m)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: label.accessibilityLabel(in: locale)))
            .accessibilityHint(Text(verbatim: GoalsContent.newGoalHint.text(in: locale)))
            .accessibilityIdentifier("goals.hero")
        }
    }
}

/// The main goal: its name, what is saved as the big number with quiet cents, the wavy bar,
/// "62 % из 1 500 $" and what refusals added. Reached, the bar is full, its wave settles (with one
/// tap of haptics the first time on this phone) and "Купить" appears.
private struct MainGoalTile: View {
    let hero: MainGoalHero
    var onOpen: () -> Void
    var onBuy: (Goal) -> Void
    var onCelebrated: (UUID) -> Void

    @Environment(\.locale) private var locale
    /// The wave of a goal reached a moment ago ripples until the celebration settles it; one
    /// celebrated before is flat from the start.
    @State private var settled: Bool
    /// Counts celebrations, so each one is felt once.
    @State private var celebrations = 0

    init(hero: MainGoalHero, onOpen: @escaping () -> Void, onBuy: @escaping (Goal) -> Void, onCelebrated: @escaping (UUID) -> Void) {
        self.hero = hero
        self.onOpen = onOpen
        self.onBuy = onBuy
        self.onCelebrated = onCelebrated
        _settled = State(initialValue: !hero.celebrates)
    }

    var body: some View {
        HeroCard {
            VStack(alignment: .leading, spacing: 0) {
                // Two buttons in one row: each answers only to its own frame.
                Button(action: onOpen) { summary }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: hero.accessibilityLabel(in: locale)))
                    .accessibilityHint(Text(verbatim: GoalsContent.heroHint.text(in: locale)))
                    .accessibilityIdentifier("goals.hero")
                if hero.isReached {
                    // Plain Liquid Glass: blue is for a modal's confirmation (D34), and the
                    // question this opens has it.
                    Button { onBuy(hero.goal) } label: {
                        Text(verbatim: hero.buyTitle(in: locale))
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, minHeight: Theme.minimumTarget)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .padding(.top, Theme.Gap.l)
                    .accessibilityIdentifier("goals.buy")
                }
            }
        }
        .sensoryFeedback(.success, trigger: celebrations)
        .task(id: hero.celebrates) {
            guard hero.celebrates else { return }
            // A beat after the tile appears, so the settling is seen, as on Android.
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            settled = true
            celebrations += 1
            onCelebrated(hero.goal.id)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: hero.goal.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            BigNumber(
                minor: hero.savedMinor, currency: hero.goal.currency, fraction: .automatic,
                quietColor: Theme.Color.muted
            )
            .padding(.top, Theme.Gap.xs)
            // The tile's graphite, as on Home: a black line with no visible track reads as a divider.
            WavyBar(progress: hero.progress, hero: true, ink: Theme.Color.graphite, flat: hero.isReached && settled)
                .padding(.top, Theme.Gap.m)
            // Inside a button a line is cut rather than wrapped; at the largest sizes these wrap.
            Text(verbatim: hero.progressText(in: locale).keepingMarksOnTheLine)
                .font(.subheadline)
                .tabularDigits()
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Gap.s)
            Text(verbatim: hero.skipped.text(in: locale).keepingMarksOnTheLine)
                .font(.subheadline)
                .tabularDigits()
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Gap.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }
}
