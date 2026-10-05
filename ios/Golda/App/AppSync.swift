import CloudKit
import CoreTransferable
import Foundation
import GoldaData
import GoldaSync
import Observation
import OSLog
import UIKit

private let log = Logger(subsystem: "com.f4studio.golda", category: "Sync")

/// How the app reaches the other phones: CloudKit on a real launch, nothing in memory (UI tests,
/// previews), or a transport a unit test hands in.
enum SyncBackend: Sendable {
    case off
    case cloudKit(containerIdentifier: String)
    case custom(@Sendable (SyncStore) -> any SyncTransport)

    static let containerIdentifier = "iCloud.com.f4studio.golda"
}

/// Sync and sharing as the screens see them (stage 5b and 5c): whether iCloud is there, which
/// profiles are shared and with whom, inviting, stopping, accepting, and what went wrong in words.
///
/// The books never wait for it. Local changes reach the queue in their own transaction
/// (`GoldaDatabase.write`); the `SyncService` hands it to CloudKit and writes what comes back into
/// the books, and the screens follow the books as always.
@MainActor @Observable
final class AppSync {
    enum Availability: Equatable {
        /// This run does not sync (in memory, a test host).
        case off
        /// iCloud is not there: no account, restricted, or not known yet.
        case noICloud
        case on
    }

    private(set) var availability: Availability = .off
    /// What went wrong last, until sync works again.
    private(set) var problem: SyncProblem?
    /// The zone of every profile: own ones in this person's iCloud, shared ones under their owner.
    private(set) var zones: [UUID: SyncZone] = [:]
    /// The latest lines of what the transport did, for the debug screen.
    private(set) var logLines: [SyncLogEntry] = []

    @ObservationIgnored let store: SyncStore
    @ObservationIgnored private(set) var service: SyncService?
    @ObservationIgnored private var cloudKit: CloudKitSyncTransport?
    @ObservationIgnored private var following: Task<Void, Never>?
    @ObservationIgnored private var starting = false
    /// Asks for the other phones' changes while the app is on screen (D66).
    @ObservationIgnored private var polling: Task<Void, Never>?
    /// Invitations accepted before sync could start; taken once it has.
    @ObservationIgnored private var waitingInvitations: [CKShare.Metadata] = []
    /// Hears a profile that just arrived through an accepted invitation, to open it.
    @ObservationIgnored var onJoined: ((UUID) -> Void)?
    /// Hears the zones change: sync started, a profile became shared or stopped being.
    @ObservationIgnored var onZonesChanged: (() -> Void)?
    /// The people in each shared profile, and when they were asked for: names beside operations
    /// (D67) need them on every change, the server only now and then.
    @ObservationIgnored private var people: [UUID: (asked: Date, participants: [SyncParticipant])] = [:]

    init(database: GoldaDatabase, backend: SyncBackend, clock: @escaping @Sendable () -> Int64) {
        // When sync takes the last profile away, an empty «Личный» takes its place.
        store = SyncStore(database: database, lastProfileName: AppModel.firstProfileName)
        let transport: (any SyncTransport)?
        switch backend {
        case .off:
            transport = nil
        case .cloudKit(let identifier):
            let cloudKit = CloudKitSyncTransport(
                containerIdentifier: identifier, store: store, now: clock,
                problem: { problem in Task { @MainActor [weak self] in self?.report(problem) } },
                log: { entry in Task { @MainActor [weak self] in self?.note(entry) } }
            )
            self.cloudKit = cloudKit
            transport = cloudKit
        case .custom(let make):
            transport = make(store)
        }
        if let transport {
            service = SyncService(store: store, transport: transport, now: clock) { state in
                Task { @MainActor [weak self] in self?.apply(state) }
            }
            availability = .noICloud
        }
    }

    isolated deinit {
        following?.cancel()
        polling?.cancel()
    }

    // MARK: Running

    /// Starts sync if it can, at launch and on every return to the app: the person may have
    /// signed in to iCloud meanwhile. Once running, a return fetches what changed.
    func start() async {
        guard let service, !starting else { return }
        starting = true
        defer { starting = false }
        if await service.isStarted {
            await takeWaitingInvitations()
            try? await service.syncNow()
        } else {
            if cloudKit != nil { UIApplication.shared.registerForRemoteNotifications() }
            await service.start()
            apply(await service.state)
            if await service.isStarted { await takeWaitingInvitations() }
        }
        followZones()
        await reloadZones()
    }

    /// How often the app asks for changes while it is open: CloudKit's push brings them in a
    /// second or two as a rule, but now and then late; this bounds the wait.
    static let pollInterval: Duration = .seconds(15)

    /// On screen, the app asks for the other phones' changes every `pollInterval`; off screen it
    /// leaves that to CloudKit's push (D66).
    func setActive(_ active: Bool) {
        polling?.cancel()
        polling = nil
        guard active, let service else { return }
        polling = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard !Task.isCancelled else { return }
                await service.fetch()
            }
        }
    }

    /// Fetches the other phones' changes now, quietly: a push or the background refresh woke the
    /// app with no window, so nothing on screen started the sync.
    func catchUp() async {
        await start()
        await service?.fetch()
    }

    /// Sends and fetches now: pull to refresh.
    func syncNow() async {
        guard let service else { return }
        do {
            try await service.syncNow()
        } catch {
            log.error("Sync failed: \(String(describing: error))")
        }
        await reloadZones()
    }

    // MARK: Profiles

    /// Whether [profileId] is someone else's, shared with this person.
    func isParticipant(in profileId: UUID) -> Bool {
        zones[profileId].map { !$0.isOwned } ?? false
    }

    /// The people in the profile besides this phone's owner, and its owner when that is someone else.
    func participants(_ profileId: UUID) async throws -> [SyncParticipant] {
        guard let service else { return [] }
        return try await service.participants(profileId)
    }

    /// The owner stops sharing: the participants lose the profile, the owner keeps it.
    func stopSharing(_ profileId: UUID) async throws {
        guard let service else { throw SyncProblem.noAccount }
        try await service.stopSharing(profileId)
    }

    /// What the share sheet sends: a `CKShare` of the profile's zone, created when the sheet asks
    /// for it, so AirDrop, Messages, Mail and Copy Link all invite (D58). Nil when sharing is not
    /// possible here.
    func invitation(for profileId: UUID, title: String) -> ProfileInvitation? {
        guard availability == .on, let cloudKit, zones[profileId]?.isOwned != false else { return nil }
        let zone = SyncZone.own(profileId)
        return ProfileInvitation(container: cloudKit.container) { [weak self] in
            do {
                return try await cloudKit.share(zone, title: title)
            } catch {
                let problem = SyncProblem(error)
                await MainActor.run { self?.report(problem) }
                throw problem
            }
        }
    }

    /// An invitation the system handed to the scene. Accepted at once when sync runs, otherwise
    /// as soon as it does; the profile then opens.
    func accept(_ metadata: CKShare.Metadata) {
        waitingInvitations.append(metadata)
        Task {
            if let service, await service.isStarted {
                await takeWaitingInvitations()
            } else {
                await start()
            }
        }
    }

    private func takeWaitingInvitations() async {
        guard let cloudKit else { return }
        let invitations = waitingInvitations
        waitingInvitations = []
        for metadata in invitations {
            do {
                try await cloudKit.accept(metadata)
                await reloadZones()
                let zoneID = metadata.share.recordID.zoneID
                if let zone = SyncZone(zoneID: zoneID, scope: .shared), zones[zone.profileId] != nil {
                    onJoined?(zone.profileId)
                }
            } catch {
                log.error("Accepting an invitation failed: \(String(describing: error))")
                report(SyncProblem(error))
            }
        }
    }

    // MARK: Authors

    /// Who wrote each of [operations] in [profileId] (D67), nil when the profile is not shared with
    /// anyone who joined. The share is asked for at most every ten minutes, or sooner when a writer
    /// is someone it did not list; offline, the last list answers.
    func authorship(of profileId: UUID, operations: [UUID]) async -> Authorship? {
        guard let service, zones[profileId] != nil, await service.isStarted else { return nil }
        let fields = (try? await store.operationSystemFields(profileId: profileId)) ?? [:]
        let creators = await Task.detached { fields.compactMapValues(CloudKitMapping.creator(ofSystemFields:)) }.value
        let cached = people[profileId]
        let strangers = Set(creators.values).subtracting([CKCurrentUserDefaultName]).subtracting(cached?.participants.map(\.id) ?? [])
        var participants = cached?.participants ?? []
        if cached == nil || Date().timeIntervalSince(cached!.asked) > 600 || !strangers.isEmpty {
            if let fresh = try? await service.participants(profileId) {
                participants = fresh
                people[profileId] = (Date(), fresh)
            }
        }
        return Authorship.resolve(operations: operations, creators: creators, participants: participants, currentUser: CKCurrentUserDefaultName)
    }

    // MARK: State

    private func apply(_ state: SyncService.State) {
        switch state {
        case .off(let status):
            availability = .noICloud
            problem = status == .noAccount ? .noAccount : nil
        case .on:
            availability = .on
            problem = nil
        case .problem(let problem):
            availability = .on
            self.problem = problem
        }
    }

    private func report(_ problem: SyncProblem) {
        log.notice("iCloud refused: \(String(describing: problem))")
        self.problem = problem
    }

    private func note(_ entry: SyncLogEntry) {
        logLines.append(entry)
        if logLines.count > 300 { logLines.removeFirst(logLines.count - 300) }
    }

    /// Follows the profiles, so a profile that arrived or left shows the right sharing state.
    private func followZones() {
        guard following == nil else { return }
        let profiles = store.database.profiles()
        following = Task { [weak self] in
            do {
                for try await _ in profiles {
                    await self?.reloadZones()
                }
            } catch {
                // The model shows a failing database on its own.
            }
        }
    }

    func reloadZones() async {
        do {
            let fresh = try await store.zones()
            if fresh != zones {
                zones = fresh
                onZonesChanged?()
            }
        } catch {
            log.error("Reading the zones failed: \(String(describing: error))")
        }
    }
}

/// A profile's invitation for `ShareLink`: the system share sheet with a `CKShare` offers AirDrop,
/// Messages, Mail and Copy Link, and the share is made only when the person picks one. The share
/// starts as "only invited people" with read and write (`publicPermission = .none`, O3); the
/// sheet's options let the owner pick a link anyone may open, since a way of sending that names no
/// recipient may need it. Read-only is not offered: the app does not yet stop a read-only
/// participant from editing, and their refused changes are only rolled back (D58).
struct ProfileInvitation: Transferable {
    let container: CKContainer
    let prepare: @Sendable () async throws -> CKShare

    static var transferRepresentation: some TransferRepresentation {
        CKShareTransferRepresentation { invitation in
            .prepareShare(container: invitation.container, allowedSharingOptions: sharingOptions) {
                try await invitation.prepare()
            }
        }
    }

    static var sharingOptions: CKAllowedSharingOptions {
        CKAllowedSharingOptions(allowedParticipantPermissionOptions: .readWrite, allowedParticipantAccessOptions: .any)
    }
}
