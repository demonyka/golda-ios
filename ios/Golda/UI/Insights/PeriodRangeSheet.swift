import GoldaCore
import SwiftUI

/// The dates of a period of your own: from and to, each with its calendar. iOS has no range
/// calendar, and two dates with a calendar each is how Calendar's own start and end read. "Готово"
/// takes the range, "Отмена" leaves the screen as it was.
struct PeriodRangeSheet: View {
    let zone: TimeZone
    var onCancel: () -> Void
    var onDone: (Period) -> Void

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var draft: PeriodRangeDraft

    init(period: Period, zone: TimeZone, onCancel: @escaping () -> Void, onDone: @escaping (Period) -> Void) {
        self.zone = zone
        self.onCancel = onCancel
        self.onDone = onDone
        _draft = State(initialValue: PeriodRangeDraft(period))
    }

    private static let done = LocalizedStringResource("Done", table: "Insights", comment: "Button that takes the picked period.")

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker(selection: day(\.from, set: { draft.setFrom($0) }), displayedComponents: .date) {
                        Text("From", tableName: "Insights", comment: "Insights, custom period: the first day.")
                    }
                    .accessibilityIdentifier("insights.range.from")
                    DatePicker(selection: day(\.to, set: { draft.setTo($0) }), displayedComponents: .date) {
                        Text("To", tableName: "Insights", comment: "Insights, custom period: the last day.")
                    }
                    .accessibilityIdentifier("insights.range.to")
                }
                .listRowBackground(Theme.Color.card)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.Color.page)
            // The pickers show days in the books' zone, the zone a day is turned back with.
            .environment(\.timeZone, zone)
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
    }

    /// A day as the picker's midnight in the books' zone, and back.
    private func day(_ keyPath: KeyPath<PeriodRangeDraft, LocalDate>, set: @escaping (LocalDate) -> Void) -> Binding<Date> {
        let zone = zone
        return Binding(
            get: { Date(timeIntervalSince1970: Double(draft[keyPath: keyPath].startOfDayMillis(in: zone)) / 1000) },
            set: { set(LocalDate(epochMillis: Int64(($0.timeIntervalSince1970 * 1000).rounded(.down)), in: zone)) }
        )
    }
}
