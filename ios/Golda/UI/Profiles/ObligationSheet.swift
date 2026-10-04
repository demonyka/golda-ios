import GoldaCore
import SwiftUI

/// The payment form, for a new payment or for [editing] one: the port of Android's
/// `ObligationSheet` as an iOS form sheet. What it is, how much in which currency, and which day of
/// the month. "Отмена" on the left; on the right the trash when editing and "Добавить" or
/// "Сохранить" in the system blue (D34). The trash asks nothing: the screen offers "Отменить".
/// The rules live in `ObligationForm`.
struct ObligationSheet: View {
    var onSave: (Obligation) -> Void
    var onDelete: (Obligation) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var form: ObligationForm
    @FocusState private var isNameFocused: Bool
    /// The big amount field is a UIKit one, so its focus is a flag of its own.
    @State private var isAmountFocused = false

    init(editing: Obligation?, settings: Settings, onSave: @escaping (Obligation) -> Void, onDelete: @escaping (Obligation) -> Void) {
        self.onSave = onSave
        self.onDelete = onDelete
        _form = State(initialValue: ObligationForm(editing: editing, settings: settings))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(text: $form.name, prompt: Text(verbatim: ObligationForm.namePrompt.text(in: locale))) {
                        Text(verbatim: ObligationForm.namePrompt.text(in: locale))
                    }
                    .font(.title3.weight(.semibold))
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.next)
                    .focused($isNameFocused)
                    .onSubmit { isAmountFocused = true }
                    // A field with a prompt hides its label from VoiceOver: once filled, it read only the name.
                    .accessibilityLabel(Text(verbatim: ObligationForm.namePrompt.text(in: locale)))
                    .accessibilityIdentifier("obligationForm.name")
                }
                .listRowBackground(Theme.Color.card)

                Section {
                    BigAmountInput(
                        text: $form.amountText, symbol: Currencies.symbol(form.currency), isInvalid: form.isAmountInvalid,
                        isFocused: $isAmountFocused, label: ObligationForm.amountTitle.text(in: locale),
                        identifier: "obligationForm.amount"
                    )
                    currencyPicker
                }
                .listRowBackground(Theme.Color.card)

                Section {
                    DayGrid(selected: form.day) { form.day = $0 }
                        .listRowInsets(EdgeInsets(top: Theme.Gap.s, leading: Theme.Gap.s, bottom: Theme.Gap.s, trailing: Theme.Gap.s))
                } header: {
                    Text(verbatim: ObligationForm.dayTitle.text(in: locale))
                }
                .listRowBackground(Theme.Color.card)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Color.page)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(Text(verbatim: form.title.text(in: locale)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.Color.page)
        .onAppear {
            // A new payment starts with its name; an existing one opens to be looked over.
            if form.isNew { isNameFocused = true }
        }
    }

    private var currencyPicker: some View {
        Picker(selection: $form.currency) {
            ForEach(form.preferredCurrencies, id: \.self) { code in
                Text(verbatim: AccountFormModel.currencyLabel(code)).tag(code)
            }
            Section {
                ForEach(form.otherCurrencies, id: \.self) { code in
                    Text(verbatim: AccountFormModel.currencyLabel(code)).tag(code)
                }
            }
        } label: {
            Text(verbatim: ObligationForm.currencyTitle.text(in: locale))
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("obligationForm.currency")
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                dismiss()
            } label: {
                Text("Cancel", tableName: "Profiles", comment: "Closes an alert or a sheet without changes.")
            }
            .accessibilityIdentifier("obligationForm.cancel")
        }
        if let editing = form.editing {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    onDelete(editing)
                    dismiss()
                } label: {
                    Label {
                        Text(verbatim: ObligationForm.deleteTitle.text(in: locale))
                    } icon: {
                        Image(systemName: Symbols.delete)
                    }
                }
                .accessibilityIdentifier("obligationForm.delete")
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            ConfirmButton(title: form.saveTitle.text(in: locale)) {
                guard let output = form.output else { return }
                onSave(output)
                dismiss()
            }
            .disabled(!form.canSave)
            .accessibilityIdentifier("obligationForm.save")
        }
    }
}

#Preview("New, abroad") {
    Color.clear.sheet(isPresented: .constant(true)) {
        ObligationSheet(
            editing: nil, settings: Settings(displayCurrencies: ["RUB", "USD", "GEL"], localCurrency: "GEL"),
            onSave: { _ in }, onDelete: { _ in }
        )
    }
}

#Preview("Editing, dark, Russian") {
    Color.clear.sheet(isPresented: .constant(true)) {
        ObligationSheet(
            editing: Obligation(name: "Аренда", amountMinor: 90_000, currency: "GEL", dayOfMonth: 1),
            settings: Settings(displayCurrencies: ["RUB", "USD", "GEL"], localCurrency: "GEL"),
            onSave: { _ in }, onDelete: { _ in }
        )
    }
    .environment(\.locale, Locale(identifier: "ru"))
    .preferredColorScheme(.dark)
}
