import GoldaCore
import SwiftUI

/// A day on the calendar, in a small sheet of its own: a popover from a control at the edge of the
/// screen cut the calendar off, and a sheet always has room for it. A picked day closes the sheet;
/// the confirmation closes it keeping the day shown. The operation form's day and the ends of a
/// period of your own open it.
struct DayCalendarSheet: View {
    let title: String
    @Binding var date: LocalDate
    /// The books' zone: the calendar shows its days, and a picked day is turned back with it.
    let zone: TimeZone
    let doneTitle: String
    /// "entry.date": the calendar is then "entry.datePicker" and the confirmation "entry.date.done".
    let identifier: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                DatePicker(selection: day, displayedComponents: .date) {
                    Text(verbatim: title)
                }
                .datePickerStyle(.graphical)
                .environment(\.timeZone, zone)
                .padding(.horizontal, Theme.Gap.m)
                .accessibilityIdentifier(identifier + "Picker")
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle(Text(verbatim: title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // A picked day closes the calendar; keeping the day shown needs a way back too.
                ToolbarItem(placement: .confirmationAction) {
                    ConfirmButton(title: doneTitle) { dismiss() }
                        .accessibilityIdentifier(identifier + ".done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.Color.page)
    }

    /// The day as the picker's midnight in the books' zone, and back; a picked day closes the calendar.
    private var day: Binding<Date> {
        let zone = zone
        return Binding(
            get: { Date(timeIntervalSince1970: Double(date.startOfDayMillis(in: zone)) / 1000) },
            set: {
                let picked = LocalDate(epochMillis: Int64(($0.timeIntervalSince1970 * 1000).rounded(.down)), in: zone)
                if picked != date {
                    date = picked
                    dismiss()
                }
            }
        )
    }
}
