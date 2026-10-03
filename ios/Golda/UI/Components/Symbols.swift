import GoldaCore

/// SF Symbols for everything Iconoteka drew on Android (DESIGN.md, "Иконки", decision D14). Every
/// name here is checked against the system by a test, so a symbol that the SDK does not know
/// fails the build of the tests, not the screen at run time.
enum Symbols {
    // MARK: Actions

    static let mic = "mic.fill"
    static let stop = "stop.fill"
    /// Add by hand: the "+" in the navigation bar.
    static let add = "plus"
    static let settings = "gearshape"
    static let delete = "trash"
    /// The arrow in "Семья ⌄", the profile menu in the toolbar.
    static let profileMenu = "chevron.down"
    /// A shared profile.
    static let sharedProfile = "person.2"
    /// Reconciliation: the balance matches.
    static let reconcile = "checkmark"
    static let transfer = "arrow.left.arrow.right"

    // MARK: Tabs

    /// The four tabs of the `TabView`. The selected tab takes the filled variant of its symbol.
    enum Tab: CaseIterable, Sendable {
        case home, accounts, goals, insights

        func symbol(selected: Bool) -> String {
            let base = switch self {
            case .home: "house"
            case .accounts: "wallet.pass"
            case .goals: "flag"
            case .insights: "chart.pie"
            }
            return selected ? base + ".fill" : base
        }
    }

    // MARK: Categories

    /// A category's symbol by its stable key. A category of your own, or no category, gets the box.
    static func category(_ key: String?) -> String {
        switch key {
        case "eating_out": "fork.knife"
        case "groceries": "cart"
        case "transport": "bus"
        case "housing": "house"
        case "telecom": "phone"
        case "fun": "ticket"
        case "health": "pills"
        case "clothes": "tshirt"
        case "subscriptions": "arrow.triangle.2.circlepath"
        case "travel": "airplane"
        case "fees": "percent"
        case "salary": "briefcase"
        case "interest": "building.columns"
        case "gift": "gift"
        default: other
        }
    }

    /// "Прочее" and any category without a symbol of its own.
    static let other = "shippingbox"

    /// The built-in keys that have a symbol of their own (`other` and `other_income` share the box).
    static let categoryKeys = [
        "eating_out", "groceries", "transport", "housing", "telecom", "fun", "health", "clothes",
        "subscriptions", "travel", "fees", "other", "salary", "interest", "gift", "other_income",
    ]

    // MARK: Accounts

    static func accountType(_ type: AccountType) -> String {
        switch type {
        case .card: "creditcard"
        case .cash: "banknote"
        case .savings: "chart.line.uptrend.xyaxis"
        case .credit: "creditcard.trianglebadge.exclamationmark"
        case .loan: "building.columns"
        }
    }

    // MARK: Operations

    /// What the start of an operation's row shows: its category, or what kind of move it is.
    static func operation(categoryKey: String?, type: OpType) -> String {
        if let categoryKey { return category(categoryKey) }
        switch type {
        case .transfer: return transfer
        case .adjustment: return reconcile
        case .expense, .income, .opening: return other
        }
    }

    // MARK: Settings

    enum Setting: CaseIterable, Sendable {
        case currency, rate, key, language, reminder

        var symbol: String {
            switch self {
            case .currency: "dollarsign.circle"
            case .rate: "arrow.clockwise"
            case .key: "key"
            case .language: "globe"
            case .reminder: "bell"
            }
        }
    }

    // MARK: Everything, for the test

    /// Every symbol name this file can return.
    static var allNames: [String] {
        var names = [mic, stop, add, settings, delete, profileMenu, sharedProfile, reconcile, transfer, other]
        names += Tab.allCases.flatMap { [$0.symbol(selected: false), $0.symbol(selected: true)] }
        names += categoryKeys.map { category($0) }
        names += AccountType.allCases.map { accountType($0) }
        names += Setting.allCases.map(\.symbol)
        return names
    }
}
