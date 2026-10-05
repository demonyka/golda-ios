import Foundation
import GoldaCore
import GoldaData
import Synchronization
import Testing

@testable import GoldaSync

/// A clock the tests move by hand, in ms since 1970; it starts at 2026-10-02 10:00 UTC.
final class TestClock: Sendable {
    static let utc = TimeZone(secondsFromGMT: 0)!
    static let today = LocalDate(2026, 10, 2)
    private let value = Mutex(TestClock.today.atTimeMillis(hour: 10, in: TestClock.utc))

    var now: Int64 { value.withLock { $0 } }

    func advance(_ ms: Int64) { value.withLock { $0 += ms } }

    var reader: @Sendable () -> Int64 { { [self] in now } }
}

/// One person's phone: the books, this phone's settings, sync over the shared in-memory cloud.
final class Phone: Sendable {
    let user: String
    let database: GoldaDatabase
    let device: DeviceSettingsStore
    let repository: Repository
    let store: SyncStore
    let transport: InMemorySyncTransport
    let service: SyncService
    private let suite: String

    init(_ user: String, cloud: InMemoryCloud, clock: TestClock, database: GoldaDatabase? = nil) async throws {
        self.user = user
        suite = "golda.sync.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        device = DeviceSettingsStore(defaults: defaults)
        self.database = try database ?? GoldaDatabase.inMemory(clock: clock.reader)
        repository = Repository(
            database: self.database, deviceSettings: device, secrets: InMemorySecretStore(), clock: clock.reader, zone: { TestClock.utc }
        )
        try await repository.ensureSeed()
        store = SyncStore(database: self.database)
        transport = InMemorySyncTransport(cloud: cloud, user: user, store: store, now: clock.reader)
        service = SyncService(store: store, transport: transport, now: clock.reader)
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suite)
    }

    /// Opens the app: sync starts when iCloud is there.
    func launch() async {
        await service.start()
    }

    /// Sends what is due and fetches what changed, as the engines do on their own.
    func sync() async throws {
        try await service.syncNow()
    }

    func profiles() async throws -> [Profile] {
        try await database.read { try $0.profiles() }
    }

    func books(_ profileId: UUID) async throws -> ProfileSnapshot? {
        try await database.read { try $0.snapshot(profileId: profileId) }
    }

    /// Each account's balance, by name.
    func balances(_ profileId: UUID) async throws -> [String: Int64] {
        let books = try #require(try await books(profileId))
        let states = Ledger.states(books.accounts, books.operations.flatMap(\.postings))
        return Dictionary(uniqueKeysWithValues: books.accounts.map { ($0.name, states[$0.id]?.balanceMinor ?? 0) })
    }

    /// «Можно сегодня» of the profile, as Home counts it, with this phone's settings.
    func safeToSpend(_ profileId: UUID, at now: Int64) async throws -> Today {
        let books = try #require(try await books(profileId))
        let rates = try await repository.rates(profileId: profileId)
        let day = LocalDate(epochMillis: now, in: TestClock.utc)
        let start = day.startOfDayMillis(in: TestClock.utc)
        let states = Ledger.states(books.accounts, books.operations.flatMap(\.postings))
        return Budget.today(
            states: states,
            operations: books.operations.filter { $0.op.timestamp >= start },
            settings: Settings(profile: books.profile.settings, device: device.current, profileId: profileId),
            today: day, zone: TestClock.utc,
            obligations: books.obligations + Debts.obligations(books.accounts, states),
            rates: rates
        )
    }
}

extension Account {
    static func card(_ name: String, currency: String = "RUB", sort: Int = 0) -> Account {
        Account(name: name, currency: currency, type: .card, includeInFree: true, sort: sort)
    }
}
