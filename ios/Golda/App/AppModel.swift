import Foundation
import GoldaCore
import GoldaData
import Observation
import OSLog

private let log = Logger(subsystem: "com.f4studio.golda", category: "AppModel")

/// What "Отменить" needs after an operation was deleted: the rows, and the profile they came from,
/// so the undo lands there even when another profile has been opened since.
struct OperationUndoToken: Equatable, Sendable {
    let profileId: UUID
    let deleted: DeletedOperation
}

enum AppModelError: Error, Equatable, Sendable {
    /// A change to the books was asked for while no profile is open (before onboarding makes one).
    case noProfileOpen
}

/// The state every screen reads: the profiles, the active one and its `AppData`, kept current by
/// observing the database and this phone's settings. The iOS side of Android's `GoldaRoot`.
///
/// The intents are thin on purpose: the repository decides, the model only says which profile.
/// Changes to the books go to the profile on screen (D23).
@MainActor @Observable
final class AppModel {
    enum Phase {
        /// Before the first read; nothing to draw yet.
        case loading
        /// No profile or not onboarded: the three steps of the first launch.
        case onboarding
        case main(AppData)
        /// The data could not be read: the failure screen, with "Try again". [reason] is the
        /// technical message, which only debug builds show.
        case failed(reason: String)
    }

    @ObservationIgnored let environment: AppEnvironment
    /// The local notifications of every profile (`AppModel+Reminders`).
    let reminders: ReminderScheduler
    /// The snapshot the «Можно сегодня» widgets read (`AppModel+Widgets`).
    @ObservationIgnored let widgets: TodayWidgetPublisher
    /// Sync and sharing of the profiles (`AppSync`, `AppModel+Sharing`).
    let sync: AppSync

    /// By `sort`, then id.
    private(set) var profiles: [Profile] = []
    /// This phone's part of the settings, current.
    private(set) var device: DeviceSettings
    /// The profile everything shows: the one remembered on this phone, or the first one when that
    /// one is gone.
    private(set) var activeProfileId: UUID?
    /// The active profile's books; it trails `activeProfileId` by one database read after a switch.
    private(set) var data: AppData?
    /// The profiles have been read once.
    private(set) var isLoaded = false
    /// Why the data could not be read, until "Try again" reads it.
    private(set) var failureReason: String?

    @ObservationIgnored private var snapshot: ProfileSnapshot?
    @ObservationIgnored private var rateTable: [RateRecord] = []
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var snapshotTask: Task<Void, Never>?
    /// Remembered profiles missing from the list, being looked up.
    @ObservationIgnored private var checkingProfileIds: Set<UUID> = []
    @ObservationIgnored private var started = false
    @ObservationIgnored private var isBeginningOnboarding = false

    init(environment: AppEnvironment) {
        self.environment = environment
        reminders = ReminderScheduler(environment: environment)
        widgets = TodayWidgetPublisher(environment: environment)
        sync = AppSync(database: environment.database, backend: environment.syncBackend, clock: environment.clock)
        device = environment.deviceSettings.current
        // A profile that arrived through an invitation opens at once.
        sync.onJoined = { [weak self] profileId in self?.joined(profileId) }
    }

    isolated deinit {
        tasks.forEach { $0.cancel() }
        snapshotTask?.cancel()
    }

    var activeProfile: Profile? { profiles.first { $0.id == activeProfileId } }

    var phase: Phase {
        if let failureReason { return .failed(reason: failureReason) }
        guard isLoaded else { return .loading }
        guard device.onboarded, !profiles.isEmpty else { return .onboarding }
        return data.map(Phase.main) ?? .loading
    }

    /// The first profile's name, from onboarding or a debug command.
    static var firstProfileName: String {
        String(localized: "Personal", comment: "Name of the first profile, created on the first launch.")
    }

    // MARK: Launch

    /// Launch work, done once: the debug [command], then `load`. Returns once the profiles are
    /// known, or once reading them failed.
    func start(command: LaunchCommand? = nil, profileName: String = AppModel.firstProfileName) async {
        guard !started else { return }
        started = true
        #if DEBUG
        // Before anything is read, so the screens open on the data the command builds.
        if let command { await run(command, profileName: profileName) }
        #endif
        await load()
    }

    /// "Try again" on the failure screen: the launch reads once more, on the same database. The
    /// debug command does not run again.
    func retry() async {
        guard started, failureReason != nil else { return }
        failureReason = nil
        await load()
    }

    /// The data could not be read: following the database stops, and the failure screen replaces
    /// whatever was on screen, since none of it can be trusted to be current any more.
    func fail(_ error: any Error) {
        log.error("The data could not be read: \(String(describing: error))")
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        snapshotTask?.cancel()
        snapshotTask = nil
        // Forgotten, so the next `load` opens the profile afresh and follows its books again.
        activeProfileId = nil
        snapshot = nil
        data = nil
        isLoaded = false
        failureReason = String(describing: error)
    }

    /// The seed rates, the rates and the profiles, then the observers, and fresh rates in the
    /// background. The rates from the network never hold it up, and failing to get them is silent;
    /// failing to read the database is not.
    private func load() async {
        do {
            try await environment.repository.ensureSeed()
        } catch {
            // A full disk refuses the seed but may still read: whether the books can be read decides.
            log.error("Seeding the rates failed: \(String(describing: error))")
        }
        do {
            rateTable = try await environment.database.read { try $0.rates() }
            let fresh = try await environment.database.read { try $0.profiles() }
            if fresh != profiles { profiles = fresh }
        } catch {
            fail(error)
            return
        }
        device = environment.deviceSettings.current
        isLoaded = true
        resolveActiveProfile()
        observe()
        tasks.append(Task { [weak self] in await self?.refreshRates() })
    }

    #if DEBUG
    /// `-golda.demo`, `-golda.samples`, `-golda.reset`. Each one erases everything first.
    private func run(_ command: LaunchCommand, profileName: String) async {
        let repository = environment.repository
        do {
            switch command {
            case .demo: try await Demo.fill(repository, profileName: profileName)
            case .samples: try await Demo.samples(repository, profileName: profileName)
            case .reset: try await repository.resetAll()
            }
        } catch {
            log.error("The launch command \(command.rawValue) failed: \(String(describing: error))")
        }
    }
    #endif

    // MARK: Profiles

    /// Opens [id] everywhere: the four tabs, "+" and voice. This phone remembers it.
    func switchProfile(to id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        environment.deviceSettings.update { $0.activeProfileId = id }
        applyDeviceSettings()
    }

    /// A new profile after the others, opened at once.
    @discardableResult
    func createProfile(name: String) async throws -> Profile {
        let profile = try await environment.repository.createProfile(name: name)
        // Read back rather than wait for the observer, so the switch below finds the new profile.
        await reloadProfiles()
        switchProfile(to: profile.id)
        return profile
    }

    func renameProfile(_ id: UUID, to name: String) async throws {
        try await environment.repository.renameProfile(id, to: name)
    }

    /// Deletes the profile with everything it owns. When it was the active one, the first profile
    /// left takes over, here and in this phone's settings. The last profile cannot go
    /// (`RepositoryError.lastProfile`).
    func deleteProfile(_ id: UUID) async throws {
        try await environment.repository.deleteProfile(id)
        await reloadProfiles()
        applyDeviceSettings()
    }

    /// The first profile, unless one exists already, opened: the steps of onboarding set it up
    /// through its books, so it is there from the first of them, while the app stays closed until
    /// `finishOnboarding`. A profile left by an earlier launch that never finished is the one
    /// the steps continue with.
    func beginOnboarding(profileName: String = AppModel.firstProfileName) async throws {
        // The screen's task can run twice; a second profile would be a duplicate nobody sees.
        guard !isBeginningOnboarding else { return }
        isBeginningOnboarding = true
        defer { isBeginningOnboarding = false }
        await reloadProfiles()
        // A profile someone shared through the invitation that installed the app is not the
        // person's own: the steps set up their own one, never another person's income.
        await sync.reloadZones()
        let own = profiles.filter { !sync.isParticipant(in: $0.id) }
        if let first = own.first {
            if sync.isParticipant(in: activeProfileId ?? first.id) { switchProfile(to: first.id) }
            return
        }
        try await createProfile(name: profileName)
    }

    /// The last step's "Готово": the app opens on the profile the steps set up.
    func finishOnboarding() {
        environment.deviceSettings.update { $0.onboarded = true }
        applyDeviceSettings()
        // The Sunday reminder is on from the start, so its first need is now (D49).
        if device.reconcileReminder { askForNotifications() }
    }

    // MARK: Books of the profile on screen

    /// Records [draft], or replaces the operation with its id; returns the operation id.
    @discardableResult
    func save(_ draft: Draft) async throws -> UUID {
        let profileId = try profileOnScreen()
        return try await environment.repository.save(draft, profileId: profileId)
    }

    /// Deletes the operation; the token brings it back through `restoreOperation`. Nil when there
    /// was no such operation.
    func deleteOperation(_ id: UUID) async throws -> OperationUndoToken? {
        let profileId = try profileOnScreen()
        let deleted = try await environment.repository.deleteOperation(id, profileId: profileId)
        return deleted.map { OperationUndoToken(profileId: profileId, deleted: $0) }
    }

    func restoreOperation(_ token: OperationUndoToken) async throws {
        try await environment.repository.restoreOperation(token.deleted, profileId: token.profileId)
    }

    /// Adds [account] with [openingMinor] booked as its opening balance, or updates the account with
    /// its id (the opening balance is then ignored, and the reconcile stamp stays as stored).
    func saveAccount(_ account: Account, openingMinor: Int64?) async throws {
        let profileId = try profileOnScreen()
        try await environment.repository.saveAccount(account, profileId: profileId, openingMinor: openingMinor)
        askForNotifications(after: account)
    }

    /// Deletes the account with every operation that touches it, both sides of its transfers included.
    func deleteAccount(_ id: UUID) async throws {
        let profileId = try profileOnScreen()
        try await environment.repository.deleteAccount(id, profileId: profileId)
    }

    /// Brings the account to what the bank shows; returns the adjustment, if one was needed.
    @discardableResult
    func reconcile(accountId: UUID, actualMinor: Int64) async throws -> UUID? {
        let profileId = try profileOnScreen()
        return try await environment.repository.reconcile(accountId: accountId, actualMinor: actualMinor, profileId: profileId)
    }

    // MARK: Rates

    /// Fresh rates from the Bank of Russia. False when there are none to be had; no network is not
    /// an error, and the rates already stored stay.
    @discardableResult
    func refreshRates() async -> Bool {
        let fresh: Bool
        do {
            fresh = try await environment.repository.refreshRates(from: environment.ratesSource)
        } catch {
            log.error("Storing fresh rates failed: \(String(describing: error))")
            return false
        }
        // The database does not observe rates, so the model rereads them after a change it made.
        if fresh { await reloadRates() }
        return fresh
    }

    // MARK: Observing

    private func observe() {
        let profileUpdates = environment.database.profiles()
        let deviceUpdates = environment.deviceSettings.changes()
        tasks.append(Task { [weak self] in
            do {
                for try await profiles in profileUpdates {
                    guard let self else { return }
                    if self.profiles != profiles { self.profiles = profiles }
                    self.resolveActiveProfile()
                    // Another profile makes the widgets name the one on screen.
                    self.publishWidgets()
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.fail(error)
            }
        })
        tasks.append(Task { [weak self] in
            // Only a signal: the store's current value is newer than a value that waited in the
            // stream while a switch was applied directly.
            for await _ in deviceUpdates {
                guard let self else { return }
                self.applyDeviceSettings()
            }
        })
    }

    func applyDeviceSettings() {
        let current = environment.deviceSettings.current
        guard current != device else { return }
        device = current
        resolveActiveProfile()
        // Currencies and the last-used account are part of `AppData`.
        rebuild()
    }

    /// Follows the remembered profile, or the first one when it is not in the list.
    private func resolveActiveProfile() {
        let remembered = device.activeProfileId
        let active = profiles.first { $0.id == remembered } ?? profiles.first
        if let remembered, active?.id != remembered, !checkingProfileIds.contains(remembered) {
            checkingProfileIds.insert(remembered)
            Task { [weak self] in await self?.forgetIfGone(remembered) }
        }
        guard active?.id != activeProfileId else { return }
        activeProfileId = active?.id
        observeSnapshots(of: active?.id)
    }

    /// The remembered profile is missing from the list: deleted (here, or later by sync), or created
    /// a moment ago and not yet in an observed list. A fresh read tells which; only a profile that
    /// is really gone hands the phone's choice to the first one left.
    private func forgetIfGone(_ id: UUID) async {
        defer { checkingProfileIds.remove(id) }
        let current: [Profile]
        do {
            current = try await environment.database.read { try $0.profiles() }
        } catch {
            log.error("Reading the profiles failed: \(String(describing: error))")
            return
        }
        guard !current.contains(where: { $0.id == id }) else { return }
        environment.deviceSettings.update { device in
            if device.activeProfileId == id { device.activeProfileId = current.first?.id }
        }
        applyDeviceSettings()
    }

    /// The old profile stays on screen until the new one's first snapshot arrives, so a switch
    /// does not flash an empty screen. The stream ends when the profile is deleted; the profile
    /// list then moves the app to another one. A stream that fails, the first snapshot included,
    /// puts the failure screen up: waiting for books that cannot be read would be a blank screen
    /// forever.
    private func observeSnapshots(of profileId: UUID?) {
        snapshotTask?.cancel()
        guard let profileId else {
            snapshot = nil
            rebuild()
            return
        }
        let snapshots = environment.database.snapshots(profileId: profileId)
        snapshotTask = Task { [weak self] in
            do {
                for try await snapshot in snapshots {
                    guard let self, self.activeProfileId == profileId else { return }
                    self.snapshot = snapshot
                    self.rebuild()
                }
            } catch {
                guard !Task.isCancelled, let self, self.activeProfileId == profileId else { return }
                self.fail(error)
            }
        }
    }

    private func rebuild() {
        guard let snapshot else {
            data = nil
            return
        }
        data = AppData(snapshot: snapshot, device: device, rates: rateTable, zone: environment.zone())
        publishWidgets()
    }

    func reloadProfiles() async {
        do {
            let fresh = try await environment.database.read { try $0.profiles() }
            if fresh != profiles { profiles = fresh }
        } catch {
            log.error("Reading the profiles failed: \(String(describing: error))")
        }
    }

    func reloadRates() async {
        do {
            rateTable = try await environment.database.read { try $0.rates() }
            rebuild()
        } catch {
            log.error("Reading the rates failed: \(String(describing: error))")
        }
    }

    /// The profile whose books are on screen: every change to the books goes there (D23).
    func profileOnScreen() throws -> UUID {
        guard let id = data?.profile.id else { throw AppModelError.noProfileOpen }
        return id
    }
}
