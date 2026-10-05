import Foundation
import GoldaData

/// Keeps one phone's books in sync (stage 5b): gives new own profiles their zones, tells the
/// server about deleted and left profiles, and hands the queue to the transport after every local
/// change. The books never wait for it: with no iCloud the app works locally, the queue keeps the
/// changes, and the profiles go up once iCloud is there (ARCHITECTURE, «Без iCloud»).
public actor SyncService {
    public enum State: Equatable, Sendable {
        /// Not syncing: no iCloud account, or it could not be checked yet.
        case off(SyncAccountStatus)
        case on
        /// Syncing, but the last attempt failed; the queue keeps what did not go.
        case problem(SyncProblem)
    }

    public let store: SyncStore
    public let transport: any SyncTransport
    private let now: @Sendable () -> Int64
    private let report: @Sendable (State) -> Void
    private var following: Task<Void, Never>?
    private var started = false
    public private(set) var state: State = .off(.couldNotDetermine)

    public init(
        store: SyncStore, transport: any SyncTransport,
        now: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
        report: @escaping @Sendable (State) -> Void = { _ in }
    ) {
        self.store = store
        self.transport = transport
        self.now = now
        self.report = report
    }

    deinit {
        following?.cancel()
    }

    /// Starts once iCloud is there; until then nothing leaves the phone. Called at launch and
    /// whenever the app comes back, since the person may have signed in meanwhile.
    public func start() async {
        guard !started else { return }
        let status = await transport.accountStatus()
        guard status == .available else {
            set(.off(status))
            return
        }
        do {
            try await transport.start(accountChanged: { [weak self] in await self?.accountChanged() })
        } catch {
            set(.problem(SyncProblem(error)))
            return
        }
        started = true
        set(.on)
        await localChanged()
        follow()
        do {
            try await transport.fetchNow()
        } catch {
            set(.problem(SyncProblem(error)))
        }
    }

    /// Whether the transport runs; sharing is offered only then.
    public var isStarted: Bool { started }

    /// After each local change: new own profiles get their zones, deleted or left ones go from the
    /// server, and the queue's due part goes to the transport.
    public func localChanged() async {
        guard started else { return }
        do {
            for zone in try await store.registerProfiles(now: now()) {
                try await transport.createZone(zone)
            }
            for zone in try await store.zonesToRemove() {
                try await transport.removeZone(zone)
                try await store.zoneRemoved(zone)
            }
        } catch {
            // Offline, say: the zones stay marked and are tried again with the next change.
            set(.problem(SyncProblem(error)))
        }
        await transport.outgoingChanged()
    }

    /// Sends what is due and fetches what changed, now: pull to refresh, a return to the app.
    public func syncNow() async throws {
        guard started else { return }
        await localChanged()
        do {
            try await transport.sendNow()
            try await transport.fetchNow()
            if case .problem = state { set(.on) }
        } catch {
            let problem = SyncProblem(error)
            set(.problem(problem))
            throw problem
        }
    }

    /// Fetches what the other phones changed, while the app is open (D66): CloudKit's push comes
    /// late now and then. Quiet: a failure here (offline) is not news, the next try or push follows.
    public func fetch() async {
        guard started else { return }
        try? await transport.fetchNow()
    }

    /// The owner stops sharing the profile: the participants lose it, the owner keeps it.
    public func stopSharing(_ profileId: UUID) async throws {
        guard started, let zone = try await store.zone(of: profileId), zone.isOwned else { throw SyncProblem.notPermitted }
        do {
            try await transport.stopSharing(zone)
        } catch {
            throw SyncProblem(error)
        }
    }

    /// Who the profile is shared with; empty when it is not, or sync is off.
    public func participants(_ profileId: UUID) async throws -> [SyncParticipant] {
        guard started, let zone = try await store.zone(of: profileId) else { return [] }
        do {
            return try await transport.participants(of: zone)
        } catch {
            throw SyncProblem(error)
        }
    }

    /// The account signed in, out or switched; the transport has already made the store forget
    /// the old one. The phone's own profiles go to the new account's zones.
    private func accountChanged() async {
        let status = await transport.accountStatus()
        if status != .available { set(.off(status)) } else { set(.on) }
        await localChanged()
    }

    private func follow() {
        following?.cancel()
        let changes = store.changes()
        following = Task { [weak self] in
            do {
                for try await _ in changes {
                    guard let self else { return }
                    await self.localChanged()
                }
            } catch {
                // The database failed; the app shows that on its own.
            }
        }
    }

    private func set(_ state: State) {
        guard state != self.state else { return }
        self.state = state
        report(state)
    }
}
