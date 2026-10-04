import GoldaCore
import SwiftUI

/// The account form, for a new account or for [editing] one: the port of Android's `AccountSheet`
/// as an iOS form sheet. "Отмена" on the left; on the right the trash when editing and the
/// confirmation, "Добавить" or "Сохранить", in the system blue (D34). The name and currency come
/// first, then the type, how much is there for a new account, what a savings account or a debt
/// needs, the group and whether it counts in "Можно сегодня". The rules live in `AccountFormModel`.
///
/// Present it with `.sheet`; it sets its own detent. Saving and deleting go through the `AppModel`
/// in the environment, to the profile on screen; [onDismiss] closes the sheet after either, and
/// [onDeleted] also runs once the account is gone, so a page that showed it can close.
struct AccountFormSheet: View {
    let data: AppData
    var onDismiss: () -> Void
    var onDeleted: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var form: AccountFormModel
    @State private var isBusy = false
    @State private var isConfirmingDelete = false
    @State private var isPickingGraceEnd = false
    @State private var failure: Failure?
    @FocusState private var focus: Focus?
    /// The big amount field is a UIKit one, so its focus is a flag of its own.
    @State private var isOpeningFocused = false

    private enum Focus: Hashable {
        case name, rate, payment, group
    }

    private enum Failure {
        case save, delete
    }

    init(data: AppData, editing: Account?, onDismiss: @escaping () -> Void, onDeleted: @escaping () -> Void = {}) {
        self.data = data
        self.onDismiss = onDismiss
        self.onDeleted = onDeleted
        _form = State(initialValue: AccountFormModel(data: data, editing: editing))
    }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                typeSection
                if form.isNew { openingSection }
                if form.hasRate { termsSection }
                groupSection
                budgetSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Color.page)
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle(Text(verbatim: form.title.text(in: locale)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.Color.page)
        .alert(
            Text(verbatim: failure.map(failureText) ?? ""),
            isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
        ) {
            Button(role: .cancel) {} label: {
                Text("OK", tableName: "AccountForm", comment: "Closes the message that saving or deleting failed.")
            }
        }
        .onAppear {
            // A new account starts with its name; an existing one opens to be looked over.
            if form.isNew { focus = .name }
        }
    }

    // MARK: Sections

    private var nameSection: some View {
        Section {
            TextField(text: $form.name, prompt: Text("Name", tableName: "AccountForm", comment: "Account form: the placeholder of the account's name.")) {
                Text("Name", tableName: "AccountForm")
            }
            .font(.title3.weight(.semibold))
            .textInputAutocapitalization(.sentences)
            .submitLabel(.done)
            .focused($focus, equals: .name)
            // A field with a prompt hides its label from VoiceOver: once named, it read only "Карта ₽".
            .accessibilityLabel(Text("Name", tableName: "AccountForm"))
            .accessibilityIdentifier("accountForm.name")
            currencyRow
        } footer: {
            if !form.isNew {
                Text("An account keeps the currency it was opened in.", tableName: "AccountForm", comment: "Account form, editing: why the currency cannot be changed.")
            }
        }
        .listRowBackground(Theme.Color.card)
    }

    @ViewBuilder private var currencyRow: some View {
        let title = Text("Currency", tableName: "AccountForm", comment: "Account form: the account's currency.")
        if form.isNew {
            Picker(selection: Binding(get: { form.currency }, set: { form.pickCurrency($0) })) {
                ForEach(form.preferredCurrencies, id: \.self) { code in
                    Text(verbatim: AccountFormModel.currencyLabel(code)).tag(code)
                }
                Section {
                    ForEach(form.otherCurrencies, id: \.self) { code in
                        Text(verbatim: AccountFormModel.currencyLabel(code)).tag(code)
                    }
                }
            } label: {
                title
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("accountForm.currency")
        } else {
            LabeledContent {
                Text(verbatim: AccountFormModel.currencyLabel(form.currency))
            } label: {
                title
            }
            .accessibilityIdentifier("accountForm.currency")
        }
    }

    private var typeSection: some View {
        Section {
            AccountTypeTiles(selection: $form.type)
                .listRowInsets(EdgeInsets(top: Theme.Gap.s, leading: Theme.Gap.s, bottom: Theme.Gap.s, trailing: Theme.Gap.s))
        } header: {
            Text("Type", tableName: "AccountForm", comment: "Account form: the header over the account type tiles.")
        }
        .listRowBackground(Theme.Color.card)
    }

    private var openingSection: some View {
        Section {
            BigAmountInput(
                text: $form.openingText, symbol: Currencies.symbol(form.currency),
                isInvalid: form.invalidFields.contains(.opening), isFocused: $isOpeningFocused,
                label: form.openingCaption.text(in: locale), identifier: "accountForm.opening"
            )
        } header: {
            Text(verbatim: form.openingCaption.text(in: locale))
        }
        .listRowBackground(Theme.Color.card)
    }

    private var termsSection: some View {
        Section {
            numberRow(
                title: form.rateTitle, text: $form.rateText,
                // The percent sign stays out of the catalog, where it would read as a format.
                suffix: Text(verbatim: "% " + LocalizedStringResource("p.a.", table: "AccountForm", comment: "Account form: “per year” after a yearly interest rate.").text(in: locale)),
                invalid: form.invalidFields.contains(.rate), focus: .rate, identifier: "accountForm.rate"
            )
            if form.isDebt {
                numberRow(
                    title: form.paymentTitle, text: $form.paymentText, suffix: Text(verbatim: Currencies.symbol(form.currency)),
                    invalid: form.invalidFields.contains(.payment), focus: .payment, identifier: "accountForm.payment"
                )
                Picker(selection: $form.paymentDay) {
                    Text("Not set", tableName: "AccountForm", comment: "Account form: no payment day picked.").tag(Int?.none)
                    ForEach(1...31, id: \.self) { day in
                        Text(verbatim: "\(day)").tag(Int?.some(day))
                    }
                } label: {
                    Text("Payment day", tableName: "AccountForm", comment: "Account form: the day of the month a debt's payment is due.")
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("accountForm.paymentDay")
            }
            if form.hasGracePeriod {
                Toggle(isOn: Binding(get: { form.graceUntil != nil }, set: { form.setGracePeriod($0, today: model.environment.today()) })) {
                    Text("Interest-free period", tableName: "AccountForm", comment: "Account form: a credit card's grace period switch.")
                }
                .accessibilityIdentifier("accountForm.grace")
                if let until = form.graceUntil {
                    DateRowButton(title: Self.graceUntil.text(in: locale), date: InsightsDates.full(until, in: locale)) {
                        isPickingGraceEnd = true
                    }
                    .accessibilityIdentifier("accountForm.graceUntil")
                    .sheet(isPresented: $isPickingGraceEnd) {
                        DayCalendarSheet(
                            title: Self.graceUntil.text(in: locale), date: graceDay(until), zone: data.zone,
                            doneTitle: Self.done.text(in: locale), identifier: "accountForm.graceUntil"
                        )
                    }
                }
            }
        }
        .listRowBackground(Theme.Color.card)
    }

    private var groupSection: some View {
        Section {
            if !form.existingGroups.isEmpty {
                Picker(selection: $form.groupChoice) {
                    Text("No group", tableName: "AccountForm", comment: "Account form: the account stands on its own.")
                        .tag(AccountFormModel.GroupChoice.none)
                    ForEach(form.existingGroups, id: \.self) { group in
                        Text(verbatim: group).tag(AccountFormModel.GroupChoice.existing(group))
                    }
                    Text("New group…", tableName: "AccountForm", comment: "Account form: type the name of a new group.")
                        .tag(AccountFormModel.GroupChoice.new)
                } label: {
                    Text("Group", tableName: "AccountForm", comment: "Account form: the group of a bank's accounts.")
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("accountForm.group")
            }
            if form.groupChoice == .new {
                TextField(
                    text: $form.newGroupName,
                    prompt: Text("Group, like the bank's name", tableName: "AccountForm", comment: "Account form: the placeholder of a new group's name.")
                ) {
                    Text("Group", tableName: "AccountForm")
                }
                .submitLabel(.done)
                .focused($focus, equals: .group)
                // A field with a prompt hides its label from VoiceOver.
                .accessibilityLabel(Text("Group", tableName: "AccountForm"))
                .accessibilityIdentifier("accountForm.newGroup")
            }
        } footer: {
            Text("A bank's accounts stand together.", tableName: "AccountForm", comment: "Account form: what a group is for.")
        }
        .listRowBackground(Theme.Color.card)
    }

    private var budgetSection: some View {
        Section {
            Toggle(isOn: $form.includeInFree) {
                Text("Count in “Safe to spend today”", tableName: "AccountForm", comment: "Account form: the switch that puts the account's money into today's budget.")
            }
            .accessibilityIdentifier("accountForm.includeInFree")
        } footer: {
            Text("Savings and debts usually stay out.", tableName: "AccountForm", comment: "Account form: why savings and debts start with the budget switch off.")
        }
        .listRowBackground(Theme.Color.card)
    }

    /// A short number on the right of its row, with its unit after it. The title keeps its whole
    /// width ("Минимальный платёж" is long); at the accessibility sizes the number goes under it.
    private func numberRow(
        title: LocalizedStringResource, text: Binding<String>, suffix: Text, invalid: Bool, focus field: Focus, identifier: String
    ) -> some View {
        let title = title.text(in: locale)
        let number = HStack(spacing: Theme.Gap.xs) {
            TextField(text: text, prompt: Text(verbatim: "0")) {
                Text(verbatim: title)
            }
            .keyboardType(.decimalPad)
            .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
            .monospacedDigit()
            .foregroundStyle(invalid ? Theme.Color.danger : Theme.Color.text)
            .focused($focus, equals: field)
            // The field carries the title for VoiceOver, which otherwise heard a bare "0".
            .accessibilityLabel(Text(verbatim: title))
            .accessibilityIdentifier(identifier)
            suffix
                .foregroundStyle(Theme.Color.muted)
                .accessibilityHidden(true)
        }
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Theme.Gap.xs) {
                    Text(verbatim: title)
                        .accessibilityHidden(true)
                    number
                }
            } else {
                HStack(spacing: Theme.Gap.s) {
                    Text(verbatim: title)
                        .lineLimit(1)
                        .layoutPriority(1)
                        .accessibilityHidden(true)
                    number
                }
            }
        }
    }

    // MARK: Actions

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(action: onDismiss) {
                Text("Cancel", tableName: "AccountForm", comment: "Closes a form without saving.")
            }
            .accessibilityIdentifier("accountForm.cancel")
        }
        if !form.isNew {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Label {
                        Text("Delete account", tableName: "AccountForm", comment: "Account form: the trash button.")
                    } icon: {
                        Image(systemName: Symbols.delete)
                    }
                }
                .disabled(isBusy)
                .accessibilityIdentifier("accountForm.delete")
                // An alert, as Android's dialog, not a popover: at the largest text sizes a popover
                // from the toolbar squeezes the warning into a narrow column and cuts it.
                .alert(Text(verbatim: form.deleteQuestion(in: locale)), isPresented: $isConfirmingDelete) {
                    Button(role: .destructive, action: delete) {
                        Text("Delete", tableName: "AccountForm", comment: "Confirms deleting an account with its operations.")
                    }
                    Button(role: .cancel) {} label: {
                        Text("Cancel", tableName: "AccountForm")
                    }
                } message: {
                    Text(verbatim: AccountFormModel.deleteWarning.text(in: locale))
                }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            ConfirmButton(title: form.saveTitle.text(in: locale), action: save)
                .disabled(!canSave)
                .accessibilityIdentifier("accountForm.save")
        }
    }

    private var canSave: Bool { form.canSave && !isBusy }

    private func save() {
        guard let output = form.output, !isBusy else { return }
        isBusy = true
        Task {
            do {
                try await model.saveAccount(output.account, openingMinor: output.openingMinor)
                onDismiss()
            } catch {
                isBusy = false
                failure = .save
            }
        }
    }

    private func delete() {
        guard let id = form.editing?.id, !isBusy else { return }
        isBusy = true
        Task {
            do {
                try await model.deleteAccount(id)
                onDismiss()
                onDeleted()
            } catch {
                isBusy = false
                failure = .delete
            }
        }
    }

    // MARK: Helpers

    private static let graceUntil = LocalizedStringResource("Interest-free until", table: "AccountForm", comment: "Account form: the last day of a credit card's grace period.")
    private static let done = LocalizedStringResource("Done", table: "AccountForm", comment: "Closes a sheet over the account: the early repayment calculator, the grace period's calendar.")

    /// The last interest-free day; the calendar works in the books' zone (`DayCalendarSheet`).
    private func graceDay(_ until: LocalDate) -> Binding<LocalDate> {
        Binding(get: { form.graceUntil ?? until }, set: { form.graceUntil = $0 })
    }

    private func failureText(_ failure: Failure) -> String {
        switch failure {
        case .save:
            LocalizedStringResource("The account was not saved. Try again.", table: "AccountForm", comment: "Account form: saving failed.").text(in: locale)
        case .delete:
            LocalizedStringResource("The account was not deleted. Try again.", table: "AccountForm", comment: "Account form: deleting failed.").text(in: locale)
        }
    }
}

// MARK: - Previews

#Preview("New, samples") {
    @Previewable @State var model = AppModel.preview()
    Color.clear
        .sheet(isPresented: .constant(true)) {
            if let data = model.data {
                AccountFormSheet(data: data, editing: nil) {}
            }
        }
        .environment(model)
        .task { await model.start(command: .samples) }
}

#Preview("Editing the loan, dark, Russian") {
    @Previewable @State var model = AppModel.preview()
    Color.clear
        .sheet(isPresented: .constant(true)) {
            if let data = model.data {
                AccountFormSheet(data: data, editing: data.accounts.first { $0.type == .loan }) {}
            }
        }
        .environment(model)
        .environment(\.locale, Locale(identifier: "ru"))
        .preferredColorScheme(.dark)
        .task { await model.start(command: .samples) }
}
