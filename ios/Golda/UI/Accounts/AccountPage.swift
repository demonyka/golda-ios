import GoldaCore
import OSLog
import SwiftUI

private let log = Logger(subsystem: "com.f4studio.golda", category: "AccountPage")

/// An account's page, pushed from Accounts: the account's name as the large title, the balance as
/// the hero with what it is worth elsewhere, the rate it was bought at and its interest, a
/// "Сверить" action, the debt's details for a credit card or a loan, then the operations that
/// touched it by day, each with this account's own side. "Изменить" in the toolbar opens the form.
struct AccountPage: View {
    let data: AppData
    let accountId: UUID
    let today: LocalDate
    var onEditAccount: (Account) -> Void
    var onEditOperation: (OperationFull) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @State private var isReconciling = false

    var body: some View {
        if let page = AccountPageModel(data: data, accountId: accountId, today: today) {
            List {
                Section {
                    AccountPageHero(page: page) { isReconciling = true }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                DebtSectionSlot(state: page.state)
                OperationDaySections(days: page.days, rowIdentifier: "account.operation", onSelect: onEditOperation)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.Color.page)
            .animation(.snappy, value: page.days.map(\.rows))
            .navigationTitle(Text(verbatim: page.account.name))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        onEditAccount(page.account)
                    } label: {
                        Text(verbatim: Self.editTitle.text(in: locale))
                    }
                    .accessibilityIdentifier("account.edit")
                }
            }
            .sheet(isPresented: $isReconciling) {
                ReconcileSheet(state: page.state) { actual in reconcile(actualMinor: actual) }
            }
        } else {
            // The account went (deleted from its form, or by another device): back to the list.
            Theme.Color.page
                .ignoresSafeArea()
                .onAppear { dismiss() }
        }
    }

    private func reconcile(actualMinor: Int64) {
        let accountId = accountId
        Task {
            do {
                try await model.reconcile(accountId: accountId, actualMinor: actualMinor)
            } catch {
                log.error("Reconciling an account failed: \(String(describing: error))")
            }
        }
    }

    static let editTitle = LocalizedStringResource("Edit", comment: "Account page toolbar: opens the account's form.")
}

/// The account page's hero: the type and the bank, the balance with quiet cents, the other
/// currencies, the rate it was bought at and the month's interest, then "Сверить".
struct AccountPageHero: View {
    let page: AccountPageModel
    var onReconcile: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        HeroCard {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: page.caption(in: locale))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    BigNumber(
                        minor: page.state.balanceMinor, currency: page.state.currency, fraction: .automatic,
                        quietColor: Theme.Color.muted, maxSize: 72
                    )
                    .padding(.top, Theme.Gap.xs)
                    if !page.others.isEmpty {
                        Text(verbatim: "≈ " + page.others.keepingDotsOnTheLine)
                            .font(.body)
                            .tabularDigits()
                            .foregroundStyle(.secondary)
                    }
                    if let rate = page.purchaseRateText(in: locale) {
                        Text(verbatim: rate)
                            .font(.subheadline)
                            .tabularDigits()
                            .foregroundStyle(.secondary)
                            .padding(.top, Theme.Gap.xs)
                    }
                    if let interest = page.interest {
                        Text(verbatim: interest.text(in: locale))
                            .font(.subheadline)
                            .tabularDigits()
                            .foregroundStyle(.secondary)
                            .padding(.top, Theme.Gap.xs)
                    }
                }
                // The figures are one stop for VoiceOver; the button is its own.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: page.accessibilityLabel(in: locale)))
                .accessibilityIdentifier("account.hero")

                Button(action: onReconcile) {
                    Text(verbatim: Self.reconcileTitle.text(in: locale))
                }
                .buttonStyle(ReconcileButtonStyle())
                .padding(.top, Theme.Gap.m)
                .accessibilityIdentifier("account.reconcile")
            }
        }
    }

    static let reconcileTitle = LocalizedStringResource(
        "Reconcile",
        comment: "Account page: opens the sheet to check the balance against the bank."
    )
}

// MARK: - Previews

#Preview("Samples, a foreign card") {
    @Previewable @State var model = AppModel.preview()
    NavigationStack {
        if let data = model.data, let account = data.accounts.first(where: { $0.currency == "USD" }) {
            AccountPage(data: data, accountId: account.id, today: model.environment.today(), onEditAccount: { _ in }, onEditOperation: { _ in })
        }
    }
    .environment(model)
    .task { await model.start(command: .samples) }
}
