import CloudKit
import Foundation

/// Sync over CloudKit: one `CKSyncEngine` on the private database (this person's profiles) and one
/// on the shared database (the profiles others shared with them), one zone per profile and one
/// `CKShare` per zone (ARCHITECTURE, «Синхронизация и шаринг»).
///
/// The engines decide when to fetch and send, listen to CloudKit's silent pushes and retry what
/// the network failed; their state goes into the `SyncStore` on every `stateUpdate`, so a new
/// process resumes from the same change tokens and pending changes.
public actor CloudKitSyncTransport: SyncTransport, CKSyncEngineDelegate {
    public nonisolated let container: CKContainer
    private let store: SyncStore
    private let log: @Sendable (SyncLogEntry) -> Void
    private let now: @Sendable () -> Int64
    private var engines: [SyncScope: CKSyncEngine] = [:]
    private var wakeUp: Task<Void, Never>?

    public init(
        containerIdentifier: String, store: SyncStore,
        now: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
        log: @escaping @Sendable (SyncLogEntry) -> Void
    ) {
        container = CKContainer(identifier: containerIdentifier)
        self.store = store
        self.now = now
        self.log = log
    }

    // MARK: SyncTransport

    public func start() async throws {
        guard engines.isEmpty else { return }
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
        try await store.removeZone(zone)
    }

    public func stopSharing(_ zone: SyncZone) async throws {
        guard zone.isOwned else { throw SyncTransportError.notOwner }
        _ = try await container.privateCloudDatabase.deleteRecord(withID: zone.shareRecordID)
        say(.private, "deleted the share of \(zone.zoneName)")
    }

    // MARK: Sharing

    /// The zone's share, created on first use: everyone invited may read and write (O3, by default).
    /// The zone has to be on the server first, so the queue is sent before.
    public func share(_ zone: SyncZone, title: String) async throws -> CKShare {
        guard zone.isOwned else { throw SyncTransportError.notOwner }
        try await sendNow()
        do {
            if let existing = try await container.privateCloudDatabase.record(for: zone.shareRecordID) as? CKShare {
                say(.private, "share exists: \(existing.participants.count) participant(s), url \(existing.url?.absoluteString ?? "none")")
                return existing
            }
        } catch let error as CKError where error.code == .unknownItem {
            // No share yet.
        }
        let share = CKShare(recordZoneID: zone.zoneID)
        share[CKShare.SystemFieldKey.title] = title
        share.publicPermission = .none
        let (saved, _) = try await container.privateCloudDatabase.modifyRecords(saving: [share], deleting: [])
        guard let result = saved[share.recordID] else { throw SyncTransportError.shareNotSaved }
        let created = try result.get()
        say(.private, "share created for \(zone.zoneName)")
        return created as? CKShare ?? share
    }

    /// The share as the server has it now, nil when the zone is not shared.
    public func existingShare(_ zone: SyncZone) async -> CKShare? {
        let database = zone.isOwned ? container.privateCloudDatabase : container.sharedCloudDatabase
        return try? await database.record(for: zone.shareRecordID) as? CKShare
    }

    /// Accepts an invitation the system handed to the scene, then fetches the shared database so
    /// the profile shows up at once.
    public func accept(_ metadata: CKShare.Metadata) async throws {
        say(.shared, "accepting share \(metadata.share.recordID.zoneID.zoneName) from \(metadata.ownerIdentity.nameComponents?.formatted() ?? "?")")
        let results = try await container.accept([metadata])
        if case .failure(let error)? = results[metadata] { throw error }
        say(.shared, "accepted")
        try await engines[.shared]?.fetchChanges()
    }

    /// A participant leaves by deleting the share from their shared database; if CloudKit refuses,
    /// deleting the zone there is the other documented way. Which one worked goes to the log.
    private func leave(_ zone: SyncZone) async throws {
        do {
            _ = try await container.sharedCloudDatabase.deleteRecord(withID: zone.shareRecordID)
            say(.shared, "left \(zone.zoneName) by deleting the share")
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
                    if let zone = SyncZone(zoneID: deletion.zoneID, scope: scope) { try await store.removeZone(zone) }
                }
            case .fetchedRecordZoneChanges(let changes):
                try await fetched(changes, scope: scope)
            case .sentDatabaseChanges(let sent):
                for zone in sent.savedZones { say(scope, "zone saved: \(zone.zoneID.zoneName)") }
                for failure in sent.failedZoneSaves { say(scope, "zone save failed: \(failure.zone.zoneID.zoneName) \(failure.error.code)") }
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
    /// by last writer wins, a missing zone is created again.
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
                    try await store.removeZone(ref.zone)
                }
            case .unknownItem:
                try await store.setSystemFields(nil, for: ref)
                again.append(ref)
            default:
                // Network, throttling, quota: the engine retries what is still pending.
                break
            }
        }
        for (id, error) in sent.failedRecordDeletes {
            guard let ref = SyncRecordRef(recordID: id, scope: scope) else { continue }
            if error.code == .unknownItem {
                try await store.confirm(.delete, of: ref)
            } else {
                say(scope, "delete failed: \(ref.recordName) \(error.code)")
            }
        }
        if !again.isEmpty {
            try await store.rehand(again)
            await outgoingChanged()
        }
    }

    private func accountChanged(_ change: CKSyncEngine.Event.AccountChange, scope: SyncScope) async throws {
        switch change.changeType {
        case .signIn:
            say(scope, "iCloud signed in")
        case .signOut, .switchAccounts:
            // Another person's data must not stay, nor go to their iCloud.
            say(scope, "iCloud signed out or switched: local sync data wiped")
            try await store.wipe()
        @unknown default:
            say(scope, "account change \(change)")
        }
    }

    // MARK: Helpers

    /// Hands the next waiting delete over when its undo window ends.
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

public enum SyncTransportError: Error, Sendable {
    /// Only the owner may create, share and stop sharing a zone.
    case notOwner
    case shareNotSaved
}
