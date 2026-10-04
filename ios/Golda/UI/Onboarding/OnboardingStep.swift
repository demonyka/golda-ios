import Foundation

/// The three steps of the first launch, in Android's order: income, currencies, accounts. Everything
/// in them can be changed later in settings and on the profile's screen. The order, the bar and the
/// words live here; `OnboardingView` only lays them out.
enum OnboardingStep: Int, CaseIterable, Sendable {
    case income, currencies, accounts

    static var count: Int { allCases.count }

    /// 1-based, as the person counts them.
    var number: Int { rawValue + 1 }
    var next: OnboardingStep? { Self(rawValue: rawValue + 1) }
    var previous: OnboardingStep? { Self(rawValue: rawValue - 1) }
    var isFirst: Bool { previous == nil }
    var isLast: Bool { next == nil }

    /// Where the wavy bar stands: a third on the first step, full on the last.
    var progress: Double { Double(number) / Double(Self.count) }

    // MARK: Text

    var title: LocalizedStringResource {
        switch self {
        case .income: Self.incomeTitle
        case .currencies: Self.currenciesTitle
        case .accounts: Self.accountsTitle
        }
    }

    /// What the step is for, under its title.
    var note: LocalizedStringResource {
        switch self {
        case .income: Self.incomeNote
        case .currencies: Self.currenciesNote
        case .accounts: Self.accountsNote
        }
    }

    /// "Дальше" on the first two steps, "Готово" on the last, which opens the app.
    var advanceTitle: LocalizedStringResource {
        isLast ? Self.doneTitle : Self.nextTitle
    }

    static let backTitle = resource("Back", "Onboarding: the button to the previous step.")

    /// "Шаг 2 из 3": what the bar says to VoiceOver.
    func positionText(in locale: Locale) -> String {
        Self.position(number, of: Self.count).text(in: locale)
    }

    private static let incomeTitle = resource("Income", "Onboarding, step 1: its title.")
    private static let currenciesTitle = resource("Currencies", "Onboarding, step 2: its title.")
    private static let accountsTitle = resource("Accounts", "Onboarding, step 3: its title.")
    private static let incomeNote = resource(
        "Used to work out what is safe to spend until the next payday and to turn prices into hours of work.",
        "Onboarding, income step: what the income is for."
    )
    private static let currenciesNote = resource(
        "Every amount shows in all the chosen currencies at once. The ruble is the main one.",
        "Onboarding, currencies step: what the shown currencies do."
    )
    private static let accountsNote = resource(
        "Cards, cash, savings and debts with their balances now. Rough numbers are easy to fix later by reconciling.",
        "Onboarding, accounts step: what to add and that mistakes can be fixed."
    )
    private static let nextTitle = resource("Next", "Onboarding: the button to the next step.")
    private static let doneTitle = resource("Done", "Onboarding, last step: the button that finishes it and opens the app.")

    private static func position(_ number: Int, of count: Int) -> LocalizedStringResource {
        resource("Step \(number) of \(count)", "Onboarding, VoiceOver: where the progress bar stands, “Step 2 of 3”.")
    }

    // MARK: Currencies step

    static let shownHeader = resource("Show amounts in", "Onboarding, currencies step: the header over the switches of the shown currencies.")
    static let localHeader = resource(
        "Local currency, for amounts said without one", "Onboarding, currencies step: the header over the choice of the local currency."
    )
    static let localTitle = resource("Currency", "Onboarding, currencies step: the label of the local currency's menu.")

    // MARK: Accounts step

    static let addAccountTitle = resource("Account", "Onboarding, accounts step: the last row, “+ Account”.")
    static let addAccountLabel = resource("Add account", "Onboarding, VoiceOver: the “+ Account” row.")

    private static let table = "Onboarding"

    private static func resource(_ key: String.LocalizationValue, _ comment: StaticString) -> LocalizedStringResource {
        LocalizedStringResource(key, table: table, comment: comment)
    }
}
