import SwiftUI

/// The days of a month as circles in rows of seven, one tap picks: payday and a payment's day, the
/// port of Android's `DayGrid`. The picked day is graphite, the others soft (D34: graphite is what
/// is picked). At the accessibility text sizes the circles grow and the rows hold four, so a
/// two-digit day still fits its circle.
struct DayGrid: View {
    let selected: Int?
    var onPick: (Int) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var scaledDiameter: CGFloat = 44

    /// Never under the 44 pt of a touch target, never so big that four do not fit a phone's row.
    private var diameter: CGFloat { min(max(scaledDiameter, Theme.minimumTarget), 72) }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Theme.Gap.xs), count: dynamicTypeSize.isAccessibilitySize ? 4 : 7)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: Theme.Gap.xs) {
            ForEach(1...31, id: \.self) { day in
                let isPicked = day == selected
                Button {
                    onPick(day)
                } label: {
                    Text(verbatim: "\(day)")
                        .font(.body.weight(.medium))
                        .tabularDigits()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(isPicked ? Theme.Color.onGraphite : Theme.Color.text)
                        .frame(width: diameter, height: diameter)
                        .background(isPicked ? Theme.Color.graphite : Theme.Color.soft, in: Circle())
                        .contentShape(Circle())
                }
                // Each circle answers to its own taps, not to the whole row of the list it sits in.
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(isPicked ? .isSelected : [])
                .accessibilityIdentifier("dayGrid.\(day)")
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
    }
}

#Preview("Picked 10") {
    @Previewable @State var day: Int? = 10
    List {
        DayGrid(selected: day) { day = $0 }
    }
}

#Preview("Accessibility, dark") {
    @Previewable @State var day: Int? = 31
    List {
        DayGrid(selected: day) { day = $0 }
    }
    .dynamicTypeSize(.accessibility3)
    .preferredColorScheme(.dark)
}
