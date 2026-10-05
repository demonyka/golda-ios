import GoldaCore
import SwiftUI

/// The operation form over the tabs: "+" opens it empty, an operation's row opens it with that
/// operation, and a purchase to decide on (voice "хочу купить", a waiting wish) opens it already
/// in "Сомневаюсь". Opening balances and reconciliation adjustments open the read-only
/// `BookkeepingSheet` instead.
struct EntrySheet: View {
    let data: AppData
    let request: EntryRequest

    @Environment(AppModel.self) private var model

    var body: some View {
        if EntryFormModel.isBookkeeping(request), let operation = request.editing {
            BookkeepingSheet(data: data, operation: operation, today: model.environment.today())
        } else {
            EntryForm(data: data, request: request, today: model.environment.today())
        }
    }
}

/// Manual entry and editing of expenses, income and transfers: the port of Android's `EntrySheet`
/// as an iOS form sheet. "Отмена" on the left; on the right the trash when editing and the
/// confirmation, "Записать" or "Сохранить", in the system blue (D34). A new expense has a second
/// state, "Сомневаюсь": the same amount stays on top and the form below turns into what the price
/// means, with "Не беру · Подумаю · Беру" at the bottom. The rules live in `EntryFormModel`.
///
/// Saving and deleting go through the `AppModel` in the environment, to the profile on screen;
/// what happened is reported in the undo toast of the tab under the sheet.
private struct EntryForm: View {
    let data: AppData
    let request: EntryRequest

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.showUndoToast) private var showUndoToast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var form: EntryFormModel
    /// What the price means, once the repository has worked it out.
    @State private var facts: Facts?
    /// The big amount is a UIKit field, so its focus is a flag of its own.
    @State private var isAmountFocused = false
    @FocusState private var focus: EntryFocus?
    @State private var isBusy = false
    @State private var failure: LocalizedStringResource?
    /// Bumped when an expense is recorded or a purchase skipped: the success tap.
    @State private var confirmations = 0

    init(data: AppData, request: EntryRequest, today: LocalDate) {
        self.data = data
        self.request = request
        _form = State(initialValue: EntryFormModel(data: data, request: request, today: today))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(.horizontal, Theme.Gap.m)
                    .padding(.bottom, Theme.Gap.l)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(Theme.Color.page)
            // A bar, not a bare inset: the form scrolls clear of it, and what passes under it fades
            // as under any iOS bar. At the accessibility sizes the stacked answers are a quarter of
            // the screen, and crisp text under them read as covered.
            .safeAreaBar(edge: .bottom) { bottomActions }
            .navigationTitle(Text(verbatim: title.text(in: locale)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.Color.page)
        .sensoryFeedback(.success, trigger: confirmations)
        .task(id: form.factsKey) { await loadFacts() }
        .onChange(of: focus) { old, new in
            // The second amount closes once the keyboard leaves it.
            if old == .second, new != .second { form.isEditingSecond = false }
        }
        .onAppear {
            // A new operation starts with its amount; an existing one or a purchase being weighed
            // up opens to be looked over.
            if form.isNew, request.consider == nil { isAmountFocused = true }
        }
        .alert(
            Text(verbatim: failure?.text(in: locale) ?? ""),
            isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
        ) {
            Button(role: .cancel) {} label: {
                Text(verbatim: EntryText.ok.text(in: locale))
            }
        }
    }

    private var title: LocalizedStringResource {
        if form.isDeciding { return EntryText.decidingTitle }
        return form.isNew ? EntryText.newTitle : EntryText.editTitle
    }

    // MARK: Content

    private var content: some View {
        VStack(spacing: 0) {
            // "Сомневаюсь" has no type: its way back is the toolbar.
            if !form.isDeciding {
                typePicker
                    .padding(.top, Theme.Gap.s)
                    .padding(.bottom, Theme.Gap.l)
                if form.type == .transfer {
                    EntryRouteTiles(
                        form: form,
                        onFrom: { form.pickAccount($0) },
                        onTo: { form.pickDestination($0) },
                        onSwap: { form.swapRoute() }
                    )
                    .padding(.bottom, Theme.Gap.l)
                }
            }
            EntryAmountField(
                text: $form.amountText,
                currency: form.amountCode,
                choices: form.picksCurrency ? form.currencyChoices : nil,
                onPick: { form.pickCurrency($0) },
                isInvalid: form.isAmountInvalid,
                isFocused: $isAmountFocused,
                label: EntryText.amount.text(in: locale),
                currencyLabel: EntryText.currency.text(in: locale)
            )
            EntryUnderLine(
                line: form.underLine,
                secondCode: form.secondCode,
                secondText: Binding(get: { form.secondText }, set: { form.typeSecond($0) }),
                isEditingSecond: $form.isEditingSecond,
                focus: $focus
            )
            .padding(.top, Theme.Gap.xs)
            Group {
                if form.isDeciding {
                    decidingSection
                } else if form.type == .transfer {
                    transferSection
                } else {
                    formSection
                }
            }
            .transition(.opacity)
        }
        .animation(reduceMotion ? nil : .snappy, value: form.isDeciding)
        .animation(reduceMotion ? nil : .snappy, value: form.type)
    }

    private var typePicker: some View {
        Picker(selection: Binding(get: { form.type }, set: { form.pickType($0) })) {
            ForEach([OpType.expense, .income, .transfer], id: \.self) { type in
                Text(verbatim: EntryText.typeTitle(type).text(in: locale)).tag(type)
            }
        } label: {
            Text(verbatim: EntryText.type.text(in: locale))
        }
        .pickerStyle(.segmented)
        // A segmented picker shows no label, and VoiceOver had none to read either.
        .accessibilityLabel(Text(verbatim: EntryText.type.text(in: locale)))
        .accessibilityIdentifier("entry.type")
    }

    /// An expense or income: what it was, the account and the day, then every category.
    private var formSection: some View {
        VStack(spacing: Theme.Gap.s) {
            noteField(EntryText.notePlaceholder(type: form.type, categoryKey: form.categoryKey, deciding: false))
            pills
            EntryCategoryGrid(categories: form.categories, selected: form.categoryKey) { form.pickCategory($0) }
                .padding(.top, Theme.Gap.m)
        }
        .padding(.top, Theme.Gap.l)
    }

    /// A transfer's accounts are in the tiles above; what is left is a note and the day.
    private var transferSection: some View {
        VStack(spacing: Theme.Gap.s) {
            noteField(EntryText.notePlaceholder(type: .transfer, categoryKey: nil, deciding: false))
            HStack {
                EntryDatePill(date: $form.date, today: form.today, zone: data.zone)
                Spacer(minLength: 0)
            }
        }
        .padding(.top, Theme.Gap.l)
    }

    private var decidingSection: some View {
        VStack(spacing: Theme.Gap.s) {
            EntryFactsBento(facts: form.facts(facts), isPriced: form.amount != nil)
            noteField(EntryText.notePlaceholder(type: .expense, categoryKey: nil, deciding: true))
        }
        .padding(.top, Theme.Gap.l)
    }

    /// The account and the day side by side when both fit whole; otherwise, as with a long name
    /// ("Мультивалютная GEL · ₾") or at the accessibility sizes, one under the other, so the
    /// account is never cut to "Мультив…я GEL".
    private var pills: some View {
        let account = EntryAccountPill(accounts: form.accounts, account: form.account) { form.pickAccount($0) }
        let day = EntryDatePill(date: $form.date, today: form.today, zone: data.zone)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Gap.s) {
                account.fixedSize(horizontal: true, vertical: false)
                day.fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: Theme.Gap.s) {
                // A name too long for a line of its own still gives way rather than overflow.
                account
                day.fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func noteField(_ placeholder: LocalizedStringResource) -> some View {
        TextField(text: $form.note, prompt: Text(verbatim: placeholder.text(in: locale)).foregroundStyle(Theme.Color.muted)) {
            Text(verbatim: placeholder.text(in: locale))
        }
        .font(.body)
        .textInputAutocapitalization(.sentences)
        .submitLabel(.done)
        .focused($focus, equals: .note)
        .onSubmit { if !form.isDeciding { save() } }
        // A field with a prompt hides its label from VoiceOver: once filled, it read only the note.
        .accessibilityLabel(Text(verbatim: EntryText.note.text(in: locale)))
        .accessibilityIdentifier("entry.note")
        .padding(.horizontal, Theme.Gap.m)
        .frame(minHeight: 52)
        .background(Theme.Color.card, in: RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous))
        // The whole card is the field: a tap on its padding still gives it the keyboard, and the
        // window's tap leaves the keyboard up for it.
        .contentShape(.rect)
        .onTapGesture { focus = .note }
        .keepsKeyboardOnTap()
    }

    // MARK: Actions

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if form.returnsToForm {
                Button {
                    form.isDeciding = false
                } label: {
                    Label {
                        Text(verbatim: EntryText.back.text(in: locale))
                    } icon: {
                        Image(systemName: "chevron.backward")
                    }
                }
                .accessibilityIdentifier("entry.back")
            } else {
                Button {
                    dismiss()
                } label: {
                    Text(verbatim: EntryText.cancel.text(in: locale))
                }
                .accessibilityIdentifier("entry.cancel")
            }
        }
        if !form.isNew, !form.isDeciding {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive, action: delete) {
                    Label {
                        Text(verbatim: EntryText.delete.text(in: locale))
                    } icon: {
                        Image(systemName: Symbols.delete)
                    }
                }
                .disabled(isBusy)
                .accessibilityIdentifier("entry.delete")
            }
        }
        if !form.isDeciding {
            ToolbarItem(placement: .confirmationAction) {
                ConfirmButton(title: (form.isNew ? EntryText.record : EntryText.save).text(in: locale), action: save)
                    .disabled(!form.isValid || isBusy)
                    .accessibilityIdentifier("entry.save")
            }
        }
    }

    /// Above the keyboard: "Сомневаюсь" under a new expense, the three answers in "Сомневаюсь".
    @ViewBuilder private var bottomActions: some View {
        if form.isDeciding {
            EntryDecideActions(
                enabled: consider != nil && !isBusy,
                wait: facts?.waitHours.map { EntryText.wait($0, in: locale) },
                withThink: form.offersThink,
                onSkip: skip,
                onThink: think,
                onBuy: buy
            )
            .padding(.horizontal, Theme.Gap.m)
            .padding(.bottom, Theme.Gap.s)
        } else if form.offersConsider {
            Button {
                isAmountFocused = false
                focus = nil
                form.isDeciding = true
            } label: {
                Text(verbatim: EntryText.notSure.text(in: locale))
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, minHeight: Theme.minimumTarget)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            // A bar over the form: past this size it would cover what it is about.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .disabled(form.amount == nil)
            .padding(.horizontal, Theme.Gap.m)
            .padding(.bottom, Theme.Gap.s)
            .accessibilityIdentifier("entry.consider")
        }
    }

    private var consider: Consider? {
        form.consider(
            categoryName: { CategoryName.resource($0).text(in: locale) },
            unnamed: EntryText.purchase.text(in: locale)
        )
    }

    private func save() {
        guard let draft = form.draft(now: model.environment.clock()) else { return }
        record(draft, wishId: nil)
    }

    /// "Беру": the expense as the form has it, and a waiting wish marked bought.
    private func buy() {
        guard let draft = form.purchaseDraft(now: model.environment.clock(), unnamed: EntryText.purchase.text(in: locale)) else { return }
        record(draft, wishId: request.wishId)
    }

    /// Writes [draft]; the sheet closes once it is in, and a new operation is announced with what
    /// it cost and "Отменить".
    private func record(_ draft: Draft, wishId: UUID?) {
        guard !isBusy else { return }
        isBusy = true
        let model = model, data = data, locale = locale, showUndoToast = showUndoToast
        Task {
            do {
                let saved = try await model.saveEntry(draft, wishId: wishId)
                if draft.id == nil, draft.type == .expense { confirmations += 1 }
                dismiss()
                guard draft.id == nil else { return }
                showUndoToast(UndoToast(
                    EntryAnnouncement.saved(draft, impact: saved.impact, data: data, in: locale),
                    actionTitle: EntryAnnouncement.undo.text(in: locale),
                    length: saved.impact == nil ? .short : .long
                ) {
                    Task { try? await model.undoEntry(saved) }
                })
            } catch {
                isBusy = false
                failure = EntryText.saveFailed
            }
        }
    }

    /// Gone at once, back with "Вернуть".
    private func delete() {
        guard let operation = request.editing, !isBusy else { return }
        isBusy = true
        let model = model, locale = locale, showUndoToast = showUndoToast
        Task {
            do {
                let token = try await model.deleteOperation(operation.op.id)
                dismiss()
                guard let token else { return }
                showUndoToast(UndoToast(
                    EntryAnnouncement.deleted(operation, in: locale),
                    actionTitle: EntryAnnouncement.restore.text(in: locale),
                    length: .long
                ) {
                    Task { try? await model.restoreOperation(token) }
                })
            } catch {
                isBusy = false
                failure = EntryText.deleteFailed
            }
        }
    }

    /// "Не беру": the money goes to the main goal, and the toast says how much.
    private func skip() {
        guard let consider, !isBusy else { return }
        isBusy = true
        confirmations += 1
        let model = model, locale = locale, showUndoToast = showUndoToast, wishId = request.wishId
        Task {
            do {
                let wish = try await model.skipPurchase(consider, wishId: wishId)
                dismiss()
                showUndoToast(UndoToast(EntryAnnouncement.skipped(wish, in: locale), actionTitle: EntryText.ok.text(in: locale), length: .long) {})
            } catch {
                isBusy = false
                failure = EntryText.decideFailed
            }
        }
    }

    /// "Подумаю": on the wishlist, and the toast says when to decide.
    private func think() {
        guard let consider, !isBusy else { return }
        isBusy = true
        let model = model, locale = locale, showUndoToast = showUndoToast
        Task {
            do {
                let wish = try await model.thinkAbout(consider)
                dismiss()
                showUndoToast(UndoToast(EntryAnnouncement.thinking(wish, in: locale), actionTitle: EntryText.ok.text(in: locale)) {})
            } catch {
                isBusy = false
                failure = EntryText.decideFailed
            }
        }
    }

    /// The facts for the price on screen, after the typing settles. Out of "Сомневаюсь", or with
    /// no price, there are none; a new price keeps the old facts on screen until its own arrive.
    private func loadFacts() async {
        guard form.isDeciding, let consider else {
            facts = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled else { return }
        do {
            let fresh = try await model.purchaseFacts(consider)
            if !Task.isCancelled { facts = fresh }
        } catch {
            // The dashes stay: the facts are a help, not something to stop the purchase for.
        }
    }
}

// MARK: - Previews

#Preview("New") {
    @Previewable @State var model = AppModel.preview()
    Color.clear
        .sheet(isPresented: .constant(true)) {
            if let data = model.data {
                EntrySheet(data: data, request: EntryRequest())
            }
        }
        .environment(model)
        .task { await model.start(command: .samples) }
}

#Preview("Not sure, dark, Russian") {
    @Previewable @State var model = AppModel.preview()
    Color.clear
        .sheet(isPresented: .constant(true)) {
            if let data = model.data {
                EntrySheet(data: data, request: EntryRequest(consider: Consider(title: "Велосипед", amountMinor: 8_000_000, currency: "RUB")))
            }
        }
        .environment(model)
        .environment(\.locale, Locale(identifier: "ru"))
        .preferredColorScheme(.dark)
        .task { await model.start(command: .samples) }
}
