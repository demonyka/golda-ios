import Foundation
import GoldaCore
import Testing

@testable import GoldaData

/// A database, device settings in a throwaway suite, a secret store and a `Backups` on top of them
/// with a fixed clock, so exports are comparable byte for byte.
final class BackupHarness {
    static let clock = Date(timeIntervalSince1970: 1_790_100_000)

    let database: GoldaDatabase
    let device: DeviceSettingsStore
    let secrets = InMemorySecretStore()
    let backups: Backups
    private let suiteName = "golda.tests.backup.\(UUID().uuidString)"
    private let defaults: UserDefaults

    init(clock: Date = BackupHarness.clock) throws {
        database = try GoldaDatabase.inMemory()
        defaults = try #require(UserDefaults(suiteName: suiteName))
        device = DeviceSettingsStore(defaults: defaults)
        backups = Backups(database: database, deviceSettings: device, now: { clock })
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func snapshots() async throws -> [ProfileSnapshot] {
        try await database.read { store -> [ProfileSnapshot] in
            try store.profiles().compactMap { try store.snapshot(profileId: $0.id) }
        }
    }

    func rates() async throws -> [RateRecord] {
        try await database.read { try $0.rates() }
    }

    /// Every goal's creation counter, by goal id, over all profiles.
    func goalCounters() async throws -> [UUID: Int64] {
        try await database.read { store -> [UUID: Int64] in
            var all: [UUID: Int64] = [:]
            for profile in try store.profiles() {
                all.merge(try store.goalCreationCounters(profileId: profile.id)) { first, _ in first }
            }
            return all
        }
    }

    /// Every payment's creation counter, by payment id, over all profiles.
    func obligationCounters() async throws -> [UUID: Int64] {
        try await database.read { store -> [UUID: Int64] in
            var all: [UUID: Int64] = [:]
            for profile in try store.profiles() {
                all.merge(try store.obligationCreationCounters(profileId: profile.id)) { first, _ in first }
            }
            return all
        }
    }

    /// The goal names of [profileId] with the counters they hold, oldest first.
    func goalNamesByAge(_ profileId: UUID) async throws -> [String] {
        let goals = try await database.read { try $0.goals(profileId: profileId) }
        let counters = try await goalCounters()
        return goals.sorted { (counters[$0.id] ?? 0) < (counters[$1.id] ?? 0) }.map(\.name)
    }

    /// A repository over the same database and device settings, for the changes the tests make
    /// the way the app does.
    func repository() -> Repository {
        Repository(database: database, deviceSettings: device, secrets: InMemorySecretStore())
    }

    /// The only snapshot, for the tests of a one-profile import.
    func onlySnapshot() async throws -> ProfileSnapshot {
        let all = try await snapshots()
        try #require(all.count == 1)
        return all[0]
    }

    @discardableResult
    func importAndroidFixture(name: String = "Личный") async throws -> BackupSummary {
        try await backups.import(BackupFixtures.androidV1(), personalProfileName: name)
    }

    /// A second profile with a bit of everything and settings that differ from the defaults, so a
    /// round trip has something to lose.
    func seedFamilyProfile() async throws {
        let family = StoreFixture.id(900)
        try await database.write { store in
            try store.save(
                Profile(
                    id: family, name: "Семья", sort: 1,
                    settings: ProfileSettings(
                        incomeHourly: false, hourlyRate: 0, monthlySalary: 250_000.5, taxPercent: 13, hoursPerWeek: 36,
                        payday: 25,
                        // Not representable in a short decimal: it must survive the text.
                        markup: 0.1 + 0.2
                    )
                )
            )
            try store.save(
                Account(
                    id: StoreFixture.id(901), name: "Общая карта", currency: "RUB", type: .card, includeInFree: true,
                    sort: 0, reconciledAt: 1_789_000_000_000
                ),
                profileId: family
            )
            try store.save(
                Account(
                    id: StoreFixture.id(902), name: "Копилка $", currency: "USD", type: .savings, groupName: "Копилки",
                    includeInFree: false, interestRate: 4.5, sort: 1
                ),
                profileId: family
            )
            try store.save(
                Account(
                    id: StoreFixture.id(903), name: "Ипотека", currency: "RUB", type: .loan, includeInFree: false,
                    interestRate: 9.1, sort: 2, paymentDay: 12, paymentMinor: 4_500_000, graceUntil: 20_800,
                    creditLimitMinor: 30_000_000
                ),
                profileId: family
            )
            // Two notes from one voice message share a timestamp; the later one is listed first.
            try store.book(
                GoldaCore.Operation(
                    id: StoreFixture.id(910), type: .expense, timestamp: 1_789_500_000_000, categoryKey: "groceries",
                    note: "Хлеб", voiceText: "хлеб и молоко"
                ),
                [Posting(id: StoreFixture.id(911), operationId: StoreFixture.id(910), accountId: StoreFixture.id(901), amountMinor: -9_000, rubMinor: -9_000)],
                profileId: family
            )
            try store.book(
                GoldaCore.Operation(
                    id: StoreFixture.id(912), type: .expense, timestamp: 1_789_500_000_000, categoryKey: "groceries",
                    note: "Молоко", voiceText: "хлеб и молоко"
                ),
                [Posting(id: StoreFixture.id(913), operationId: StoreFixture.id(912), accountId: StoreFixture.id(901), amountMinor: -8_000, rubMinor: -8_000)],
                profileId: family
            )
            try store.book(
                GoldaCore.Operation(
                    id: StoreFixture.id(914), type: .transfer, timestamp: 1_789_000_000_000, note: "В копилку",
                    purchaseAmountMinor: 12_345, purchaseCurrency: "EUR", isEstimate: true, cbrFrom: 1.0, cbrTo: 83.1 + 0.15
                ),
                [
                    Posting(id: StoreFixture.id(916), operationId: StoreFixture.id(914), accountId: StoreFixture.id(901), amountMinor: -830_000, rubMinor: -830_000),
                    Posting(id: StoreFixture.id(915), operationId: StoreFixture.id(914), accountId: StoreFixture.id(902), amountMinor: 10_000, rubMinor: 830_000),
                ],
                profileId: family
            )
            try store.save(Obligation(id: StoreFixture.id(920), name: "Ипотека", amountMinor: 4_500_000, currency: "RUB", dayOfMonth: 12), profileId: family)
            try store.save(Goal(id: StoreFixture.id(930), name: "Ремонт", targetMinor: 90_000_000, currency: "RUB", accountId: StoreFixture.id(902), savedMinor: 1_000), profileId: family)
            try store.save(Goal(id: StoreFixture.id(931), name: "Машина", targetMinor: 120_000_000, currency: "RUB", savedMinor: 5_000, isMain: true), profileId: family)
            try store.save(
                Wish(id: StoreFixture.id(940), title: "Пылесос", amountMinor: 3_000_000, currency: "RUB", createdAt: 1_789_000_000_000, decideAt: 1_790_500_000_000),
                profileId: family
            )
            try store.save([RateRecord(code: "USD", rubPerUnit: 83.25, date: "2026-09-21"), RateRecord(code: "EUR", rubPerUnit: 90.4, date: "2026-09-21")])
        }
    }
}

enum BackupFixtures {
    /// A hand-written file in the exact shape the Android app exports (see `Fixtures/`).
    static func androidV1() throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: "android-backup-v1", withExtension: "json", subdirectory: "Fixtures")
        )
        return try Data(contentsOf: url)
    }

    /// The fixture as a dictionary, for tests that tamper with it.
    static func androidV1Object() throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: androidV1()) as? [String: Any])
    }

    static func data(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    /// The object after [change], as file bytes.
    static func edit(_ data: Data, _ change: (inout [String: Any]) throws -> Void) throws -> Data {
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        try change(&object)
        return try Self.data(object)
    }

    /// Every JSON object in [value] gets a key a future version might add.
    static func addingUnknownKeys(_ value: Any) -> Any {
        if var object = value as? [String: Any] {
            object = object.mapValues(addingUnknownKeys)
            object["futureKey"] = ["nested": [1, 2, 3], "flag": true] as [String: Any]
            return object
        }
        if let array = value as? [Any] { return array.map(addingUnknownKeys) }
        return value
    }
}

extension ProfileSnapshot {
    func account(named name: String) throws -> Account {
        try #require(accounts.first { $0.name == name }, "no account named \(name)")
    }

    func operation(noted note: String) throws -> OperationFull {
        try #require(operations.first { $0.op.note == note }, "no operation noted \(note)")
    }

    var postings: [Posting] { operations.flatMap(\.postings) }
}
