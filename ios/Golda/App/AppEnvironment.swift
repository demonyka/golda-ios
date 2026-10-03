import Foundation
import GoldaData

/// The composition root: every dependency the app runs on, built once at launch. Screens never
/// build their own; they reach the data through `AppModel`.
struct AppEnvironment: Sendable {
    let database: GoldaDatabase
    let deviceSettings: DeviceSettingsStore
    let secrets: any SecretStore
    let repository: Repository
    let ratesSource: any RatesSource
    /// Where "today" is; read on each use, since the phone travels.
    let zone: @Sendable () -> TimeZone

    init(
        database: GoldaDatabase,
        deviceSettings: DeviceSettingsStore,
        secrets: any SecretStore,
        ratesSource: any RatesSource,
        clock: (@Sendable () -> Int64)? = nil,
        zone: @escaping @Sendable () -> TimeZone = { TimeZone.current }
    ) {
        self.database = database
        self.deviceSettings = deviceSettings
        self.secrets = secrets
        self.ratesSource = ratesSource
        self.zone = zone
        if let clock {
            repository = Repository(database: database, deviceSettings: deviceSettings, secrets: secrets, clock: clock, zone: zone)
        } else {
            repository = Repository(database: database, deviceSettings: deviceSettings, secrets: secrets, zone: zone)
        }
    }

    /// The real thing: the database in Application Support, the settings in the standard defaults,
    /// the keys in the Keychain and the rates from the Bank of Russia.
    static func live() throws -> AppEnvironment {
        AppEnvironment(
            database: try GoldaDatabase.open(at: URL.applicationSupportDirectory.appending(path: "golda.sqlite")),
            deviceSettings: DeviceSettingsStore(defaults: .standard),
            secrets: KeychainSecretStore(),
            ratesSource: CbrRatesSource(transport: URLSessionTransport())
        )
    }

    /// Nothing on disk survives it: a private database, a defaults suite wiped as it opens, keys in
    /// memory. By default the rates source is offline, so tests, previews and UI scenarios never touch
    /// the network and run on the fallback rates. Give each concurrent user its own [defaultsSuite].
    static func inMemory(
        defaultsSuite: String = "golda.inMemory",
        ratesSource: any RatesSource = CbrRatesSource(transport: StubHTTPTransport(error: URLError(.notConnectedToInternet))),
        clock: (@Sendable () -> Int64)? = nil,
        zone: @escaping @Sendable () -> TimeZone = { TimeZone.current }
    ) throws -> AppEnvironment {
        // Nil only for the app's own bundle id or the global domain, never for our suite names.
        guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
            preconditionFailure("UserDefaults refused the suite \(defaultsSuite)")
        }
        // The suite is a file in the sandbox; what an earlier run left there must not leak in.
        defaults.removePersistentDomain(forName: defaultsSuite)
        return AppEnvironment(
            database: try GoldaDatabase.inMemory(),
            deviceSettings: DeviceSettingsStore(defaults: defaults),
            secrets: InMemorySecretStore(),
            ratesSource: ratesSource,
            clock: clock,
            zone: zone
        )
    }

    /// The environment [options] ask for: in memory for UI tests and for the unit-test host, the
    /// real one otherwise.
    static func make(for options: LaunchOptions) throws -> AppEnvironment {
        options.inMemory || options.isHostingTests ? try inMemory() : try live()
    }
}
