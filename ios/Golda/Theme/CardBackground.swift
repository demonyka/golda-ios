import SwiftUI

extension Theme {
    /// What a card is filled with: the normal white-on-grey card, or the soft red of an overspent hero.
    enum CardTone: Equatable, Sendable {
        case normal
        case error

        var fill: SwiftUI.Color {
            switch self {
            case .normal: Theme.Color.card
            case .error: Theme.Color.dangerSoft
            }
        }

        /// Primary text on this fill.
        var ink: SwiftUI.Color {
            switch self {
            case .normal: Theme.Color.text
            case .error: Theme.Color.onDangerSoft
            }
        }

        /// Second-level text on this fill. On red it is the same ink a little quieter, never `muted`:
        /// grey on `dangerSoft` is too faint.
        var quietInk: SwiftUI.Color {
            switch self {
            case .normal: Theme.Color.muted
            case .error: Theme.Color.onDangerSoft.opacity(0.78)
            }
        }
    }

    /// The card outline: 28 pt, continuous corners (the same curve the system uses for its own cards).
    static let cardShape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
}

extension View {
    /// Fills the view with a card and sets the ink for what is inside it. The primary and secondary
    /// foreground styles are set together, so `.foregroundStyle(.secondary)` inside lands on the
    /// quiet ink of the card, whatever its tone.
    func cardBackground(_ tone: Theme.CardTone = .normal) -> some View {
        self
            .foregroundStyle(tone.ink, tone.quietInk)
            .background(tone.fill, in: Theme.cardShape)
            // Red arrives and leaves with the budget, so the colour changes softly.
            .animation(.easeInOut(duration: 0.25), value: tone)
    }
}
