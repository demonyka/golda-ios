import GoldaCore
import OSLog
import SwiftUI

private let log = Logger(subsystem: "com.f4studio.golda", category: "Accounts")

/// An account by its id: the page pushed for it, or the account the reconcile sheet is open for.
struct AccountRoute: Hashable, Identifiable {
    let accountId: UUID
    var id: UUID { accountId }
}

/// Accounts of the open profile: the total as the hero, then the accounts in their sections with
/// "+ Счёт" at the end. A row opens the account's page.
///
/// In reconcile mode (the Sunday reminder opens it) each row offers "Сходится" instead, and a tap
/// on the row opens the reconcile sheet; once every account is checked the screen says so, and
/// [onAllReconciled] ends the mode.
struct AccountsScreen: View {
    let data: AppData
    let today: LocalDate
    var reconcileMode = false
    /// The account form, empty.
    var onAddAccount: () -> Void
    /// The account form for an account, from its page's toolbar.
    var onEditAccount: (Account) -> Void
    /// The operation form, from an account's page.
    var onEditOperation: (OperationFull) -> Void = { _ in }
    var onAllReconciled: () -> Void = {}

    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.showUndoToast) private var showUndoToast
    @State private var round = ReconcileRound()
    @State private var reconciling: AccountRoute?
    /// Counts finished rounds, so each one is felt once.
    @State private var finishedRounds = 0

    var body: some View {
        let content = AccountsContent(data: data, today: today)
        List {
            Section {
                AccountsHeroView(hero: content.hero)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            if reconcileMode {
                Section {
                    reconcileHint
                        .listRowInsets(EdgeInsets(top: 0, leading: Theme.Gap.l, bottom: 0, trailing: Theme.Gap.l))
                        .listRowBackground(Color.clear)
                }
            }
            ForEach(content.sections) { section in
                Section {
                    ForEach(section.rows) { row in
                        accountRow(row)
                            .listRowBackground(Theme.Color.card)
                    }
                    if content.addRowJoinsLastSection, section.id == content.sections.last?.id {
                        addRow
                    }
                } header: {
                    if let label = section.label {
                        Text(verbatim: label.keepingMarksOnTheLine)
                            .fixedSize(horizontal: false, vertical: true)
                            .font(.subheadline.weight(.medium))
                            .tabularDigits()
                            .foregroundStyle(Theme.Color.muted)
                            .textCase(nil)
                    }
                }
            }
            if !content.addRowJoinsLastSection {
                Section { addRow }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.Color.page)
        .animation(.snappy, value: content.sections)
        .navigationDestination(for: AccountRoute.self) { route in
            AccountPage(
                data: data, accountId: route.accountId, today: today,
                onEditAccount: onEditAccount, onEditOperation: onEditOperation
            )
        }
        .sheet(item: $reconciling) { route in
            if let state = data.states[route.accountId] {
                ReconcileSheet(state: state) { actual in reconcile(state, actualMinor: actual) }
            }
        }
        .sensoryFeedback(.success, trigger: finishedRounds)
        // A new round each time the mode opens.
        .onChange(of: reconcileMode) { round = ReconcileRound() }
    }

    // MARK: Rows

    @ViewBuilder private func accountRow(_ row: AccountRowModel) -> some View {
        if reconcileMode {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Gap.s))
                : AnyLayout(HStackLayout(spacing: Theme.Gap.s))
            layout {
                // Two buttons in one row: each answers only to its own frame.
                Button {
                    reconciling = AccountRoute(accountId: row.id)
                } label: {
                    AccountRowView(row: row)
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text(verbatim: Self.reconcileRowHint.text(in: locale)))
                .accessibilityIdentifier("accounts.account")
                ReconcileMark(isChecked: round.isChecked(row.id)) {
                    reconcile(row.state, actualMinor: row.state.balanceMinor)
                }
            }
        } else {
            NavigationLink(value: AccountRoute(accountId: row.id)) {
                AccountRowView(row: row)
            }
            .accessibilityIdentifier("accounts.account")
        }
    }

    /// "+ Счёт" in the system blue, as an action row of an iOS list reads (D34).
    private var addRow: some View {
        Button(action: onAddAccount) {
            HStack(spacing: Theme.Gap.m) {
                Image(systemName: Symbols.add)
                Text(verbatim: Self.addTitle.text(in: locale))
            }
            .font(.body.weight(.medium))
            .foregroundStyle(.tint)
            .frame(maxWidth: .infinity, minHeight: Theme.minimumTarget, alignment: .leading)
            .contentShape(.rect)
        }
        .listRowBackground(Theme.Color.card)
        .accessibilityLabel(Text(verbatim: Self.addLabel.text(in: locale)))
        .accessibilityIdentifier("accounts.add")
    }

    private var reconcileHint: some View {
        VStack(alignment: .leading, spacing: Theme.Gap.xs) {
            Text(verbatim: Self.reconcileTitle.text(in: locale))
                .font(.headline)
                .foregroundStyle(Theme.Color.text)
            Text(verbatim: Self.reconcileHint.text(in: locale))
                .font(.subheadline)
                .foregroundStyle(Theme.Color.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("accounts.reconcileHint")
    }

    // MARK: Reconciling

    /// Brings the account to [actualMinor]. In reconcile mode the account is ticked off, and the
    /// last one finishes the round: a success tap, a toast, and the mode ends.
    private func reconcile(_ state: AccountState, actualMinor: Int64) {
        let accountId = state.account.id
        Task {
            do {
                try await model.reconcile(accountId: accountId, actualMinor: actualMinor)
            } catch {
                log.error("Reconciling an account failed: \(String(describing: error))")
            }
        }
        guard reconcileMode else { return }
        round.check(accountId, matched: actualMinor == state.balanceMinor)
        guard round.isComplete(data.accounts) else { return }
        finishedRounds += 1
        showUndoToast(UndoToast(Self.allReconciled.text(in: locale), actionTitle: Self.okTitle.text(in: locale)) {})
        onAllReconciled()
    }

    // MARK: Text

    static let addTitle = LocalizedStringResource("Account", comment: "Accounts: the last row, “+ Account”, opens the form for a new account.")
    static let addLabel = LocalizedStringResource("Add account", comment: "VoiceOver: the “+ Account” row.")
    static let reconcileTitle = LocalizedStringResource("Reconciling", comment: "Accounts in reconcile mode: the heading over the hint.")
    static let reconcileHint = LocalizedStringResource(
        "Matches the bank: “Matches”. Doesn’t: tap the account.",
        comment: "Accounts in reconcile mode: how to check each account against the bank."
    )
    static let reconcileRowHint = LocalizedStringResource(
        "Type what the bank shows",
        comment: "VoiceOver hint, reconcile mode: tapping an account opens the sheet to enter its real balance."
    )
    static let allReconciled = LocalizedStringResource("All accounts reconciled", comment: "Toast after the last account of a reconcile round was checked.")
    static let okTitle = LocalizedStringResource("OK", comment: "The toast's button that only closes it.")
}

/// The hero of Accounts: the caption, the total in the main currency as the big number, the other
/// currencies, and the advice on debts.
struct AccountsHeroView: View {
    let hero: AccountsHero

    @Environment(\.locale) private var locale

    var body: some View {
        HeroCard {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: AccountsHero.caption.text(in: locale))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                BigNumber(minor: hero.totalMinor, currency: hero.currency)
                    .padding(.top, Theme.Gap.xs)
                if !hero.others.isEmpty {
                    Text(verbatim: ("≈ " + hero.others).keepingMarksOnTheLine)
                        .font(.body)
                        .tabularDigits()
                        .foregroundStyle(.secondary)
                }
                if let advice = hero.adviceText(in: locale) {
                    Text(verbatim: advice)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Theme.Gap.m)
                }
            }
        }
        // One stop for VoiceOver: the whole card as a sentence, amounts in words.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: hero.accessibilityLabel(in: locale)))
        .accessibilityIdentifier("accounts.hero")
    }
}

extension String {
    /// "Карта · ≈ 5 298 117 ₽" with no-break spaces before each dot and after each "≈", so a line
    /// that wraps never starts with a dot nor ends with a lone "≈".
    var keepingMarksOnTheLine: String {
        replacingOccurrences(of: " · ", with: "\u{00A0}· ").replacingOccurrences(of: "≈ ", with: "≈\u{00A0}")
    }
}

// MARK: - Previews

#Preview("Samples") {
    @Previewable @State var model = AppModel.preview()
    NavigationStack {
        if let data = model.data {
            AccountsScreen(data: data, today: model.environment.today(), onAddAccount: {}, onEditAccount: { _ in })
                .navigationTitle(Text(AppTab.accounts.title))
        }
    }
    .environment(model)
    .task { await model.start(command: .samples) }
}

#Preview("Reconcile mode, dark, Russian") {
    @Previewable @State var model = AppModel.preview()
    NavigationStack {
        if let data = model.data {
            AccountsScreen(data: data, today: model.environment.today(), reconcileMode: true, onAddAccount: {}, onEditAccount: { _ in })
                .navigationTitle(Text(AppTab.accounts.title))
        }
    }
    .environment(model)
    .environment(\.locale, Locale(identifier: "ru"))
    .preferredColorScheme(.dark)
    .task { await model.start(command: .samples) }
}
