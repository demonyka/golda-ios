import SwiftUI

/// One setting, as Android's `SettingRow`: a quiet glyph, the name in the text ink with what it is
/// for under it, and the value at the end in quiet ink. A row that opens something ends in a mark
/// saying where it goes. At the accessibility sizes the glyph steps aside and the value moves under
/// the name, so the words have the whole width.
struct SettingRow: View {
    let title: String
    /// Nil leaves the glyph's room empty, so the text still lines up with the rows that have one.
    let symbol: String?
    var value: String?
    var detail: String?
    /// `SettingsSymbols.opens` for a sheet, `.leavesApp` for the iOS Settings, nil for an action.
    var trailingSymbol: String?
    /// Red name and glyph: the row destroys data ("Стереть всё").
    var isDestructive = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// One column for every glyph, growing with the text, so the names line up whatever the
    /// symbol's own width.
    @ScaledMetric(relativeTo: .body) private var glyphWidth: CGFloat = 28

    var body: some View {
        HStack(spacing: Theme.Gap.m) {
            // At the accessibility sizes the glyph would take a third of the width the words need.
            if !isStacked { glyph }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .foregroundStyle(isDestructive ? Theme.Color.danger : Theme.Color.text)
                if let detail {
                    Text(verbatim: detail)
                        .font(.footnote)
                        .foregroundStyle(Theme.Color.muted)
                }
                if isStacked, let value {
                    valueText(value)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !isStacked, let value {
                valueText(value)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            if let trailingSymbol {
                Image(systemName: trailingSymbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Color.muted)
                    .accessibilityHidden(true)
            }
        }
        // No height of its own: a list row is never under 44 pt.
        .contentShape(.rect)
    }

    private var isStacked: Bool { dynamicTypeSize.isAccessibilitySize }

    private var glyph: some View {
        // An empty slot is a hidden glyph, so it is sized and laid out like a real one.
        Image(systemName: symbol ?? SettingsSymbols.version)
            .foregroundStyle(isDestructive ? Theme.Color.danger : Theme.Color.muted)
            .opacity(symbol == nil ? 0 : 1)
            .frame(width: glyphWidth)
            .accessibilityHidden(true)
    }

    private func valueText(_ value: String) -> some View {
        Text(verbatim: value)
            .monospacedDigit()
            .foregroundStyle(Theme.Color.muted)
    }
}
