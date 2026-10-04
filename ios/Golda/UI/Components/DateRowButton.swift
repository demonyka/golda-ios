import SwiftUI

/// "С            27 сент. 2026 г.": a title and the day in a pill, as the system's pickers show
/// it, that opens `DayCalendarSheet`. The compact `DatePicker` looked the same, but its button is
/// UIKit's and read only "Date Picker" to VoiceOver: no label of SwiftUI's reaches it, and this row
/// says "From, 27 Sep 2026" (D51). At the accessibility sizes the day goes under the title, where
/// it has the width.
struct DateRowButton: View {
    let title: String
    /// The day as the interface writes it (`InsightsDates.full`).
    let date: String
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Gap.xs))
            : AnyLayout(HStackLayout(spacing: Theme.Gap.s))
        Button(action: action) {
            layout {
                Text(verbatim: title)
                    .foregroundStyle(Theme.Color.text)
                if !stacked { Spacer(minLength: Theme.Gap.s) }
                Text(verbatim: date)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Color.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.Color.soft, in: Capsule())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(Text(verbatim: date))
        .accessibilityAddTraits(.isButton)
    }
}
