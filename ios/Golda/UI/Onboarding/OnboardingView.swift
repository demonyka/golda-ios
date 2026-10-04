import GoldaCore
import GoldaData
import OSLog
import SwiftUI

private let log = Logger(subsystem: "com.f4studio.golda", category: "Onboarding")

/// The first launch: income, currencies, accounts, one step at a time under a wavy bar, with "Назад"
/// and "Дальше" at the bottom; "Готово" on the last step opens the app. The port of Android's
/// `Onboarding`, with the same steps and the same words.
///
/// The steps reuse the screens that change the same things later: the income's sheets of a
/// profile's screen, the currency switches of settings and the account form. The first profile is
/// made when this screen appears, so each of them has a profile to change; the app stays closed
/// until "Готово".
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @State private var step = OnboardingStep.income
    @State private var incomeEdit: IncomeEdit?
    @State private var accountForm: AccountFormRequest?
    @State private var failed = false

    /// The sheet open over the income step.
    enum IncomeEdit: String, Identifiable {
        case rate, taxHours, payday
        var id: String { rawValue }
    }

    /// The account form: empty from "+ Счёт", or for an account from its row.
    private struct AccountFormRequest: Identifiable {
        let account: Account?
        let id = UUID()
    }

    var body: some View {
        Group {
            if let data = model.data {
                content(data)
            } else {
                // The profile is made a moment after the screen appears; a blank page carries on.
                Theme.Color.page.ignoresSafeArea()
            }
        }
        .task { await begin() }
    }

    private func content(_ data: AppData) -> some View {
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets(top: Theme.Gap.m, leading: Theme.Gap.s, bottom: Theme.Gap.xs, trailing: Theme.Gap.s))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            switch step {
            case .income:
                OnboardingIncomeStep(data: data, today: model.environment.today()) { incomeEdit = $0 }
            case .currencies:
                OnboardingCurrenciesStep()
            case .accounts:
                OnboardingAccountsStep(data: data, today: model.environment.today()) { accountForm = AccountFormRequest(account: $0) }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.Color.page)
        // A new step starts at its top, not where the last one was scrolled to.
        .id(step)
        .safeAreaInset(edge: .bottom) { bottomBar }
        .sensoryFeedback(.selection, trigger: step)
        .sheet(item: $incomeEdit) { edit in
            incomeSheet(edit, settings: data.profile.settings)
        }
        .sheet(item: $accountForm) { request in
            AccountFormSheet(data: model.data ?? data, editing: request.account, onDismiss: { accountForm = nil })
        }
        .alert(Text(verbatim: ProfileScreen.failureText.text(in: locale)), isPresented: $failed) {
            Button(role: .cancel) {} label: {
                Text("OK", tableName: "Profiles", comment: "Closes the message that a change was not saved.")
            }
        }
    }

    // MARK: Pieces

    /// "Golda", the bar, then what the step is.
    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Gap.m) {
            Text(verbatim: "Golda")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Theme.Color.text)
            WavyBar(progress: step.progress)
                .accessibilityLabel(Text(verbatim: step.positionText(in: locale)))
            VStack(alignment: .leading, spacing: Theme.Gap.xs) {
                Text(verbatim: step.title.text(in: locale))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.Color.text)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: step.note.text(in: locale))
                    .foregroundStyle(Theme.Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bottomBar: some View {
        HStack(spacing: Theme.Gap.s) {
            if let previous = step.previous {
                Button {
                    go(to: previous)
                } label: {
                    Text(verbatim: OnboardingStep.backTitle.text(in: locale))
                        .font(.headline)
                        .padding(.horizontal, Theme.Gap.s)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .accessibilityIdentifier("onboarding.back")
            }
            Spacer(minLength: 0)
            Button(action: advance) {
                Text(verbatim: step.advanceTitle.text(in: locale))
                    .font(.headline)
                    .padding(.horizontal, Theme.Gap.s)
            }
            // The screen's one way on: prominent glass in the system blue, as an iOS "Continue" (D34).
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .accessibilityIdentifier(step.isLast ? "onboarding.done" : "onboarding.next")
        }
        .padding(.horizontal, Theme.Gap.m)
        .padding(.vertical, Theme.Gap.s)
    }

    @ViewBuilder private func incomeSheet(_ edit: IncomeEdit, settings: ProfileSettings) -> some View {
        switch edit {
        case .rate: RateSheet(settings: settings, onSave: update)
        case .taxHours: TaxHoursSheet(settings: settings, onSave: update)
        case .payday: PaydaySheet(payday: settings.payday, onSave: update)
        }
    }

    // MARK: Actions

    private func go(to next: OnboardingStep) {
        withAnimation(.snappy) { step = next }
    }

    private func advance() {
        if let next = step.next {
            go(to: next)
        } else {
            model.finishOnboarding()
        }
    }

    /// The first profile; the failure screen takes over when there is none to be had, since no step
    /// can do anything without one.
    private func begin() async {
        do {
            try await model.beginOnboarding()
        } catch {
            model.fail(error)
        }
    }

    /// Applies [change] to the profile's settings as they are now, as the profile's screen does.
    private func update(_ change: @escaping ProfileSettingsChange) {
        guard let profile = model.data?.profile, let settings = change(profile.settings), settings != profile.settings else { return }
        let model = model
        Task {
            do {
                try await model.saveProfileSettings(settings, profileId: profile.id)
            } catch {
                log.error("Saving the income failed: \(String(describing: error))")
                failed = true
            }
        }
    }
}

#Preview("Onboarding") {
    @Previewable @State var model = AppModel.preview()
    OnboardingView()
        .environment(model)
        .task { await model.start() }
}

#Preview("Onboarding, dark, Russian") {
    @Previewable @State var model = AppModel.preview()
    OnboardingView()
        .environment(model)
        .environment(\.locale, Locale(identifier: "ru"))
        .preferredColorScheme(.dark)
        .task { await model.start() }
}
