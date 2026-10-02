import Foundation
import GoldaCore
import Synchronization
import Testing

@testable import GoldaData

/// Time the tests move by hand.
final class TestClock: Sendable {
    private let millis: Mutex<Int64>

    init(_ millis: Int64) {
        self.millis = Mutex(millis)
    }

    var now: Int64 { millis.withLock { $0 } }

    func set(_ value: Int64) {
        millis.withLock { $0 = value }
    }
}

/// GoldaCore's helper for values computed in floating point.
func expectClose(_ actual: Double, _ expected: Double, _ tolerance: Double, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(abs(actual - expected) <= tolerance, "\(actual) is not within \(tolerance) of \(expected)", sourceLocation: sourceLocation)
}

/// Rates that answer from a closure.
struct StubRatesSource: RatesSource {
    let answer: @Sendable () throws -> [CbrRate]

    func fetch() async throws -> [CbrRate] { try answer() }
}

/// A repository over an in-memory database and its own defaults suite, in UTC, on a clock that
/// stands at 2026-10-02 10:00, the day the Kotlin tests call today.
final class RepositoryHarness {
    static let utc = TimeZone(secondsFromGMT: 0)!
    static let today = LocalDate(2026, 10, 2)
    static let start = today.atTimeMillis(hour: 10, in: utc)

    /// LedgerTest's rates.
    static let rates = [
        RateRecord(code: "USD", rubPerUnit: 83.2454, date: "2026-10-02"),
        RateRecord(code: "GEL", rubPerUnit: 31.9597, date: "2026-10-02"),
        RateRecord(code: "THB", rubPerUnit: 2.47438, date: "2026-10-02"),
    ]

    let suiteName = "golda.tests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let device: DeviceSettingsStore
    let database: GoldaDatabase
    let clock = TestClock(RepositoryHarness.start)
    let repository: Repository

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
        device = DeviceSettingsStore(defaults: defaults)
        database = try GoldaDatabase.inMemory()
        let clock = clock
        repository = Repository(database: database, deviceSettings: device, clock: { clock.now }, zone: { RepositoryHarness.utc })
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    /// A profile with LedgerTest's rates in the table and [accounts] opened without balances.
    func profile(_ name: String = "Личный", accounts: [Account] = [], settings: ProfileSettings = ProfileSettings()) async throws -> UUID {
        try await database.write { try $0.save(RepositoryHarness.rates) }
        let profileId = try await repository.createProfile(name: name, settings: settings).id
        for account in accounts { try await repository.saveAccount(account, profileId: profileId) }
        return profileId
    }

    func snapshot(_ profileId: UUID) async throws -> ProfileSnapshot {
        try #require(try await database.read { try $0.snapshot(profileId: profileId) })
    }

    func operation(_ id: UUID, _ profileId: UUID) async throws -> OperationFull? {
        try await database.read { try $0.operation(id, profileId: profileId) }
    }

    func states(_ profileId: UUID) async throws -> [UUID: AccountState] {
        let books = try await snapshot(profileId)
        return Ledger.states(books.accounts, books.operations.flatMap(\.postings))
    }

    func state(_ accountId: UUID, _ profileId: UUID) async throws -> AccountState {
        try #require(try await states(profileId)[accountId])
    }

    func profileSettings(_ profileId: UUID) async throws -> ProfileSettings {
        try #require(try await database.read { try $0.profile(profileId) }).settings
    }

    func updatedAt(_ operationId: UUID) async throws -> Int64? {
        try await database.writer.read { db in try OperationRecord.fetchOne(db, id: operationId)?.updatedAt }
    }
}
