import CloudKit
import Foundation
import GoldaData

/// Sync over CloudKit: one `CKSyncEngine` on the private database (this person's profiles) and one
/// on the shared database (the profiles others shared with them), one zone per profile and one
/// `CKShare` per zone (ARCHITECTURE, «Синхронизация и шаринг»). Verified on two iPhones with
/// different Apple IDs in spike 5a (S1).
///
/// The engines decide when to fetch and send, listen to CloudKit's silent pushes and retry what
/// the network failed; their state goes into the `SyncStore` on every `stateUpdate`, so a new
/// process resumes from the same change tokens and pending changes. When the server asks to wait
/// (`retryAfterSeconds`), the change leaves the engine and comes back to it only then.
public actor CloudKitSyncTransport: SyncTransport, CKSyncEngineDelegate {
    public nonisolated let container: CKContainer
    private let store: SyncStore
    private let log: @Sendable (SyncLogEntry) -> Void
    private let problem: @Sendable (SyncProblem) -> Void
    private let now: @Sendable () -> Int64
    private var engines: [SyncScope: CKSyncEngine] = [:]
    private var wakeUp: Task<Void, Never>?
    private var accountChanged: (@Sendable () async -> Void)?
    /// Not before these moments (ms) may a zone's share be asked for again: the server said so.
    private var shareNotBefore: [SyncZone: Int64] = [:]

    /// [problem] hears what went wrong while the engines worked on their own (a full iCloud, a
    /// request to wait), so the app can say it; [log] hears everything, for the debug screen.
    public init(
        containerIdentifier: String, store: SyncStore,
        now: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
        problem: @escaping @Sendable (SyncProblem) -> Void = { _ in },
        log: @escaping @Sendable (SyncLogEntry) -> Void = { _ in }
    ) {
        container = CKContainer(identifier: containerIdentifier)
        self.store = store
        self.now = now
        self.problem = problem
        self.log = log
    }

    // MARK: SyncTransport

    public func start(accountChanged: @escaping @Sendable () async -> Void) async throws {
        guard engines.isEmpty else { return }
        self.accountChanged = accountChanged
        for scope in SyncScope.allCases {
            let serialization = try await store.engineState(scope).flatMap {
                try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0)
            }
            let database = scope == .private ? container.privateCloudDatabase : container.sharedCloudDatabase
            engines[scope] = CKSyncEngine(CKSyncEngine.Configuration(
                database: database, stateSerialization: serialization, delegate: self
            ))
            say(scope, serialization == nil ? "engine started fresh" : "engine resumed from saved state")
        }
        try await store.rehand()
        await outgoingChanged()
    }

    public func accountStatus() async -> SyncAccountStatus {
        do {
            switch try await container.accountStatus() {
            case .available: return .available
            case .noAccount: return .noAccount
            case .restricted: return .restricted
            case .temporarilyUnavailable: return .temporarilyUnavailable
            default: return .couldNotDetermine
            }
        } catch {
            say(nil, "account status failed: \(error)")
            return .couldNotDetermine
        }
    }

    public func outgoingChanged() async {
        do {
            for change in try await store.takeDue(at: now()) {
                guard let engine = engines[change.ref.zone.scope] else { continue }
                let id = change.ref.recordID
                let (add, drop): (CKSyncEngine.PendingRecordZoneChange, CKSyncEngine.PendingRecordZoneChange) =
                    change.kind == .save ? (.saveRecord(id), .deleteRecord(id)) : (.deleteRecord(id), .saveRecord(id))
                engine.state.remove(pendingRecordZoneChanges: [drop])
                engine.state.add(pendingRecordZoneChanges: [add])
                say(change.ref.zone.scope, "queued \(change.kind.rawValue) \(change.ref.recordName)")
            }
            scheduleWakeUp(at: try await store.nextDue(after: now()))
        } catch {
            say(nil, "handing over the queue failed: \(error)")
        }
    }

    public func sendNow() async throws {
        await outgoingChanged()
        for scope in SyncScope.allCases {
            try await engines[scope]?.sendChanges()
        }
    }

    public func fetchNow() async throws {
        for scope in SyncScope.allCases {
            try await engines[scope]?.fetchChanges()
        }
    }

    public func createZone(_ zone: SyncZone) async throws {
        guard zone.isOwned, let engine = engines[.private] else { throw SyncTransportError.notOwner }
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zone.zoneID))])
        say(.private, "queued zone \(zone.zoneName)")
    }

    public func removeZone(_ zone: SyncZone) async throws {
        if zone.isOwned {
            engines[.private]?.state.add(pendingDatabaseChanges: [.deleteZone(zone.zoneID)])
            say(.private, "queued zone delete \(zone.zoneName)")
        } else {
            try await leave(zone)
        }
    }

    public func stopSharing(_ zone: SyncZone) async throws {
        guard zone.isOwned else { throw SyncTransportError.notOwner }
        do {
            _ = try await container.privateCloudDatabase.deleteRecord(withID: zone.shareRecordID)
        } catch let error as CKError where error.code == .unknownItem {
            // Not shared any more: what was asked is done.
        }
        say(.private, "deleted the share of \(zone.zoneName)")
    }

    public func participants(of zone: SyncZone) async throws -> [SyncParticipant] {
        guard let share = try await existingShare(zone) else { return [] }
        return share.participants.map { participant in
            let identity = participant.userIdentity
            let name = identity.nameComponents.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) }
                .flatMap { $0.isEmpty ? nil : $0 }
                ?? identity.lookupInfo?.emailAddress ?? identity.lookupInfo?.phoneNumber
            let status: SyncParticipant.Status = switch participant.acceptanceStatus {
            case .accepted: .joined
            case .removed: .removed
            default: .invited
            }
            return SyncParticipant(
                id: identity.userRecordID?.recordName ?? UUID().uuidString, name: name,
                isOwner: participant.role == .owner, isCurrentUser: participant == share.currentUserParticipant,
                status: status, canWrite: participant.permission == .readWrite
            )
        }
    }

    // MARK: Sharing

    /// The zone's share, created on first use: only the people invited may join, and they may read
    /// and write (O3). The zone has to be on the server first, so the queue is sent before. When
    /// the server asked to wait, asking again before then fails at once with how long is left,
    /// without a request.
    public func share(_ zone: SyncZone, title: String) async throws -> CKShare {
        guard zone.isOwned else { throw SyncTransportError.notOwner }
        if let notBefore = shareNotBefore[zone], notBefore > now() {
            throw SyncProblem.retryLater(seconds: Int((notBefore - now() + 999) / 1000))
        }
        do {
            try await sendNow()
            if let existing = try await existingShare(zone) {
                say(.private, "share exists: \(existing.participants.count) participant(s)")
                return existing
            }
            let share = CKShare(recordZoneID: zone.zoneID)
            share[CKShare.SystemFieldKey.title] = title
            share.publicPermission = .none
            let (saved, _) = try await container.privateCloudDatabase.modifyRecords(saving: [share], deleting: [])
            guard let result = saved[share.recordID] else { throw SyncTransportError.shareNotSaved }
            let created = try result.get()
            say(.private, "share created for \(zone.zoneName)")
            shareNotBefore[zone] = nil
            return created as? CKShare ?? share
        } catch {
            let problem = SyncProblem(error)
            if case .retryLater(let seconds) = problem {
                shareNotBefore[zone] = now() + Int64(seconds) * 1000
            }
            say(.private, "share failed: \(error)")
            throw problem
        }
    }

    /// The share as the server has it now, nil when the zone is not shared.
    public func existingShare(_ zone: SyncZone) async throws -> CKShare? {
        let database = zone.isOwned ? container.privateCloudDatabase : container.sharedCloudDatabase
        do {
            return try await database.record(for: zone.shareRecordID) as? CKShare
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            return nil
        }
    }

    /// Accepts an invitation the system handed to the scene, then fetches the shared database so
    /// the profile shows up at once.
    public func accept(_ metadata: CKShare.Metadata) async throws {
        say(.shared, "accepting share \(metadata.share.recordID.zoneID.zoneName)")
        let results = try await container.accept([metadata])
        if case .failure(let error)? = results[metadata] { throw error }
        say(.shared, "accepted")
        try await engines[.shared]?.fetchChanges()
    }

    /// A participant leaves by deleting the share from their shared database; if CloudKit refuses,
    /// deleting the zone there is the other documented way.
    private func leave(_ zone: SyncZone) async throws {
        do {
            _ = try await container.sharedCloudDatabase.deleteRecord(withID: zone.shareRecordID)
            say(.shared, "left \(zone.zoneName) by deleting the share")
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            say(.shared, "\(zone.zoneName) was already gone")
        } catch {
            say(.shared, "deleting the share failed (\(error)); deleting the zone instead")
            _ = try await container.sharedCloudDatabase.modifyRecordZones(saving: [], deleting: [zone.zoneID])
            say(.shared, "left \(zone.zoneName) by deleting the zone")
        }
    }

    // MARK: CKSyncEngineDelegate

    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard let scope = SyncScope(syncEngine.database.databaseScope) else { return }
        do {
            switch event {
            case .stateUpdate(let update):
                try await store.setEngineState(try JSONEncoder().encode(update.stateSerialization), for: scope)
            case .accountChange(let change):
                try await accountChanged(change, scope: scope)
            case .fetchedDatabaseChanges(let changes):
                for modification in changes.modifications {
                    say(scope, "zone changed: \(modification.zoneID.zoneName) owner \(modification.zoneID.ownerName)")
                }
                for deletion in changes.deletions {
                    say(scope, "zone gone (\(deletion.reason)): \(deletion.zoneID.zoneName)")
                    guard let zone = SyncZone(zoneID: deletion.zoneID, scope: scope) else { continue }
                    // Someone else's zone, or one its owner deleted: the profile goes. An own zone
                    // the server lost (iCloud data deleted, encryption reset) keeps the books here.
                    let loss: SyncStore.ZoneLoss = scope == .shared || deletion.reason == .deleted ? .deleted : .lostOnServer
                    try await store.zoneGone(zone, loss)
                }
            case .fetchedRecordZoneChanges(let changes):
                try await fetched(changes, scope: scope)
            case .sentDatabaseChanges(let sent):
                for zone in sent.savedZones { say(scope, "zone saved: \(zone.zoneID.zoneName)") }
                for failure in sent.failedZoneSaves {
                    say(scope, "zone save failed: \(failure.zone.zoneID.zoneName) \(failure.error.code)")
                    problem(SyncProblem(failure.error))
                }
                for id in sent.deletedZoneIDs { say(scope, "zone deleted: \(id.zoneName)") }
                for (id, error) in sent.failedZoneDeletes { say(scope, "zone delete failed: \(id.zoneName) \(error.code)") }
            case .sentRecordZoneChanges(let sent):
                try await sentChanges(sent, scope: scope, engine: syncEngine)
            case .willFetchChanges: say(scope, "fetch…")
            case .didFetchChanges: say(scope, "fetch done")
            case .willSendChanges: say(scope, "send…")
            case .didSendChanges: say(scope, "send done")
            case .willFetchRecordZoneChanges, .didFetchRecordZoneChanges: break
            @unknown default: say(scope, "event \(event)")
            }
        } catch {
            say(scope, "handling \(event) failed: \(error)")
        }
    }

    public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard let scope = SyncScope(syncEngine.database.databaseScope) else { return nil }
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        guard !pending.isEmpty else { return nil }
        let store = store
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            guard let ref = SyncRecordRef(recordID: recordID, scope: scope),
                  let record = try? await store.record(ref)
            else {
                // Deleted here since it was queued: nothing to save, and the engine must stop asking.
                syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
                return nil
            }
            return CloudKitMapping.ckRecord(for: record, systemFields: try? await store.systemFields(ref))
        }
    }

    // MARK: Events

    private func fetched(_ changes: CKSyncEngine.Event.FetchedRecordZoneChanges, scope: SyncScope) async throws {
        var records: [SyncRecord] = []
        for modification in changes.modifications {
            let ck = modification.record
            guard let record = CloudKitMapping.syncRecord(from: ck, scope: scope) else {
                say(scope, "skipped \(ck.recordType) \(ck.recordID.recordName)")
                continue
            }
            try await store.setSystemFields(CloudKitMapping.systemFields(of: ck), for: record.ref)
            records.append(record)
        }
        let deletions = changes.deletions.compactMap { SyncRecordRef(recordID: $0.recordID, scope: scope) }
        let kept = try await store.apply(records, deletions: deletions)
        say(scope, "fetched \(records.count) record(s), \(deletions.count) deletion(s)\(kept.isEmpty ? "" : ", \(kept.count) kept local")")
        if !kept.isEmpty {
            try await store.rehand(kept)
            await outgoingChanged()
        }
    }

    /// What the server did with a sent batch: confirmations leave the queue, conflicts are settled
    /// by last writer wins, a missing zone is created again, and a request to wait is honoured.
    private func sentChanges(_ sent: CKSyncEngine.Event.SentRecordZoneChanges, scope: SyncScope, engine: CKSyncEngine) async throws {
        for ck in sent.savedRecords {
            guard let ref = SyncRecordRef(recordID: ck.recordID, scope: scope) else { continue }
            try await store.setSystemFields(CloudKitMapping.systemFields(of: ck), for: ref)
            try await store.confirm(.save, of: ref)
        }
        for id in sent.deletedRecordIDs {
            guard let ref = SyncRecordRef(recordID: id, scope: scope) else { continue }
            try await store.setSystemFields(nil, for: ref)
            try await store.confirm(.delete, of: ref)
        }
        if !sent.savedRecords.isEmpty || !sent.deletedRecordIDs.isEmpty {
            say(scope, "sent \(sent.savedRecords.count) save(s), \(sent.deletedRecordIDs.count) delete(s)")
        }
        var again: [SyncRecordRef] = []
        var waiting: [(SyncRecordRef, CKSyncEngine.PendingRecordZoneChange, CKError)] = []
        for failure in sent.failedRecordSaves {
            guard let ref = SyncRecordRef(recordID: failure.record.recordID, scope: scope) else { continue }
            say(scope, "save failed: \(ref.recordName) \(failure.error.code)")
            switch failure.error.code {
            case .serverRecordChanged:
                guard let server = failure.error.serverRecord else { continue }
                try await store.setSystemFields(CloudKitMapping.systemFields(of: server), for: ref)
                if let incoming = CloudKitMapping.syncRecord(from: server, scope: scope) {
                    again += try await store.apply([incoming])
                    say(scope, again.contains(ref) ? "conflict: this phone's version wins" : "conflict: the server's version wins")
                }
            case .zoneNotFound:
                if ref.zone.isOwned {
                    engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: ref.zone.zoneID))])
                    again.append(ref)
                } else {
                    try await store.zoneGone(ref.zone, .deleted)
                }
            case .unknownItem:
                try await store.setSystemFields(nil, for: ref)
                again.append(ref)
            case .batchRequestFailed:
                // Another record of the batch failed; this one goes with the next batch.
                again.append(ref)
            default:
                waiting.append((ref, .saveRecord(failure.record.recordID), failure.error))
            }
        }
        for (id, error) in sent.failedRecordDeletes {
            guard let ref = SyncRecordRef(recordID: id, scope: scope) else { continue }
            if error.code == .unknownItem || error.code == .zoneNotFound {
                try await store.confirm(.delete, of: ref)
            } else {
                say(scope, "delete failed: \(ref.recordName) \(error.code)")
                waiting.append((ref, .deleteRecord(id), error))
            }
        }
        try await postpone(waiting, engine: engine)
        if !again.isEmpty {
            try await store.rehand(again)
            await outgoingChanged()
        }
    }

    /// Changes the server refused for now. With a time to wait (`retryAfterSeconds`), or a full
    /// iCloud, they leave the engine, which would otherwise try again at once and again, and come
    /// back to it when the time is up (`scheduleWakeUp`). The engine retries the rest (a lost
    /// network) on its own.
    private func postpone(_ refused: [(SyncRecordRef, CKSyncEngine.PendingRecordZoneChange, CKError)], engine: CKSyncEngine) async throws {
        guard !refused.isEmpty else { return }
        var latest: SyncProblem?
        for (ref, change, error) in refused {
            let seconds = error.retryAfterSeconds ?? (error.code == .quotaExceeded ? Self.fullQuotaPause : nil)
            latest = SyncProblem(error)
            guard let seconds else { continue }
            engine.state.remove(pendingRecordZoneChanges: [change])
            try await store.postpone([ref], until: now() + Int64((seconds * 1000).rounded(.up)))
            say(ref.zone.scope, "postponed \(ref.recordName) by \(Int(seconds)) s")
        }
        if let latest { problem(latest) }
        scheduleWakeUp(at: try await store.nextDue(after: now()))
    }

    /// How long a change waits after a full iCloud that named no time: long enough not to hammer
    /// the server, short enough that freeing space is soon noticed.
    static let fullQuotaPause: TimeInterval = 300

    private func accountChanged(_ change: CKSyncEngine.Event.AccountChange, scope: SyncScope) async throws {
        switch change.changeType {
        case .signIn:
            say(scope, "iCloud signed in")
        case .signOut, .switchAccounts:
            // The old account's shares leave the phone; its own books stay, for the new account.
            say(scope, "iCloud signed out or switched: sync state reset, shared profiles removed")
            try await store.resetForAccountChange()
        @unknown default:
            say(scope, "account change \(change)")
        }
        // Both engines hear of it; one notice to the app is enough.
        if scope == .private { await accountChanged?() }
    }

    // MARK: Helpers

    /// Hands the next waiting change over when its time comes: a delete's undo window, a wait the
    /// server asked for.
    private func scheduleWakeUp(at moment: Int64?) {
        wakeUp?.cancel()
        guard let moment else { return }
        let delay = max(0, moment - now())
        wakeUp = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled else { return }
            await self?.outgoingChanged()
        }
    }

    private nonisolated func say(_ scope: SyncScope?, _ message: String) {
        log(SyncLogEntry(scope: scope, message: message))
    }
}
