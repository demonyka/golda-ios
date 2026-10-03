import SwiftUI

/// One operation in a grouped list: the glyph, the title with its line underneath, and the amount
/// column. It only lays out what `OperationRowModel` worked out.
struct OperationRowView: View {
    let row: OperationRowModel

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // At the largest sizes nothing fits beside anything: the amount goes under the text,
                // and the glyph, which only repeats the category, steps aside.
                VStack(alignment: .leading, spacing: Theme.Gap.xs) {
                    texts
                    amounts(alignment: .leading)
                }
            } else {
                HStack(spacing: Theme.Gap.m) {
                    GlyphCircle(row.symbol)
                    texts
                    Spacer(minLength: Theme.Gap.s)
                    amounts(alignment: .trailing)
                }
            }
        }
        .padding(.vertical, Theme.Gap.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Two lines, not Android's one: a transfer's "A → B" would otherwise lose where it went.
            Text(verbatim: row.title(in: locale))
                .font(.body)
                .foregroundStyle(Theme.Color.text)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            if let supporting = row.supporting {
                Text(verbatim: supporting)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Color.muted)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            }
        }
    }

    private func amounts(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(verbatim: row.main)
                .font(.body.weight(.semibold))
                .tabularDigits()
                .foregroundStyle(row.tone == .neutral ? Theme.Color.muted : Theme.Color.text)
                .lineLimit(1)
            if let secondary = row.secondary {
                Text(verbatim: secondary.text)
                    .font(.footnote)
                    .tabularDigits()
                    .foregroundStyle(Theme.Color.muted)
                    .lineLimit(1)
            }
        }
        // The amount keeps its width; the title gives way first.
        .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
    }
}
