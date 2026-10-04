import GoldaCore
import SwiftUI

/// The dates of a period of your own: from and to, each with its calendar. iOS has no range
/// calendar, and two dates with a calendar each is how Calendar's own start and end read. "Готово"
/// takes the range, "Отмена" leaves the screen as it was.
///
/// A row opens its calendar in a small sheet, as the operation form's day does. The compact
/// `DatePicker` looked the same, but its button is UIKit's and read only "Date Picker" to
/// VoiceOver: no label of SwiftUI's reaches it, and a row of our own says "From, 27 Sep 2026".
struct PeriodRangeSheet: View {
    let zone: TimeZone
    var onCancel: () -> Void
    var onDone: (Period) -> Void

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var draft: PeriodRangeDraft
    @State private var picking: End?

    /// The end of the range whose calendar is open.
    private enum End: String, Identifiable {
        case from, to
        var id: String { rawValue }
    }

    init(period: Period, zone: TimeZone, onCancel: @escaping () -> Void, onDone: @escaping (Period) -> Void) {
        self.zone = zone
        self.onCancel = onCancel
        self.onDone = onDone
        _draft = State(initialValue: PeriodRangeDraft(period))
    }

    private static let done = LocalizedStringResource("Done", table: "Insights", comment: "Button that takes the picked period.")
    private static let from = LocalizedStringResource("From", table: "Insights", comment: "Insights, custom period: the first day.")
    private static let to = LocalizedStringResource("To", table: "Insights", comment: "Insights, custom period: the last day.")

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row(.from)
                    row(.to)
                }
                .listRowBackground(Theme.Color.card)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.Color.page)
            .navigationTitle(Text("Period", tableName: "Insights", comment: "Insights: title of the sheet where the custom period is picked."))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel, action: onCancel) {
                        Text("Cancel", tableName: "Insights", comment: "Button that closes the period sheet without a change.")
                    }
                    .accessibilityIdentifier("insights.range.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    ConfirmButton(title: Self.done.text(in: locale)) {
                        onDone(draft.period)
                    }
                    .accessibilityIdentifier("insights.range.done")
                }
            }
        }
        // Two rows fit a short sheet; at the accessibility sizes the rows are taller than it.
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(260), .large])
        .presentationBackground(Theme.Color.page)
        .sheet(item: $picking) { end in
            DayCalendarSheet(
                title: title(end), date: day(end), zone: zone,
                doneTitle: Self.done.text(in: locale), identifier: "insights.range.\(end.rawValue)"
            )
        }
    }

    /// "С            27 сент. 2026 г.": the title, and the day in a pill as the system's pickers
    /// show it. At the accessibility sizes the day goes under the title, where it has the width.
    private func row(_ end: End) -> some View {
        let title = title(end)
        let date = InsightsDates.full(end == .from ? draft.from : draft.to, in: locale)
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Gap.xs))
            : AnyLayout(HStackLayout(spacing: Theme.Gap.s))
        return Button {
            picking = end
        } label: {
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
        .accessibilityIdentifier("insights.range.\(end.rawValue)")
    }

    private func title(_ end: End) -> String {
        (end == .from ? Self.from : Self.to).text(in: locale)
    }

    /// One end of the draft; moving it past the other drags the other along.
    private func day(_ end: End) -> Binding<LocalDate> {
        Binding(
            get: { end == .from ? draft.from : draft.to },
            set: { day in
                if end == .from { draft.setFrom(day) } else { draft.setTo(day) }
            }
        )
    }
}
