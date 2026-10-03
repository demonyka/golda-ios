import GoldaCore
import SwiftUI

/// The goal form, for a new goal or for [editing] one: the port of Android's `GoalSheet` as an iOS
/// form sheet. "Отмена" on the left; on the right the trash when editing and the confirmation,
/// "Добавить" or "Сохранить", in the system blue (D34). The name, the amount and its currency, the
/// account it is saved on (or what is put aside without one), and the star that makes it the main
/// goal. The rules live in `GoalFormModel`.
///
/// Saving goes through the `AppModel` in the environment, to the profile on screen, and then
/// [onDismiss] closes the sheet. The trash hands the goal to [onDelete]: the screen under the sheet
/// deletes it and offers "Отменить", as Android's snackbar did, so there is no question first.
struct GoalFormSheet: View {
    let data: AppData
    var onDismiss: () -> Void
    var onDelete: (Goal) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var form: GoalFormModel
    @State private var isBusy = false
    @State private var failed = false
    @FocusState private var focus: Focus?
    /// The big amount field is a UIKit one, so its focus is a flag of its own.
    @State private var isTargetFocused = false

    private enum Focus: Hashable {
        case name, saved
    }

    init(data: AppData, editing: Goal?, onDismiss: @escaping () -> Void, onDelete: @escaping (Goal) -> Void) {
        self.data = data
        self.onDismiss = onDismiss
        self.onDelete = onDelete
        _form = State(initialValue: GoalFormModel(data: data, editing: editing))
    }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                targetSection
                accountSection
                mainSection
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
        .alert(Text(verbatim: GoalFormModel.saveFailed.text(in: locale)), isPresented: $failed) {
            Button(role: .cancel) {} label: { Text(verbatim: GoalFormModel.okTitle.text(in: locale)) }
        }
        .onAppear {
            // A new goal starts with its name; an existing one opens to be looked over.
            if form.isNew { focus = .name }
        }
    }

    // MARK: Sections

    private var nameSection: some View {
        Section {
            TextField(text: $form.name, prompt: Text(verbatim: GoalFormModel.namePrompt.text(in: locale))) {
                Text(verbatim: GoalFormModel.namePrompt.text(in: locale))
            }
            .font(.title3.weight(.semibold))
            .textInputAutocapitalization(.sentences)
            .submitLabel(.done)
            .focused($focus, equals: .name)
            .accessibilityIdentifier("goalForm.name")
        }
        .listRowBackground(Theme.Color.card)
    }

    private var targetSection: some View {
        Section {
            BigAmountInput(
                text: $form.targetText, symbol: Currencies.symbol(form.currency), isInvalid: form.isTargetInvalid,
                isFocused: $isTargetFocused, label: GoalFormModel.targetCaption.text(in: locale), identifier: "goalForm.target"
            )
            // The amount is centred; the line under it starts at the row's edge, not at the digits.
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
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
                Text(verbatim: GoalFormModel.currencyTitle.text(in: locale))
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("goalForm.currency")
        } header: {
            Text(verbatim: GoalFormModel.targetCaption.text(in: locale))
        }
        .listRowBackground(Theme.Color.card)
    }

    /// The account the money is kept on; without one, what is put aside by hand (and what refusals
    /// add) is the progress.
    private var accountSection: some View {
        Section {
            Picker(selection: $form.accountId) {
                Text(verbatim: GoalFormModel.noAccount.text(in: locale)).tag(UUID?.none)
                ForEach(form.accounts) { account in
                    Text(verbatim: account.name).tag(UUID?.some(account.id))
                }
            } label: {
                Text(verbatim: GoalFormModel.accountTitle.text(in: locale))
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("goalForm.account")
            if form.accountId == nil {
                savedRow
            }
        } footer: {
            if form.accountId != nil {
                Text(verbatim: GoalFormModel.accountFooter.text(in: locale))
            }
        }
        .listRowBackground(Theme.Color.card)
    }

    /// "Уже отложено" with the amount on the right; at the accessibility sizes the amount goes under it.
    private var savedRow: some View {
        let title = GoalFormModel.savedTitle.text(in: locale)
        let field = HStack(spacing: Theme.Gap.xs) {
            TextField(text: $form.savedText, prompt: Text(verbatim: "0")) {
                Text(verbatim: title)
            }
            .keyboardType(.decimalPad)
            .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
            .monospacedDigit()
            .foregroundStyle(form.isSavedInvalid ? Theme.Color.danger : Theme.Color.text)
            .focused($focus, equals: .saved)
            .accessibilityIdentifier("goalForm.saved")
            Text(verbatim: Currencies.symbol(form.currency))
                .foregroundStyle(Theme.Color.muted)
                .accessibilityHidden(true)
        }
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Theme.Gap.xs) {
                    Text(verbatim: title)
                    field
                }
            } else {
                HStack(spacing: Theme.Gap.s) {
                    Text(verbatim: title)
                        .lineLimit(1)
                        .layoutPriority(1)
                    field
                }
            }
        }
    }

    /// The star: on, the goal becomes the one purchases are held up against. The line under it says
    /// what that does to the others, since only one goal can be main.
    private var mainSection: some View {
        Section {
            Toggle(isOn: Binding(get: { form.willBeMain }, set: { form.isMain = $0 })) {
                Label {
                    Text(verbatim: GoalFormModel.mainTitle.text(in: locale))
                } icon: {
                    Image(systemName: form.willBeMain ? "star.fill" : "star")
                        // Graphite is what is picked.
                        .foregroundStyle(form.willBeMain ? Theme.Color.graphite : Theme.Color.muted)
                }
            }
            .disabled(form.isMainLocked)
            .accessibilityIdentifier("goalForm.main")
        } footer: {
            Text(verbatim: form.mainNoteText(in: locale))
                .accessibilityIdentifier("goalForm.mainNote")
        }
        .listRowBackground(Theme.Color.card)
    }

    // MARK: Actions

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(action: onDismiss) {
                Text(verbatim: GoalFormModel.cancelTitle.text(in: locale))
            }
            .accessibilityIdentifier("goalForm.cancel")
        }
        if let editing = form.editing {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    onDelete(editing)
                } label: {
                    Label {
                        Text(verbatim: GoalFormModel.deleteTitle.text(in: locale))
                    } icon: {
                        Image(systemName: Symbols.delete)
                    }
                }
                .disabled(isBusy)
                .accessibilityIdentifier("goalForm.delete")
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            ConfirmButton(title: form.saveTitle.text(in: locale), action: save)
                .disabled(!form.canSave || isBusy)
                .accessibilityIdentifier("goalForm.save")
        }
    }

    private func save() {
        guard let goal = form.output, !isBusy else { return }
        isBusy = true
        Task {
            do {
                try await model.saveGoal(goal)
                onDismiss()
            } catch {
                isBusy = false
                failed = true
            }
        }
    }
}

// MARK: - Previews

#Preview("New, samples") {
    @Previewable @State var model = AppModel.preview()
    Color.clear
        .sheet(isPresented: .constant(true)) {
            if let data = model.data {
                GoalFormSheet(data: data, editing: nil, onDismiss: {}, onDelete: { _ in })
            }
        }
        .environment(model)
        .task { await model.start(command: .samples) }
}

#Preview("Editing the cushion, dark, Russian") {
    @Previewable @State var model = AppModel.preview()
    Color.clear
        .sheet(isPresented: .constant(true)) {
            if let data = model.data {
                GoalFormSheet(data: data, editing: data.goals.last, onDismiss: {}, onDelete: { _ in })
            }
        }
        .environment(model)
        .environment(\.locale, Locale(identifier: "ru"))
        .preferredColorScheme(.dark)
        .task { await model.start(command: .samples) }
}
