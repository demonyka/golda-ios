import GoldaCore
import GoldaData
import SwiftUI

// The small sheets of a profile's screen, one value each, the iOS side of Android's `RateSheet`,
// `TaxHoursSheet`, the markup's `NumberSheet` and the payday's `PickSheet`. "Отмена" on the left and
// the confirmation in the system blue on the right (D34). Each hands its change to [onSave] as a
// function of the settings, which the screen applies to the profile as it is when saving.

/// A change to a profile's settings; nil leaves them as they are.
typealias ProfileSettingsChange = @MainActor (ProfileSettings) -> ProfileSettings?

/// "Ставка" or "Зарплата": hourly or monthly, and the amount before tax as the big number.
struct RateSheet: View {
    var onSave: (@escaping ProfileSettingsChange) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var form: IncomeRateForm
    @State private var isAmountFocused = true

    init(settings: ProfileSettings, onSave: @escaping (@escaping ProfileSettingsChange) -> Void) {
        self.onSave = onSave
        _form = State(initialValue: IncomeRateForm(settings))
    }

    var body: some View {
        ProfileSheetFrame(title: ProfileIncome.rateTitle(hourly: form.isHourly), canSave: form.canSave, identifier: "rateSheet", save: save) {
            Section {
                Picker(selection: $form.isHourly) {
                    Text(verbatim: IncomeRateForm.hourlyTitle.text(in: locale)).tag(true)
                    Text(verbatim: IncomeRateForm.monthlyTitle.text(in: locale)).tag(false)
                } label: {
                    Text(verbatim: ProfileIncome.title.text(in: locale))
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("rateSheet.kind")
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            Section {
                BigAmountInput(
                    text: $form.text, symbol: Currencies.symbol("RUB"), isInvalid: form.isInvalid,
                    isFocused: $isAmountFocused, label: form.caption.text(in: locale), identifier: "rateSheet.amount"
                )
                .listRowBackground(Theme.Color.card)
            } footer: {
                Text(verbatim: form.caption.text(in: locale))
            }
        }
    }

    private func save() {
        let form = form
        onSave { form.applied(to: $0) }
        dismiss()
    }
}

/// Tax and hours a week, two short numbers.
struct TaxHoursSheet: View {
    var onSave: (@escaping ProfileSettingsChange) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var form: TaxHoursForm
    @FocusState private var focus: TaxHoursForm.Field?

    init(settings: ProfileSettings, onSave: @escaping (@escaping ProfileSettingsChange) -> Void) {
        self.onSave = onSave
        _form = State(initialValue: TaxHoursForm(settings))
    }

    var body: some View {
        ProfileSheetFrame(title: ProfileIncome.taxHoursTitle, canSave: form.canSave, identifier: "taxHoursSheet", save: save) {
            Section {
                numberRow(
                    title: TaxHoursForm.taxTitle, text: $form.taxText, unit: "%", field: .tax, identifier: "taxHoursSheet.tax"
                )
                numberRow(
                    title: TaxHoursForm.hoursTitle, text: $form.hoursText, unit: TaxHoursForm.hoursUnit.text(in: locale),
                    field: .hours, identifier: "taxHoursSheet.hours"
                )
            }
            .listRowBackground(Theme.Color.card)
        }
        .onAppear { focus = .tax }
    }

    /// The title on the left and the number on the right with its unit; at the accessibility sizes
    /// the number goes under the title, as in the account form.
    private func numberRow(
        title: LocalizedStringResource, text: Binding<String>, unit: String, field: TaxHoursForm.Field, identifier: String
    ) -> some View {
        let title = title.text(in: locale)
        let number = HStack(spacing: Theme.Gap.xs) {
            TextField(text: text, prompt: Text(verbatim: "0")) {
                Text(verbatim: title)
            }
            .keyboardType(.decimalPad)
            .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
            .tabularDigits()
            .foregroundStyle(form.invalidFields.contains(field) ? Theme.Color.danger : Theme.Color.text)
            .focused($focus, equals: field)
            .accessibilityIdentifier(identifier)
            Text(verbatim: unit)
                .foregroundStyle(Theme.Color.muted)
                .accessibilityHidden(true)
        }
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Theme.Gap.xs) {
                    Text(verbatim: title)
                    number
                }
            } else {
                HStack(spacing: Theme.Gap.s) {
                    Text(verbatim: title)
                        .lineLimit(1)
                        .layoutPriority(1)
                    number
                }
            }
        }
    }

    private func save() {
        let form = form
        onSave { form.applied(to: $0) }
        dismiss()
    }
}

/// The markup over the CBR rate, in percent, as the big number.
struct MarkupSheet: View {
    var onSave: (@escaping ProfileSettingsChange) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var form: MarkupForm
    @State private var isFocused = true

    init(markup: Double, onSave: @escaping (@escaping ProfileSettingsChange) -> Void) {
        self.onSave = onSave
        _form = State(initialValue: MarkupForm(markup: markup))
    }

    var body: some View {
        ProfileSheetFrame(title: MarkupForm.title, canSave: form.canSave, identifier: "markupSheet", save: save) {
            Section {
                BigAmountInput(
                    text: $form.text, symbol: "%", isInvalid: form.isInvalid, isFocused: $isFocused,
                    label: MarkupForm.caption.text(in: locale), identifier: "markupSheet.amount"
                )
                .listRowBackground(Theme.Color.card)
            } footer: {
                Text(verbatim: MarkupForm.note.text(in: locale))
            }
        }
    }

    private func save() {
        let form = form
        onSave { form.applied(to: $0) }
        dismiss()
    }
}

/// Payday as a grid of days: one tap picks it and closes the sheet, as on Android, so it needs no
/// confirmation.
struct PaydaySheet: View {
    let payday: Int
    var onSave: (@escaping ProfileSettingsChange) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    var body: some View {
        ProfileSheetFrame(title: ProfileIncome.paydayTitle, canSave: nil, identifier: "paydaySheet", save: {}) {
            Section {
                DayGrid(selected: payday) { day in
                    onSave { settings in
                        var settings = settings
                        settings.payday = day
                        return settings
                    }
                    dismiss()
                }
                .listRowInsets(EdgeInsets(top: Theme.Gap.s, leading: Theme.Gap.s, bottom: Theme.Gap.s, trailing: Theme.Gap.s))
                .listRowBackground(Theme.Color.card)
            } footer: {
                Text("A month without that day pays on its last day.", tableName: "Profiles", comment: "Payday sheet: what happens to the 31st in a shorter month.")
            }
        }
    }
}

/// What every one of these sheets shares: a form on the page colour in a navigation bar with
/// "Отмена" and, when [canSave] is given, the blue confirmation.
struct ProfileSheetFrame<Content: View>: View {
    let title: LocalizedStringResource
    /// Nil for a sheet whose one tap saves.
    let canSave: Bool?
    let identifier: String
    var save: () -> Void
    @ViewBuilder var content: Content

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    var body: some View {
        NavigationStack {
            Form {
                content
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Color.page)
            .scrollDismissesKeyboard(.never)
            .navigationTitle(Text(verbatim: title.text(in: locale)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel", tableName: "Profiles", comment: "Closes an alert or a sheet without changes.")
                    }
                    .accessibilityIdentifier("\(identifier).cancel")
                }
                if let canSave {
                    ToolbarItem(placement: .confirmationAction) {
                        ConfirmButton(title: ProfileSheetFrame.saveTitle.text(in: locale), action: save)
                            .disabled(!canSave)
                            .accessibilityIdentifier("\(identifier).save")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.Color.page)
    }
}

extension ProfileSheetFrame {
    static var saveTitle: LocalizedStringResource {
        LocalizedStringResource("Save", table: "Profiles", comment: "Sheets of the profile screen: the main action that saves the change.")
    }
}
