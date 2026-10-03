#if DEBUG
import GoldaCore
import SwiftUI

/// A screen a debug build opens in place of the tabs, asked for by a launch argument such as
/// `-golda.screen=accountForm`. It lets UI tests and screenshots reach views before the real entry
/// points are wired up. A release build has neither the argument nor the screens.
enum DebugScreen: String, Sendable {
    /// `AccountFormDebugHost`: the account form and the debt screens.
    case accountForm

    static let argumentPrefix = "-golda.screen="

    /// The screen [arguments] ask for; nil when none or an unknown one.
    static func requested(in arguments: [String] = ProcessInfo.processInfo.arguments) -> DebugScreen? {
        arguments.lazy
            .filter { $0.hasPrefix(argumentPrefix) }
            .compactMap { DebugScreen(rawValue: String($0.dropFirst(argumentPrefix.count))) }
            .first
    }
}

/// The profile's accounts, each opening the account form to edit it, "+" for a new one, and the
/// debts' terms with the early-repayment calculator. The Accounts tab brings the real entry points;
/// until then this is how the form is reached in UI tests and screenshots. Each row reads back
/// everything the form saves, so a test can see a change land in the model.
struct AccountFormDebugHost: View {
    let data: AppData

    @Environment(AppModel.self) private var model
    @State private var form: FormRequest?

    /// The form for an account, or for a new one.
    private struct FormRequest: Identifiable {
        let account: Account?

        var id: UUID? { account?.id }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(data.accounts) { account in
                        Button {
                            form = FormRequest(account: account)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: account.name).font(.body)
                                Text(verbatim: summary(account)).font(.footnote).foregroundStyle(Theme.Color.muted)
                            }
                        }
                        .foregroundStyle(Theme.Color.text)
                        .accessibilityLabel(Text(verbatim: account.name + " · " + summary(account)))
                        .accessibilityIdentifier("debugHost.account.\(account.name)")
                    }
                }
                Section {
                    ForEach(data.accounts.filter(\.isDebt)) { account in
                        NavigationLink {
                            DebtPage(accountId: account.id)
                        } label: {
                            Text(verbatim: account.name)
                        }
                        .accessibilityIdentifier("debugHost.debt.\(account.name)")
                    }
                } header: {
                    Text(verbatim: "Debts")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Color.page)
            .navigationTitle(Text(verbatim: "Account form"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        form = FormRequest(account: nil)
                    } label: {
                        Label { Text(verbatim: "New account") } icon: { Image(systemName: Symbols.add) }
                    }
                    .accessibilityIdentifier("debugHost.new")
                }
            }
            .sheet(item: $form) { request in
                AccountFormSheet(data: data, editing: request.account) { form = nil }
            }
        }
    }

    /// Everything the form writes, in one line: "LOAN · RUB · −200 000 ₽ · outside · Банк · 19.9 % · 10 000 ₽ on 5".
    private func summary(_ account: Account) -> String {
        var parts = [account.type.rawValue, account.currency, Fmt.amount(data.states[account.id]?.balanceMinor ?? 0, account.currency)]
        parts.append(account.includeInFree ? "in budget" : "outside")
        if let group = account.groupName { parts.append(group) }
        if let rate = account.interestRate { parts.append("\(rate) %") }
        if let payment = account.paymentMinor { parts.append(Fmt.amount(payment, account.currency) + " on \(account.paymentDay.map(String.init) ?? "-")") }
        if let grace = account.graceUntil { parts.append("grace \(LocalDate(epochDay: Int(grace)))") }
        return parts.joined(separator: " · ")
    }
}

/// A debt's terms as its page will show them.
private struct DebtPage: View {
    let accountId: UUID

    @Environment(AppModel.self) private var model

    var body: some View {
        if let data = model.data, let state = data.states[accountId] {
            List {
                DebtDetailsView(state: state, data: data, today: model.environment.today())
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Color.page)
            .navigationTitle(Text(verbatim: state.account.name))
        }
    }
}
#endif
