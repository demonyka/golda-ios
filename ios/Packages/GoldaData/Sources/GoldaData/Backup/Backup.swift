import Foundation
import GoldaCore

/// Everything a backup file holds, in memory. A version 2 file decodes into it as written; an
/// Android version 1 file is converted into it (ids, categories, settings), so the import has one
/// shape to validate and apply.
public struct Backup: Equatable, Sendable {
    /// The version of the file this was decoded from. Informational: `BackupFormat.encode` always
    /// writes the current version.
    public var sourceVersion: Int
    /// Epoch milliseconds the file was made at.
    public var exportedAt: Int64
    public var device: BackupDevice
    /// By `sort`, as the app lists them (the file is written in that order). Each profile's lists
    /// follow `ProfileSnapshot`'s orders (operations newest first), and the import writes them back
    /// so the screens show the same order again.
    public var profiles: [ProfileSnapshot]
    /// Each goal's place in its profile's creation order (1, 2, 3… or Android's ids: a counter, not
    /// a time), by goal id. The domain's `Goal` has no such field, and "the oldest goal becomes main"
    /// needs it. A profile whose goals are not all here, or whose counters repeat, has no entries
    /// and its goals are created in the order they are listed.
    public var goalCreatedAt: [UUID: Int64]
    /// The same for payments, by payment id: payments of one day are listed in creation order. The
    /// same fallback applies.
    public var obligationCreatedAt: [UUID: Int64]
    /// Official CBR rates, shared by all profiles; by code.
    public var rates: [RateRecord]

    public init(
        sourceVersion: Int = BackupFormat.version, exportedAt: Int64, device: BackupDevice = BackupDevice(),
        profiles: [ProfileSnapshot], goalCreatedAt: [UUID: Int64] = [:], obligationCreatedAt: [UUID: Int64] = [:],
        rates: [RateRecord] = []
    ) {
        self.sourceVersion = sourceVersion
        self.exportedAt = exportedAt
        self.device = device
        self.profiles = profiles
        self.goalCreatedAt = goalCreatedAt
        self.obligationCreatedAt = obligationCreatedAt
        self.rates = rates
    }
}

/// The device settings a backup carries (D16): what shapes how the numbers are shown and how voice
/// is parsed. API keys, the voice consent, the active profile and the per-profile maps (last
/// account, celebrated goal) are the person's choice on this phone and never travel.
public struct BackupDevice: Equatable, Sendable {
    public var displayCurrencies: [String]
    public var localCurrency: String
    public var baseCurrency: String
    public var geminiModel: String
    public var reconcileReminder: Bool

    /// Defaults come from `DeviceSettings`, so a backup without a key takes what a fresh install has.
    /// Blank currency codes are dropped, as `DeviceSettings` drops them when it reads its own data.
    public init(
        displayCurrencies: [String] = DeviceSettings().displayCurrencies, localCurrency: String = DeviceSettings().localCurrency,
        baseCurrency: String = DeviceSettings().baseCurrency, geminiModel: String = DeviceSettings().geminiModel,
        reconcileReminder: Bool = DeviceSettings().reconcileReminder
    ) {
        self.displayCurrencies = displayCurrencies.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        self.localCurrency = localCurrency
        self.baseCurrency = baseCurrency
        self.geminiModel = geminiModel
        self.reconcileReminder = reconcileReminder
    }

    public init(_ settings: DeviceSettings) {
        self.init(
            displayCurrencies: settings.displayCurrencies, localCurrency: settings.localCurrency,
            baseCurrency: settings.baseCurrency, geminiModel: settings.geminiModel,
            reconcileReminder: settings.reconcileReminder
        )
    }

    /// Writes the carried fields; everything else in [settings] stays as it is.
    func apply(to settings: inout DeviceSettings) {
        settings.displayCurrencies = displayCurrencies
        settings.localCurrency = localCurrency
        settings.baseCurrency = baseCurrency
        settings.geminiModel = geminiModel
        settings.reconcileReminder = reconcileReminder
    }
}

/// What an import did, for the confirmation the person sees.
public struct BackupSummary: Equatable, Sendable {
    /// 1 for an Android file, 2 for a file this app wrote.
    public var sourceVersion: Int
    public var profiles: Int
    public var accounts: Int
    public var operations: Int
    public var postings: Int
    public var obligations: Int
    public var goals: Int
    public var wishes: Int
    public var rates: Int
    /// The profile the app shows now: the first one by `sort`.
    public var activeProfileId: UUID

    init(_ backup: Backup, activeProfileId: UUID) {
        let profiles = backup.profiles
        sourceVersion = backup.sourceVersion
        self.profiles = profiles.count
        accounts = profiles.reduce(0) { $0 + $1.accounts.count }
        operations = profiles.reduce(0) { $0 + $1.operations.count }
        postings = profiles.reduce(0) { $0 + $1.operations.reduce(0) { $0 + $1.postings.count } }
        obligations = profiles.reduce(0) { $0 + $1.obligations.count }
        goals = profiles.reduce(0) { $0 + $1.goals.count }
        wishes = profiles.reduce(0) { $0 + $1.wishes.count }
        rates = backup.rates.count
        self.activeProfileId = activeProfileId
    }
}

/// Why a file was refused. The payloads are for logs, not for the person: screens say "this file
/// cannot be imported" and, for a newer version, "update the app".
public enum BackupError: Error, Equatable, Sendable {
    /// Not JSON, cut short, or not shaped like a backup (a required key missing, a value of the wrong type).
    case unreadable(String)
    /// A version this app does not know: a newer app wrote it.
    case unsupportedVersion(Int)
    /// A version 2 file with no profiles: the app always has at least one.
    case noProfiles
    /// Export found no profile. Such a file could not be imported again, so none is written.
    case nothingToExport
    /// Two rows of one kind share an id.
    case duplicateId(String)
    /// A row points at something the file does not hold, or holds in another profile.
    case danglingReference(String)
    /// An amount past `Money.maxMinor`, which nothing in the app can write (D59).
    case amountOutOfRange(String)
}

extension Backup {
    /// Throws when applying the backup could not leave consistent books. Runs before the database is
    /// touched, so the first violation costs nothing.
    func validate() throws {
        guard !profiles.isEmpty else { throw BackupError.noProfiles }

        // Ids are primary keys of whole tables, shared by every profile, so uniqueness is file-wide.
        try requireUnique(profiles.map(\.profile.id), "profile")
        try requireUnique(profiles.flatMap { $0.accounts.map(\.id) }, "account")
        try requireUnique(profiles.flatMap { $0.operations.map(\.op.id) }, "operation")
        try requireUnique(profiles.flatMap { $0.operations.flatMap { $0.postings.map(\.id) } }, "posting")
        try requireUnique(profiles.flatMap { $0.obligations.map(\.id) }, "obligation")
        try requireUnique(profiles.flatMap { $0.goals.map(\.id) }, "goal")
        try requireUnique(profiles.flatMap { $0.wishes.map(\.id) }, "wish")
        try requireUnique(profiles.flatMap { $0.categories.map(\.id) }, "category")

        for snapshot in profiles {
            let accountIds = Set(snapshot.accounts.map(\.id))
            for full in snapshot.operations {
                for posting in full.postings {
                    // A posting on another profile's account would also be refused by the database,
                    // but then only after the old data was deleted (and rolled back).
                    guard posting.operationId == full.op.id else {
                        throw BackupError.danglingReference("posting \(posting.id) belongs to another operation")
                    }
                    guard accountIds.contains(posting.accountId) else {
                        throw BackupError.danglingReference(
                            "posting \(posting.id) is on an account that is not in profile \(snapshot.profile.id)"
                        )
                    }
                    try requireInRange(posting.amountMinor, "posting \(posting.id)")
                }
                try requireInRange(full.op.purchaseAmountMinor, "operation \(full.op.id)")
            }
            for account in snapshot.accounts { try requireInRange(account.paymentMinor, "account \(account.id)") }
            for obligation in snapshot.obligations { try requireInRange(obligation.amountMinor, "obligation \(obligation.id)") }
            for goal in snapshot.goals {
                try requireInRange(goal.targetMinor, "goal \(goal.id)")
                try requireInRange(goal.savedMinor, "goal \(goal.id)")
            }
            for wish in snapshot.wishes { try requireInRange(wish.amountMinor, "wish \(wish.id)") }
        }
    }

    /// Every amount in a currency's own minor units stays within what the app could have written.
    /// Swift traps on Int64 overflow where Kotlin's Long wraps, so one row near Int64.max (Android
    /// took up to Long.MAX_VALUE, a file can be edited) would otherwise crash every launch once the
    /// sums ran (D59). Ruble values are left alone: the sums hold at ±Int64.max for them.
    private func requireInRange(_ minor: Int64?, _ row: String) throws {
        guard let minor, minor.magnitude > Money.maxMinor.magnitude else { return }
        throw BackupError.amountOutOfRange("\(row): \(minor)")
    }

    private func requireUnique(_ ids: [UUID], _ kind: String) throws {
        var seen = Set<UUID>()
        for id in ids where !seen.insert(id).inserted {
            throw BackupError.duplicateId("\(kind) \(id)")
        }
    }
}
