import Foundation
import GoldaCore
import GoldaData
import SQLite3
import Testing

@testable import Golda

/// Data that cannot be read puts the failure screen up, never a page that waits forever, and
/// "Try again" opens the app once the cause is gone. The incident behind it: a file with an older
/// shape of a table, whose first snapshot failed while the app sat in its loading phase.
@MainActor @Suite(.timeLimit(.minutes(1))) struct DataFailureTests {
    /// An app over a database file of its own, on a phone through onboarding with "Личный" open.
    @MainActor private final class FileHarness {
        let folder = FileManager.default.temporaryDirectory.appending(path: "golda-failure-\(UUID().uuidString)", directoryHint: .isDirectory)
        let suiteName = "golda.tests.\(UUID().uuidString)"
        let model: AppModel
        let profileId: UUID

        var databasePath: String { folder.appending(path: "golda.sqlite").path(percentEncoded: false) }

        init() async throws {
            let database = try GoldaDatabase.open(at: folder.appending(path: "golda.sqlite"))
            let environment = AppEnvironment(
                database: database,
                deviceSettings: DeviceSettingsStore(defaults: try #require(UserDefaults(suiteName: suiteName))),
                secrets: InMemorySecretStore(),
                ratesSource: StubRatesSource.offline,
                clock: { AppHarness.now },
                zone: { AppHarness.utc },
                voiceQueue: VoiceQueue(directory: folder.appending(path: "voice", directoryHint: .isDirectory))
            )
            let profileId = try await environment.repository.createProfile(name: "Личный").id
            environment.deviceSettings.update {
                $0.onboarded = true
                $0.activeProfileId = profileId
            }
            self.profileId = profileId
            model = AppModel(environment: environment)
        }

        deinit {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
            // The folder stays in the temporary directory: the model and its database outlive this
            // deinit, and SQLite must not have a file it holds open deleted under it.
        }

        /// Runs [sql] on the file through a connection of its own, behind the app's back.
        func execute(_ sql: String) throws {
            var connection: OpaquePointer?
            defer { sqlite3_close(connection) }
            guard sqlite3_open(databasePath, &connection) == SQLITE_OK else { throw SQLiteFailure(sql: sql) }
            sqlite3_busy_timeout(connection, 5_000)
            guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else { throw SQLiteFailure(sql: sql) }
        }
    }

    private struct SQLiteFailure: Error {
        let sql: String
    }

    @Test func booksThatCannotBeReadShowTheFailureAndTryAgainOpensThem() async throws {
        let harness = try await FileHarness()
        // The profiles read fine; the open profile's books do not.
        try harness.execute("ALTER TABLE obligation RENAME TO obligation_gone")

        await harness.model.start()
        await eventually { harness.model.phase.failure != nil }

        #expect(harness.model.phase.failure?.contains("obligation") == true, "\(String(describing: harness.model.phase.failure))")
        #expect(harness.model.data == nil)
        #expect(!harness.model.isLoaded)

        try harness.execute("ALTER TABLE obligation_gone RENAME TO obligation")
        await harness.model.retry()

        await eventually { harness.model.phase.data?.profile.id == harness.profileId }
        #expect(harness.model.phase.failure == nil)
        #expect(harness.model.activeProfileId == harness.profileId)
    }

    @Test func profilesThatCannotBeReadShowTheFailureAtOnce() async throws {
        let harness = try await FileHarness()
        try harness.execute("ALTER TABLE profile RENAME TO profile_gone")

        await harness.model.start()

        // Known when `start` returns: the launch reads themselves failed.
        #expect(harness.model.phase.failure?.contains("profile") == true, "\(String(describing: harness.model.phase.failure))")

        // Still failing: "Try again" shows the failure again rather than an empty app.
        await harness.model.retry()
        #expect(harness.model.phase.failure != nil)

        try harness.execute("ALTER TABLE profile_gone RENAME TO profile")
        await harness.model.retry()

        #expect(harness.model.phase.failure == nil)
        #expect(harness.model.profiles.map(\.name) == ["Личный"])
        await eventually { harness.model.phase.data?.profile.id == harness.profileId }
    }

    /// A working database never shows the failure, and "Try again" without one does nothing.
    @Test func aWorkingDatabaseNeverFails() async throws {
        let harness = try await FileHarness()
        await harness.model.start()
        await eventually { harness.model.phase.data != nil }
        await harness.model.retry()
        #expect(harness.model.phase.failure == nil)
        #expect(harness.model.phase.data?.profile.id == harness.profileId)
    }
}
