import Foundation
import GoldaCore

/// A separate set of books ("Личный", "Семья"). It owns accounts, operations, obligations, goals
/// and wishes, and is what gets shared, so everyone in it sees the same "можно сегодня".
public struct Profile: Equatable, Hashable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var sort: Int
    public var settings: ProfileSettings

    public init(id: UUID = UUID(), name: String, sort: Int = 0, settings: ProfileSettings = ProfileSettings()) {
        self.id = id
        self.name = name
        self.sort = sort
        self.settings = settings
    }
}

/// The part of `GoldaCore.Settings` that belongs to a profile and its members: income, payday and
/// the markup learned from exchanges. Currencies and the last-used account stay on the device.
public struct ProfileSettings: Equatable, Hashable, Sendable, Codable {
    public var incomeHourly: Bool
    public var hourlyRate: Double
    public var monthlySalary: Double
    public var taxPercent: Double
    public var hoursPerWeek: Double
    public var payday: Int
    public var markup: Double

    public init(
        incomeHourly: Bool, hourlyRate: Double, monthlySalary: Double, taxPercent: Double, hoursPerWeek: Double,
        payday: Int, markup: Double
    ) {
        self.incomeHourly = incomeHourly
        self.hourlyRate = hourlyRate
        self.monthlySalary = monthlySalary
        self.taxPercent = taxPercent
        self.hoursPerWeek = hoursPerWeek
        self.payday = payday
        self.markup = markup
    }

    /// The profile's part of [settings]; the defaults come from the domain so they cannot drift.
    public init(from settings: Settings = Settings()) {
        self.init(
            incomeHourly: settings.incomeHourly, hourlyRate: settings.hourlyRate, monthlySalary: settings.monthlySalary,
            taxPercent: settings.taxPercent, hoursPerWeek: settings.hoursPerWeek, payday: settings.payday,
            markup: settings.markup
        )
    }
}

/// One profile's books read in a single transaction, in the orders the screens show them.
public struct ProfileSnapshot: Equatable, Sendable {
    public var profile: Profile
    /// By `sort`, then id.
    public var accounts: [Account]
    /// Newest first; of operations with the same timestamp, the last written comes first.
    public var operations: [OperationFull]
    /// By day of month, then id.
    public var obligations: [Obligation]
    /// The main goal first, then by id.
    public var goals: [Goal]
    /// By status, then the latest decision date first.
    public var wishes: [Wish]

    public init(
        profile: Profile, accounts: [Account], operations: [OperationFull], obligations: [Obligation], goals: [Goal],
        wishes: [Wish]
    ) {
        self.profile = profile
        self.accounts = accounts
        self.operations = operations
        self.obligations = obligations
        self.goals = goals
        self.wishes = wishes
    }
}
