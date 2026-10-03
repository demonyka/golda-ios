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
    public func export() async throws -> Data {
        let (snapshots, rates) = try await database.read { store -> ([ProfileSnapshot], [RateRecord]) in
            (try store.profiles().compactMap { try store.snapshot(profileId: $0.id) }, try store.rates())
        }
        let backup = Backup(
            exportedAt: milliseconds(now()), device: BackupDevice(deviceSettings.current), profiles: snapshots,
            rates: rates
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
            for existing in try store.profiles() { try store.deleteProfile(existing.id) }
            // Rates belong to no profile, so deleting the profiles does not reach them.
            try RateRecord.deleteAll(store.db)
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
                for obligation in snapshot.obligations { try store.save(obligation, profileId: profileId) }
                // In order: goals are created in the order they are listed.
                for goal in snapshot.goals { try store.save(goal, profileId: profileId) }
                for wish in snapshot.wishes { try store.save(wish, profileId: profileId) }
            }
            guard let first = try store.profiles().first else { throw BackupError.noProfiles }
            return first.id
        }
    }

    private func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded(.down))
    }
}
