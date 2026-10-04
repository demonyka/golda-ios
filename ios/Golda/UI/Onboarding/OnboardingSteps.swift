import GoldaCore
import GoldaData
import SwiftUI

// The three steps' rows, as sections of the onboarding list. Each one is the row of the screen that
// changes the same thing later (a profile's income, settings' currencies, the Accounts tab).

/// Income: the rate or the salary, tax and hours, payday, and what an hour comes to after tax. Each
/// row opens the same small sheet as on the profile's screen.
struct OnboardingIncomeStep: View {
    let data: AppData
    let today: LocalDate
    var onEdit: (OnboardingView.IncomeEdit) -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        let income = ProfileIncome(data.profile.settings, today: today)
        Section {
            row(title: income.rateTitle, value: income.rateText(in: locale), symbol: ProfileSymbols.rate, edit: .rate)
            row(title: ProfileIncome.taxHoursTitle, value: income.taxHoursText(in: locale), symbol: ProfileSymbols.taxHours, edit: .taxHours)
            row(title: ProfileIncome.paydayTitle, value: income.paydayText(in: locale), symbol: ProfileSymbols.payday, edit: .payday)
        }
        .listRowBackground(Theme.Color.card)
        Section {
            LabeledContent {
                Text(verbatim: income.hourNet)
                    .font(.title3.weight(.semibold))
                    .tabularDigits()
                    .foregroundStyle(Theme.Color.text)
            } label: {
                // No glyph of its own; its room is kept so the title lines up with the rows above.
                HStack(spacing: Theme.Gap.m) {
                    Color.clear
                        .frame(width: ProfileSymbols.width, height: 1)
                        .accessibilityHidden(true)
                    Text(verbatim: ProfileIncome.hourNetTitle.text(in: locale))
                        .foregroundStyle(Theme.Color.text)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("onboarding.hourNet")
        }
        .listRowBackground(Theme.Color.card)
    }

    private func row(title: LocalizedStringResource, value: String, symbol: String, edit: OnboardingView.IncomeEdit) -> some View {
        Button {
            onEdit(edit)
        } label: {
            LabeledContent {
                Text(verbatim: value)
                    .tabularDigits()
                    .foregroundStyle(Theme.Color.muted)
                    .multilineTextAlignment(.trailing)
            } label: {
                RowLabel(title: title.text(in: locale), symbol: symbol)
            }
            .contentShape(.rect)
        }
        .accessibilityIdentifier("onboarding.\(edit.rawValue)")
    }
}

/// Currencies: what every amount is shown in, then the local currency, out of those. The main
/// currency stays the ruble here, as on Android, and moves in settings.
struct OnboardingCurrenciesStep: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale

    var body: some View {
        Section {
            ForEach(SettingsCurrencies.shownOptions(model.device)) { option in
                Toggle(isOn: Binding(get: { option.isOn }, set: { _ in model.toggleShownCurrency(option.code) })) {
                    Text(verbatim: SettingsCurrencies.label(option.code))
                        .foregroundStyle(Theme.Color.text)
                }
                .disabled(option.isLocked)
                .frame(minHeight: Theme.minimumTarget)
                .accessibilityIdentifier("onboarding.shown.\(option.code)")
            }
        } header: {
            Text(verbatim: OnboardingStep.shownHeader.text(in: locale))
        }
        .listRowBackground(Theme.Color.card)
        Section {
            Picker(selection: Binding(get: { model.device.localCurrency }, set: { model.setLocalCurrency($0) })) {
                ForEach(SettingsCurrencies.pickOptions(model.device, selected: model.device.localCurrency), id: \.self) { code in
                    Text(verbatim: SettingsCurrencies.label(code)).tag(code)
                }
            } label: {
                Text(verbatim: OnboardingStep.localTitle.text(in: locale))
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("onboarding.local")
        } header: {
            Text(verbatim: OnboardingStep.localHeader.text(in: locale))
        }
        .listRowBackground(Theme.Color.card)
    }
}

/// Accounts: the ones made so far, as on the Accounts tab, and "+ Счёт". A row opens the account's
/// form, so a mistake is fixed here; the balances can be reconciled later.
struct OnboardingAccountsStep: View {
    let data: AppData
    let today: LocalDate
    /// The account form: for an account, or empty for nil.
    var onOpenForm: (Account?) -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        Section {
            ForEach(rows) { row in
                Button {
                    onOpenForm(row.account)
                } label: {
                    AccountRowView(row: row)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.account")
            }
            Button {
                onOpenForm(nil)
            } label: {
                // "+ Счёт" in the system blue, as an action row of an iOS list reads (D34).
                HStack(spacing: Theme.Gap.m) {
                    Image(systemName: Symbols.add)
                    Text(verbatim: OnboardingStep.addAccountTitle.text(in: locale))
                }
                .font(.body.weight(.medium))
                .foregroundStyle(.tint)
                .frame(maxWidth: .infinity, minHeight: Theme.minimumTarget, alignment: .leading)
                .contentShape(.rect)
            }
            .accessibilityLabel(Text(verbatim: OnboardingStep.addAccountLabel.text(in: locale)))
            .accessibilityIdentifier("onboarding.addAccount")
        }
        .listRowBackground(Theme.Color.card)
        .animation(.snappy, value: rows)
    }

    private var rows: [AccountRowModel] {
        data.accounts.compactMap { account in
            data.states[account.id].map { AccountRowModel($0, in: data, today: today) }
        }
    }
}
