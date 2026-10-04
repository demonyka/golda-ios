import Foundation
import GoldaCore
import GoldaData
import Observation
import OSLog
import UIKit
import UserNotifications

private let log = Logger(subsystem: "com.f4studio.golda", category: "Reminders")

/// Keeps the system's pending notifications equal to the plan of every profile (ARCHITECTURE,
/// "Вне приложения"). iOS cannot run the app when a reminder is due, as Android's workers do, so
/// the plan is made ahead: at launch and on coming back to the app, after any change to the books
/// or to the Sunday switch, and in the background refresh. Each plan replaces only what changed.
///
/// It also holds the reminder tapped last until the tabs have shown it (`AppModel.openReminder`).
@MainActor @Observable
final class ReminderScheduler {
    /// A tapped reminder the tabs have not shown yet.
    var pendingTap: ReminderTap?

    /// The language the notifications are written in; tests fix one.
    @ObservationIgnored var locale: () -> Locale = { .current }
    /// How long the books must stay still before they are planned again: a save writes in steps.
    @ObservationIgnored var debounce: Duration = .milliseconds(500)

    @ObservationIgnored private let environment: AppEnvironment
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var pendingPlan: Task<Void, Never>?
    /// The plan being handed over; the next one waits for it, so two never interleave.
    @ObservationIgnored private var applying: Task<Void, Never>?
    @ObservationIgnored private var becameActive: (any NSObjectProtocol)?
    #if DEBUG
    @ObservationIgnored let debug = ReminderDebugOptions.current
    @ObservationIgnored private var hasRemindedSoon = false
    #endif

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    isolated deinit {
        tasks.forEach { $0.cancel() }
        pendingPlan?.cancel()
        if let becameActive { NotificationCenter.default.removeObserver(becameActive) }
    }

    private var center: any NotificationCenterClient { environment.notifications }

    // MARK: Following

    /// Follows every profile's books and this phone's Sunday switch, and plans again after each
    /// change; coming back to the app plans again too, as time has moved on. Idempotent.
    func start() {
        guard tasks.isEmpty else { return }
        let books = environment.database.allSnapshots()
        let device = environment.deviceSettings.changes()
        tasks.append(Task { [weak self] in
            do {
                for try await snapshots in books {
                    self?.planSoon(snapshots)
                }
            } catch {
                log.error("Following the books for reminders failed: \(String(describing: error))")
            }
        })
        tasks.append(Task { [weak self] in
            var reconcile: Bool?
            for await settings in device {
                // The first value is the current one: the books' first value plans already.
                defer { reconcile = settings.reconcileReminder }
                guard let reconcile, reconcile != settings.reconcileReminder else { continue }
                self?.planSoon(nil)
            }
        })
        becameActive = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.planSoon(nil) }
        }
        #if DEBUG
        // A test that needs a notification delivered allows them at launch, and starts with none
        // left over from an earlier run.
        if debug.remindsSoon {
            UNUserNotificationCenter.current().removeAllDeliveredNotifications()
            Task { await askPermission() }
        }
        #endif
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        pendingPlan?.cancel()
        if let becameActive { NotificationCenter.default.removeObserver(becameActive) }
        becameActive = nil
    }

    /// Plans once things have been still for `debounce`, from [snapshots] or a fresh read.
    private func planSoon(_ snapshots: [ProfileSnapshot]?) {
        pendingPlan?.cancel()
        let delay = debounce
        pendingPlan = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            await self.replan(snapshots)
        }
    }

    // MARK: Planning

    /// Plans from what the database holds now and hands it over: the launch, the background refresh
    /// and a granted permission call it. Without permission nothing is scheduled.
    func replan() async {
        await replan(nil)
    }

    private func replan(_ given: [ProfileSnapshot]?) async {
        let previous = applying
        let task = Task { [weak self] in
            await previous?.value
            await self?.planAndApply(given)
        }
        applying = task
        await task.value
    }

    private func planAndApply(_ given: [ProfileSnapshot]?) async {
        guard await center.permission() == .allowed else { return }
        let snapshots: [ProfileSnapshot]
        do {
            if let given { snapshots = given } else { snapshots = try await readBooks() }
        } catch {
            log.error("Reading the books for reminders failed: \(String(describing: error))")
            return
        }
        let now = environment.clock()
        var plan = Self.plan(snapshots, reconcile: environment.deviceSettings.current.reconcileReminder, now: now, zone: environment.zone())
        #if DEBUG
        remindSoon(&plan, now: now)
        #endif
        await apply(Self.requests(plan, snapshots: snapshots, locale: locale()))
        ReminderBackground.submit(at: Reminders.nextRefresh(after: plan, now: now))
    }

    /// Every profile's books in one read.
    private func readBooks() async throws -> [ProfileSnapshot] {
        try await environment.database.read { store in
            try store.profiles().compactMap { try store.snapshot(profileId: $0.id) }
        }
    }

    static func plan(_ snapshots: [ProfileSnapshot], reconcile: Bool, now: Int64, zone: TimeZone) -> [Reminder] {
        let books = snapshots.map { snapshot in
            ReminderBooks(
                id: snapshot.profile.id, accounts: snapshot.accounts,
                states: Ledger.states(snapshot.accounts, snapshot.operations.flatMap(\.postings)), wishes: snapshot.wishes
            )
        }
        return Reminders.plan(books, reconcile: reconcile, now: now, zone: zone)
    }

    /// The plan in words. A profile is named only when there is more than one to tell apart.
    static func requests(_ plan: [Reminder], snapshots: [ProfileSnapshot], locale: Locale) -> [NotificationRequest] {
        let names = snapshots.count > 1
            ? Dictionary(snapshots.map { ($0.profile.id, $0.profile.name) }, uniquingKeysWith: { first, _ in first })
            : [:]
        return plan.map { ReminderText.request(for: $0, profileName: $0.booksId.flatMap { names[$0] }, locale: locale) }
    }

    /// Removes what is pending and no longer wanted (or wanted differently) first, so the system's
    /// 64 are never exceeded on the way, then adds what is missing.
    private func apply(_ requests: [NotificationRequest]) async {
        let pending = await center.pending()
        let wanted = Dictionary(requests.map { ($0.id, $0.signature) }, uniquingKeysWith: { first, _ in first })
        let stale = pending.filter { wanted[$0.key] != $0.value }.map(\.key)
        if !stale.isEmpty { await center.removePending(stale) }
        for request in requests where pending[request.id] != request.signature {
            do {
                try await center.add(request)
            } catch {
                log.error("Scheduling \(request.id) failed: \(String(describing: error))")
            }
        }
    }

    // MARK: Permission

    /// Asks the person once, at the first need (D36): "Подумаю", the Sunday switch turned on, a debt
    /// with a date. Once allowed, the plan goes in at once. Asked before, nothing happens: the
    /// answer lives in the system's settings.
    func askPermission() async {
        guard await center.permission() == .notAsked else { return }
        if await center.requestPermission() { await replan() }
    }

    // MARK: Debug

    #if DEBUG
    /// Long enough for a UI test to answer the permission alert and leave the app first.
    private static let soon: Int64 = 8_000

    /// `-golda.remindSoon`: the first plan brings its soonest wish (or whatever is soonest) to a few
    /// seconds from now, so a delivery can be watched on the simulator.
    private func remindSoon(_ plan: inout [Reminder], now: Int64) {
        guard debug.remindsSoon, !hasRemindedSoon, !plan.isEmpty else { return }
        hasRemindedSoon = true
        let index = plan.firstIndex { if case .wish = $0.event { true } else { false } } ?? 0
        plan[index].time = .instant(now + Self.soon)
        plan[index].fireAt = now + Self.soon
    }

    /// `-golda.tapReminder.<kind>`: what tapping the first planned reminder of [kind] would open,
    /// read back from its notification as a real tap is. Permission plays no part.
    func debugTap(_ kind: ReminderDebugOptions.Kind) async -> ReminderTap? {
        guard let snapshots = try? await readBooks() else { return nil }
        let plan = Self.plan(snapshots, reconcile: true, now: environment.clock(), zone: environment.zone())
        let request = Self.requests(plan, snapshots: snapshots, locale: locale()).first { kind.matches($0) }
        return request.flatMap { ReminderTap(userInfo: $0.tap.userInfo) }
    }
    #endif
}

#if DEBUG
/// Debug launch arguments of the reminders, each a flag of its own like the others.
struct ReminderDebugOptions: Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case wish, payment, grace, reconcile

        func matches(_ request: NotificationRequest) -> Bool {
            request.id.hasPrefix(rawValue)
        }
    }

    /// `-golda.tapReminder.wish`, `.payment`, `.grace`, `.reconcile`: after launch the app opens as
    /// if that reminder had been tapped.
    var tap: Kind?
    /// `-golda.remindSoon`: permission is asked at launch and the first plan fires in seconds.
    var remindsSoon = false
    /// `-golda.liveNotifications`: the system's notifications even over the in-memory data.
    var usesLiveNotifications = false

    static var current: ReminderDebugOptions { ReminderDebugOptions(arguments: ProcessInfo.processInfo.arguments) }

    init(arguments: [String] = []) {
        let flags = Set(arguments)
        tap = Kind.allCases.first { flags.contains("-golda.tapReminder.\($0.rawValue)") }
        remindsSoon = flags.contains("-golda.remindSoon")
        usesLiveNotifications = flags.contains("-golda.liveNotifications") || remindsSoon
    }
}
#endif
