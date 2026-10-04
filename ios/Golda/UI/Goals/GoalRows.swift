import SwiftUI

/// Another goal in the list: the name, "62 % · из 1 500 $", what is saved with quiet cents, and a
/// thin wavy bar under it all.
struct GoalRowView: View {
    let row: GoalRowModel

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Gap.s) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Gap.xs))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Theme.Gap.m))
            layout {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: row.goal.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.Color.text)
                        .lineLimit(lineLimit)
                    Text(verbatim: row.detailText(in: locale).keepingMarksOnTheLine)
                        .font(.subheadline)
                        .tabularDigits()
                        .foregroundStyle(Theme.Color.muted)
                        .lineLimit(lineLimit)
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: Theme.Gap.s) }
                Text(AccountRowView.quietCents(row.saved))
                    .font(.title3)
                    .tabularDigits()
                    .foregroundStyle(Theme.Color.text)
                    .lineLimit(1)
                    .contentTransition(.numericText(value: Double(row.savedMinor)))
                    // The amount keeps its width; the name gives way first.
                    .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
            }
            WavyBar(progress: row.progress, ink: Theme.Color.graphite)
        }
        .padding(.vertical, Theme.Gap.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: row.accessibilityLabel(in: locale)))
    }

    private var lineLimit: Int? { dynamicTypeSize.isAccessibilitySize ? nil : 2 }
}

/// A wish in the list: its name, the line under it, and its price at the end.
struct WishRowView: View {
    let title: String
    let detail: String
    let amount: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Gap.xs))
            : AnyLayout(HStackLayout(spacing: Theme.Gap.m))
        layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .font(.body)
                    .foregroundStyle(Theme.Color.text)
                    .lineLimit(lineLimit)
                Text(verbatim: detail.keepingMarksOnTheLine)
                    .font(.subheadline)
                    .tabularDigits()
                    .foregroundStyle(Theme.Color.muted)
                    .lineLimit(lineLimit)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: Theme.Gap.s) }
            Text(verbatim: amount)
                .font(.body)
                .tabularDigits()
                .foregroundStyle(Theme.Color.text)
                .lineLimit(1)
                .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
        }
        .padding(.vertical, Theme.Gap.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    private var lineLimit: Int? { dynamicTypeSize.isAccessibilitySize ? nil : 2 }
}
