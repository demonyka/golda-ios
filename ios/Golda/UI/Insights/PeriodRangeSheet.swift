import GoldaCore
import SwiftUI

/// The dates of a period of your own: from and to, each with its calendar. iOS has no range
/// calendar, and two dates with a calendar each is how Calendar's own start and end read. "Готово"
/// takes the range, "Отмена" leaves the screen as it was.
///
/// A row opens its calendar in a small sheet, as the operation form's day does (`DateRowButton`).
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

    private func row(_ end: End) -> some View {
        DateRowButton(title: title(end), date: InsightsDates.full(end == .from ? draft.from : draft.to, in: locale)) {
            picking = end
        }
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
