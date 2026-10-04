import Foundation
import GoldaCore
import GoldaData

/// The composition root: every dependency the app runs on, built once at launch. Screens never
/// build their own; they reach the data through `AppModel`.
struct AppEnvironment: Sendable {
    let database: GoldaDatabase
    let deviceSettings: DeviceSettingsStore
    let secrets: any SecretStore
    let repository: Repository
    let ratesSource: any RatesSource
    /// Epoch milliseconds now, the same clock the repository stamps operations with, so "today" on
    /// screen is the day the books were written on (and a test can stop it).
    let clock: @Sendable () -> Int64
    /// Where "today" is; read on each use, since the phone travels.
    let zone: @Sendable () -> TimeZone
    /// Voice notes waiting to be understood, one file each.
    let voiceQueue: VoiceQueue
    /// Understands the notes, one at a time, for the whole app: the mic and the queue share it, so
    /// two notes never book at once and every outcome reaches the one place that announces it.
    let voice: VoiceService
    /// Where `voice` reads the Gemini key: the Keychain's store, or the debug stub's own. Whether a
    /// note can be understood at once is asked of this one.
    let voiceKeys: any SecretStore
    /// The system's local notifications; in memory unless the environment is the real one.
    let notifications: any NotificationCenterClient
    /// What the widgets read (`TodayWidgetPublisher`); in memory unless the environment is the real one.
    let widgets: WidgetChannel

    /// [voiceProvider] defaults to Gemini with the key in [secrets]; [voiceSecrets] lets the debug
    /// stub give the service a key of its own without writing one where the real key lives.
    init(
        database: GoldaDatabase,
        deviceSettings: DeviceSettingsStore,
        secrets: any SecretStore,
        ratesSource: any RatesSource,
        clock: (@Sendable () -> Int64)? = nil,
        zone: @escaping @Sendable () -> TimeZone = { TimeZone.current },
        voiceQueue: VoiceQueue = .live,
        voiceProvider: (any VoiceProvider)? = nil,
        voiceSecrets: (any SecretStore)? = nil,
        notifications: (any NotificationCenterClient)? = nil,
        widgets: WidgetChannel? = nil
    ) {
        self.database = database
        self.notifications = notifications ?? InMemoryNotificationCenter()
        self.widgets = widgets ?? .inMemory()
        self.deviceSettings = deviceSettings
        self.secrets = secrets
        self.ratesSource = ratesSource
        self.zone = zone
        let clock = clock ?? { Int64(Date().timeIntervalSince1970 * 1000) }
        self.clock = clock
        let repository = Repository(database: database, deviceSettings: deviceSettings, secrets: secrets, clock: clock, zone: zone)
        self.repository = repository
        self.voiceQueue = voiceQueue
        voiceKeys = voiceSecrets ?? secrets
        voice = VoiceService(
            repository: repository,
            provider: voiceProvider ?? GeminiProvider(secrets: secrets),
            secrets: voiceSecrets ?? secrets,
            deviceSettings: deviceSettings,
            queue: voiceQueue,
            unnamedPurchase: String(localized: "Purchase", table: "Voice", comment: "Title of a purchase to weigh up when the voice note named none."),
            clock: clock,
            zone: zone
        )
    }

    /// The day it is now where the phone is.
    func today() -> LocalDate {
        LocalDate(epochMillis: clock(), in: zone())
    }

    /// The real thing: the database in Application Support, the settings in the standard defaults,
    /// the keys in the Keychain and the rates from the Bank of Russia, with the currencies it does
    /// not publish filled in from the currency API.
    static func live(voiceProvider: (any VoiceProvider)? = nil, voiceSecrets: (any SecretStore)? = nil) throws -> AppEnvironment {
        AppEnvironment(
            database: try GoldaDatabase.open(
                at: URL.applicationSupportDirectory.appending(path: "golda.sqlite"),
                eraseDatabaseOnSchemaChange: erasesStaleDatabase
            ),
            deviceSettings: DeviceSettingsStore(defaults: .standard),
            secrets: KeychainSecretStore(),
            ratesSource: MergedRatesSource.live(),
            voiceQueue: .live,
            voiceProvider: voiceProvider,
            voiceSecrets: voiceSecrets,
            notifications: UserNotificationCenterClient(),
            widgets: .appGroup()
        )
    }

    /// Nothing on disk survives it: a private database, a defaults suite wiped as it opens, keys in
    /// memory, voice notes in a temporary folder of their own. By default the rates source is
    /// offline, so tests, previews and UI scenarios never touch the network and run on the fallback
    /// rates; with no key, voice notes wait. The widgets' snapshot goes to [defaultsSuite] too, with
    /// [reloadWidgets] hearing the reloads, unless [widgets] is given. Give each concurrent user its
    /// own [defaultsSuite].
    static func inMemory(
        defaultsSuite: String = "golda.inMemory",
        ratesSource: any RatesSource = CbrRatesSource(transport: StubHTTPTransport(error: URLError(.notConnectedToInternet))),
        clock: (@Sendable () -> Int64)? = nil,
        zone: @escaping @Sendable () -> TimeZone = { TimeZone.current },
        voiceProvider: (any VoiceProvider)? = nil,
        voiceSecrets: (any SecretStore)? = nil,
        notifications: (any NotificationCenterClient)? = nil,
        widgets: WidgetChannel? = nil,
        reloadWidgets: @escaping @MainActor @Sendable () -> Void = {}
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
            zone: zone,
            voiceQueue: VoiceQueue(directory: FileManager.default.temporaryDirectory.appending(
                path: "golda-voice-\(UUID().uuidString)", directoryHint: .isDirectory
            )),
            voiceProvider: voiceProvider,
            voiceSecrets: voiceSecrets,
            notifications: notifications,
            widgets: widgets ?? WidgetChannel(store: TodaySnapshotStore(defaults: defaults), reload: reloadWidgets)
        )
    }

    /// Whether a database file whose recorded migrations now build a different schema is wiped and
    /// built afresh. Schema v1 is unreleased and still edited in place, which leaves the files of
    /// earlier builds with its old shape: the migrator counts v1 as applied and every read of a
    /// changed table fails. Only the simulator wipes, as no real data can live there; a debug build
    /// on a real iPhone, let alone a release, never erases anything.
    static var erasesStaleDatabase: Bool {
        #if DEBUG && targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    /// The environment [options] ask for: in memory for UI tests and for the unit-test host, the
    /// real one otherwise. A debug build launched with `-golda.voiceStub=<script>` answers voice
    /// notes with the stub's script instead of Gemini, and one launched with `-golda.failDatabase`
    /// fails to open its data. In memory, notifications stay in memory too, unless
    /// `-golda.liveNotifications` (or `-golda.remindSoon`) asks for the system's, and so does what
    /// the widgets read, unless `-golda.liveWidgets` asks for the App Group.
    static func make(for options: LaunchOptions) throws -> AppEnvironment {
        #if DEBUG
        if options.failsDatabase { throw DebugDatabaseFailure() }
        let stub = VoiceStubOptions.current
        let provider = stub?.provider, secrets = stub?.secrets
        // `-golda.liveNotifications`: a UI run over in-memory books that needs a real delivery.
        let delivers = ReminderDebugOptions.current.usesLiveNotifications && !options.isHostingTests
        let notifications: (any NotificationCenterClient)? = delivers ? UserNotificationCenterClient() : nil
        // `-golda.liveWidgets`: a UI run over in-memory books that shows them on the widgets.
        let showsWidgets = ProcessInfo.processInfo.arguments.contains("-golda.liveWidgets") && !options.isHostingTests
        let widgets: WidgetChannel? = showsWidgets ? .appGroup() : nil
        #else
        let provider: (any VoiceProvider)? = nil, secrets: (any SecretStore)? = nil
        let notifications: (any NotificationCenterClient)? = nil
        let widgets: WidgetChannel? = nil
        #endif
        return options.inMemory || options.isHostingTests
            ? try inMemory(voiceProvider: provider, voiceSecrets: secrets, notifications: notifications, widgets: widgets)
            : try live(voiceProvider: provider, voiceSecrets: secrets)
    }
}

#if DEBUG
/// What `-golda.failDatabase` makes opening the data throw.
struct DebugDatabaseFailure: Error, CustomStringConvertible {
    var description: String { "-golda.failDatabase: the data failed to open on purpose" }
}
#endif
