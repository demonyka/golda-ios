import Foundation
import GoldaCore
import GRDB

/// Export and import of the whole app state as one file (the iOS counterpart of Android's `Backups`).
///
/// The Gemini key is not here on purpose: this type is not given the secret store, so no file it
/// writes can hold a key and no import can replace or clear one.
public struct Backups: Sendable {
    private let database: GoldaDatabase
    private let deviceSettings: DeviceSettingsStore
    private let now: @Sendable () -> Date

    /// [now] stamps exported files and imported operations; tests hand in a fixed clock.
    public init(database: GoldaDatabase, deviceSettings: DeviceSettingsStore, now: @escaping @Sendable () -> Date = { Date() }) {
        self.database = database
        self.deviceSettings = deviceSettings
        self.now = now
    }

    /// Every profile with all it owns, the rates and the device settings worth carrying, as a
    /// version 2 file. The books are read in one transaction, so the file is a consistent moment.
    /// Throws `BackupError.nothingToExport` when there is no profile, since no file could bring
    /// that state back.
    public func export() async throws -> Data {
        typealias Books = (
            profiles: [ProfileSnapshot], goalCreatedAt: [UUID: Int64], obligationCreatedAt: [UUID: Int64],
            rates: [RateRecord]
        )
        let books = try await database.read { store -> Books in
            let profiles = try store.profiles().compactMap { try store.snapshot(profileId: $0.id) }
            var goalCreatedAt: [UUID: Int64] = [:]
            var obligationCreatedAt: [UUID: Int64] = [:]
            for profile in profiles {
                let id = profile.profile.id
                goalCreatedAt.merge(try store.goalCreationCounters(profileId: id)) { first, _ in first }
                obligationCreatedAt.merge(try store.obligationCreationCounters(profileId: id)) { first, _ in first }
            }
            return (profiles, goalCreatedAt, obligationCreatedAt, try store.rates())
        }
        guard !books.profiles.isEmpty else { throw BackupError.nothingToExport }
        let backup = Backup(
            exportedAt: milliseconds(now()), device: BackupDevice(deviceSettings.current), profiles: books.profiles,
            goalCreatedAt: books.goalCreatedAt, obligationCreatedAt: books.obligationCreatedAt, rates: books.rates
        )
        return try BackupFormat.encode(backup)
    }

    /// Replaces everything with the file's contents. The file is read and checked in full first, so a
    /// broken, cut-off or newer-version file changes nothing, and the replacement itself is one
    /// transaction, so it lands whole or not at all.
    ///
    /// Afterwards the first profile (by `sort`, as the app lists them) is active and the app counts as
    /// onboarded. [personalProfileName] is what an Android file's single set of books is called.
    @discardableResult
    public func `import`(_ data: Data, personalProfileName: String) async throws -> BackupSummary {
        let backup = try BackupFormat.decode(data, personalProfileName: personalProfileName)
        let active = try await apply(backup)

        // After the commit: the device settings are not in the database, so they follow the books
        // only once the books are in. The voice consent and the key stay as the person set them.
        deviceSettings.update { settings in
            backup.device.apply(to: &settings)
            settings.onboarded = true
            settings.activeProfileId = active
            // These pointed into the data that was just replaced.
            settings.lastAccountId = [:]
            settings.celebratedGoalId = [:]
        }
        return BackupSummary(backup, activeProfileId: active)
    }

    /// Wipes profiles (and with them everything they own) and rates, then writes the backup, in one
    /// transaction. Expects a validated backup; the database's own keys are the last line of defence,
    /// and a violation there rolls the wipe back too. Returns the profile the app lists first, which
    /// is the one to make active.
    @discardableResult
    func apply(_ backup: Backup) async throws -> UUID {
        let importedAt = milliseconds(now())
        return try await database.write { store in
            try store.deleteAllProfiles()
            // Rates belong to no profile, so deleting the profiles does not reach them.
            try store.deleteAllRates()
            try store.save(backup.rates)

            for snapshot in backup.profiles {
                let profileId = snapshot.profile.id
                try store.save(snapshot.profile)
                for account in snapshot.accounts { try store.save(account, profileId: profileId) }
                // Listed newest first, stored oldest first: of operations with one timestamp the
                // store shows the last written first, so the first listed must be written last.
                for full in snapshot.operations.reversed() {
                    try store.save(full.op, profileId: profileId, updatedAt: importedAt)
                    for posting in full.postings { try store.save(posting, profileId: profileId) }
                }
                // With a counter a payment or goal takes its original place in the creation order;
                // without one the store counts on from the last, so the listed order becomes the
                // creation order.
                for obligation in snapshot.obligations {
                    try store.save(obligation, profileId: profileId, createdAt: backup.obligationCreatedAt[obligation.id])
                }
                for goal in snapshot.goals {
                    try store.save(goal, profileId: profileId, createdAt: backup.goalCreatedAt[goal.id])
                }
                for wish in snapshot.wishes { try store.save(wish, profileId: profileId) }
                for category in snapshot.categories { try store.save(category, profileId: profileId) }
            }
            guard let first = try store.profiles().first else { throw BackupError.noProfiles }
            return first.id
        }
    }

    private func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded(.down))
    }
}

extension Store {
    /// Each goal's place in its profile's creation order, by goal id. `Goal` carries no such field,
    /// so the backup reads the counters from the rows.
    func goalCreationCounters(profileId: UUID) throws -> [UUID: Int64] {
        try creationCounters(GoalRecord.self, profileId: profileId)
    }

    /// The same for payments, by payment id.
    func obligationCreationCounters(profileId: UUID) throws -> [UUID: Int64] {
        try creationCounters(ObligationRecord.self, profileId: profileId)
    }

    private func creationCounters<Record: CreationOrderedRecord>(_ type: Record.Type, profileId: UUID) throws -> [UUID: Int64] {
        var counters: [UUID: Int64] = [:]
        for record in try Record.owned(by: profileId).fetchAll(db) {
            if let createdAt = record.createdAt { counters[record.id] = createdAt }
        }
        return counters
    }
}
