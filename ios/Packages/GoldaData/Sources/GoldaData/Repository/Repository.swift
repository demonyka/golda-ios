import Foundation
import GoldaCore

/// Every change to the books, the port of Android's `Repo` and the data side of `Wishes`. Each
/// call names its profile and touches only that profile's rows; rates are the one thing all
/// profiles share.
///
/// A change is one transaction, and it lands even when the task that asked for it is cancelled
/// (a screen went away mid-save), as Android's `NonCancellable` writes did.
public actor Repository {
    public let database: GoldaDatabase
    public let deviceSettings: DeviceSettingsStore
    /// Only `resetAll` touches it: wiping everything takes the API keys too, as on Android.
    let secrets: any SecretStore
    /// Epoch milliseconds now. Injected so tests run on a fixed time.
    let clock: @Sendable () -> Int64
    /// Where "today" is; read on each use, since the phone travels.
    let zone: @Sendable () -> TimeZone

    public init(
        database: GoldaDatabase,
        deviceSettings: DeviceSettingsStore,
        secrets: any SecretStore,
        clock: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
        zone: @escaping @Sendable () -> TimeZone = { TimeZone.current }
    ) {
        self.database = database
        self.deviceSettings = deviceSettings
        self.secrets = secrets
        self.clock = clock
        self.zone = zone
    }

    // MARK: Profiles

    /// A new profile after the existing ones. The first one is created by onboarding with a
    /// localized name ("Личный").
    @discardableResult
    public func createProfile(name: String, settings: ProfileSettings = ProfileSettings()) async throws -> Profile {
        try await write { store in
            let sort = (try store.profiles().map(\.sort).max() ?? -1) + 1
            let profile = Profile(name: name.trimmingCharacters(in: .whitespacesAndNewlines), sort: sort, settings: settings)
            try store.save(profile)
            return profile
        }
    }

    public func renameProfile(_ id: UUID, to name: String) async throws {
        try await updateProfile(id) { $0.name = name.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// Income, payday and markup, shared by everyone in the profile.
    public func saveProfileSettings(_ settings: ProfileSettings, profileId: UUID) async throws {
        try await updateProfile(profileId) { $0.settings = settings }
    }

    /// Deletes the profile with everything it owns and forgets what this phone kept about it. The
    /// active profile moves to the first one left. A profile that is already gone is not an error.
    public func deleteProfile(_ id: UUID) async throws {
        let remaining = try await write { store -> [Profile] in
            let profiles = try store.profiles()
            guard profiles.contains(where: { $0.id == id }) else { return profiles }
            guard profiles.count > 1 else { throw RepositoryError.lastProfile }
            try store.deleteProfile(id)
            return profiles.filter { $0.id != id }
        }
        deviceSettings.update { device in
            device.lastAccountId[id] = nil
            device.celebratedGoalId[id] = nil
            if device.activeProfileId == id { device.activeProfileId = remaining.first?.id }
        }
    }

    private func updateProfile(_ id: UUID, _ change: @escaping @Sendable (inout Profile) -> Void) async throws {
        try await write { store in
            guard var profile = try store.profile(id) else { throw RepositoryError.unknownProfile(id) }
            change(&profile)
            try store.save(profile)
        }
    }

    // MARK: Rates and seeding

    /// Rates to start with when there are none yet, and postings valued at 0 ₽ for want of a rate
    /// revalued at the rates there are.
    public func ensureSeed() async throws {
        try await write { store in
            if try store.rates().isEmpty { try store.save(CbrRatesSource.fallback.map(RateRecord.init)) }
            try Self.repairValuations(store)
        }
    }

    /// True when fresh rates arrived. A failed download changes nothing and is not an error; a
    /// failed write is.
    @discardableResult
    public func refreshRates(from source: any RatesSource) async throws -> Bool {
        let fresh: [CbrRate]
        do {
            fresh = try await source.fetch()
        } catch {
            return false
        }
        try await write { store in
            try store.save(fresh.map(RateRecord.init))
            try Self.repairValuations(store)
        }
        return true
    }

    /// Official rates with the profile's markup: the rates every amount of that profile is shown at.
    public func rates(profileId: UUID) async throws -> Rates {
        try await database.read { store in
            guard let profile = try store.profile(profileId) else { throw RepositoryError.unknownProfile(profileId) }
            return try Self.rates(store, markup: profile.settings.markup)
        }
    }

    /// `GoldaCore.Settings` while [profileId] is open.
    public func settings(profileId: UUID) async throws -> Settings {
        let device = deviceSettings.current
        return try await database.read { store in
            guard let profile = try store.profile(profileId) else { throw RepositoryError.unknownProfile(profileId) }
            return Settings(profile: profile.settings, device: device, profileId: profileId)
        }
    }

    /// Wipes every profile and the rates, seeds the fallback rates, deletes the API keys and resets
    /// this phone's settings. The settings go last: their reset is what sends the app back to
    /// onboarding, so it happens even when the Keychain refuses, and that error is thrown after.
    public func resetAll() async throws {
        try await write { store in
            try store.deleteAllProfiles()
            try store.deleteAllRates()
            try store.save(CbrRatesSource.fallback.map(RateRecord.init))
        }
        // Android's `settings.clear()` took the encrypted key along with the settings.
        let secrets = secrets
        let keysDeleted = Result { for key in SecretKey.all { try secrets.delete(key) } }
        deviceSettings.reset()
        try keysDeleted.get()
    }

    // MARK: Accounts

    /// A new account is inserted with [openingMinor], if any, booked as its opening balance; an
    /// existing one is updated and [openingMinor] is ignored, as on Android.
    ///
    /// `reconciledAt` is left as stored: only `reconcile` writes it. Android kept it in the
    /// settings, out of reach of the account form, and a form built before a reconcile must not
    /// wipe the stamp.
    public func saveAccount(_ account: Account, profileId: UUID, openingMinor: Int64? = nil) async throws {
        let now = clock()
        try await write { store in
            let stored = try store.account(account.id, profileId: profileId)
            var account = account
            account.reconciledAt = stored?.reconciledAt
            try store.save(account, profileId: profileId)
            if stored == nil, let openingMinor, openingMinor != 0 {
                let opening = Draft(type: .opening, timestamp: now, accountId: account.id, amountMinor: openingMinor)
                _ = try Self.book(opening, profileId: profileId, in: store, at: now)
            }
        }
    }

    /// The account goes with every operation that touches it, both sides of its transfers
    /// included, so no half of a transfer is left behind.
    public func deleteAccount(_ id: UUID, profileId: UUID) async throws {
        try await write { store in
            try store.deleteOperations(touching: id, profileId: profileId)
            try store.deleteAccount(id, profileId: profileId)
        }
    }

    // MARK: Operations

    /// Records [draft], or replaces the operation with its id, and returns the operation id.
    ///
    /// Postings are valued against the balances without the operation being replaced, at the rate
    /// table with the profile's markup. An exchange learns the markup into the profile; an expense
    /// makes its account this phone's default in the profile.
    @discardableResult
    public func save(_ draft: Draft, profileId: UUID) async throws -> UUID {
        let now = clock()
        let id = try await write { store in try Self.book(draft, profileId: profileId, in: store, at: now) }
        if draft.type == .expense { deviceSettings.update { $0.lastAccountId[profileId] = draft.accountId } }
        return id
    }

    /// Deletes the operation and returns what "Отменить" needs to bring it back; nil when the
    /// profile has no such operation.
    @discardableResult
    public func deleteOperation(_ id: UUID, profileId: UUID) async throws -> DeletedOperation? {
        try await write { store in
            guard let full = try store.operation(id, profileId: profileId),
                  let sequence = try store.sequence(ofOperation: id, profileId: profileId)
            else { return nil }
            try store.deleteOperation(id, profileId: profileId)
            return DeletedOperation(full: full, sequence: sequence)
        }
    }

    /// Undo of `deleteOperation`: the operation comes back with the same ids, its own and its
    /// postings', so sync sees the same rows return, and in the same place among operations with
    /// its timestamp, as Android re-inserted it under its autoincrement id.
    public func restoreOperation(_ deleted: DeletedOperation, profileId: UUID) async throws {
        let now = clock()
        try await write { store in
            try store.restore(deleted.full, sequence: deleted.sequence, profileId: profileId, updatedAt: now)
        }
    }

    /// Brings the account to what the bank shows: the difference is booked as an adjustment, and
    /// the account is stamped as checked, a match included. Returns the adjustment, if one was needed.
    @discardableResult
    public func reconcile(accountId: UUID, actualMinor: Int64, profileId: UUID) async throws -> UUID? {
        let now = clock()
        return try await write { store in
            let accounts = try store.accounts(profileId: profileId)
            guard var account = accounts.first(where: { $0.id == accountId }) else {
                throw RepositoryError.unknownAccount(accountId)
            }
            let state = Ledger.states([account], try store.postings(profileId: profileId))[accountId]
            // Held at ±Int64.max: a balance too big to add up must not trap here either (D59).
            let delta = Money.subtract(actualMinor, state?.balanceMinor ?? 0)
            var adjustment: UUID?
            if delta != 0 {
                let draft = Draft(type: .adjustment, timestamp: now, accountId: accountId, amountMinor: delta)
                adjustment = try Self.book(draft, profileId: profileId, in: store, at: now)
            }
            account.reconciledAt = now
            try store.save(account, profileId: profileId)
            return adjustment
        }
    }

    // MARK: Inside a transaction

    /// Runs [body] as one transaction that a cancelled caller cannot interrupt: GRDB gives up on a
    /// cancelled task, and a half-asked change should still land, as Android's did.
    @discardableResult
    func write<T: Sendable>(_ body: @escaping @Sendable (Store) throws -> T) async throws -> T {
        let database = database
        return try await Task { try await database.write(body) }.value
    }

    /// Android's `Repo.save` inside [store]'s transaction. Editing keeps the ids of the postings:
    /// the first and second ones the ledger makes (the out-leg and the in-leg of a transfer) reuse
    /// the stored ones in the order they were written, extras go, missing ones are added. Sync
    /// then sees an edit, not a delete and a create.
    static func book(_ draft: Draft, profileId: UUID, in store: Store, at now: Int64) throws -> UUID {
        guard var profile = try store.profile(profileId) else { throw RepositoryError.unknownProfile(profileId) }
        let states = Ledger.states(
            try store.accounts(profileId: profileId),
            try store.postings(profileId: profileId, excludingOperation: draft.id)
        )
        let rates = try rates(store, markup: profile.settings.markup)
        let postings = try Ledger.postings(draft, states, rates)
        let cbr = exchangeRates(draft, states, rates)
        let id = draft.id ?? UUID()
        let stored = try draft.id.flatMap { try store.operation($0, profileId: profileId)?.postings } ?? []

        let operation = GoldaCore.Operation(
            id: id, type: draft.type, timestamp: draft.timestamp, categoryKey: draft.categoryKey,
            note: draft.note.trimmingCharacters(in: .whitespacesAndNewlines), voiceText: draft.voiceText,
            purchaseAmountMinor: draft.purchaseAmountMinor, purchaseCurrency: draft.purchaseCurrency,
            isEstimate: draft.isEstimate, cbrFrom: cbr?.from, cbrTo: cbr?.to
        )
        try store.save(operation, profileId: profileId, updatedAt: now)
        for (index, posting) in postings.enumerated() {
            var posting = posting
            posting.operationId = id
            if stored.indices.contains(index) { posting.id = stored[index].id }
            try store.save(posting, profileId: profileId)
        }
        for extra in stored.dropFirst(postings.count) {
            try store.deletePosting(extra.id, profileId: profileId)
        }

        if let learned = Ledger.learnedMarkup(draft, states, rates) {
            profile.settings.markup = learned
            try store.save(profile)
        }
        return id
    }

    /// Official rates of both currencies of a transfer that changes currency, to measure later what
    /// the exchange cost.
    static func exchangeRates(_ draft: Draft, _ states: [UUID: AccountState], _ rates: Rates) -> (from: Double, to: Double)? {
        guard draft.type == .transfer,
              let from = states[draft.accountId]?.currency,
              let toId = draft.toAccountId, let to = states[toId]?.currency,
              from != to,
              let fromRate = rates.official(from), let toRate = rates.official(to)
        else { return nil }
        return (fromRate, toRate)
    }

    static func rates(_ store: Store, markup: Double) throws -> Rates {
        Rates(Dictionary(uniqueKeysWithValues: try store.rates().map { ($0.code, $0.rubPerUnit) }), markup: markup)
    }

    /// A posting written while its currency had no rate got valued at 0 ₽; once a rate exists it is
    /// valued at today's rate instead, with its own profile's markup.
    static func repairValuations(_ store: Store) throws {
        let table = Dictionary(uniqueKeysWithValues: try store.rates().map { ($0.code, $0.rubPerUnit) })
        for profile in try store.profiles() {
            let unvalued = try store.unvaluedPostings(profileId: profile.id)
            if unvalued.isEmpty { continue }
            let rates = Rates(table, markup: profile.settings.markup)
            let currencies = Dictionary(uniqueKeysWithValues: try store.accounts(profileId: profile.id).map { ($0.id, $0.currency) })
            for var posting in unvalued {
                guard let currency = currencies[posting.accountId], currency != "RUB",
                      let rub = rates.rubMinor(posting.amountMinor, currency)
                else { continue }
                posting.rubMinor = rub
                try store.save(posting, profileId: profile.id)
            }
        }
    }
}

extension RateRecord {
    init(_ rate: CbrRate) {
        self.init(code: rate.code, rubPerUnit: rate.rubPerUnit, date: rate.date)
    }
}
