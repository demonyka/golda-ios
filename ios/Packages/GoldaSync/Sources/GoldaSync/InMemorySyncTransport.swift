import Foundation

/// A CloudKit stand-in for tests: zones owned by people, shares that let others in, change tags
/// that turn a stale save into a conflict, and one change counter per server, so phones can fetch
/// what changed since they last looked. No network and no iCloud.
public actor InMemoryCloud {
    struct ZoneKey: Hashable {
        let owner: String
        let zoneName: String
    }

    private struct StoredRecord {
        var record: SyncRecord
        var tag: Int
        var seq: Int
    }

    private struct Zone {
        var records: [String: StoredRecord] = [:]
        var tombstones: [String: (ref: SyncRecordRef, seq: Int)] = [:]
        /// Each participant with the moment they joined: a newcomer receives the whole zone.
        var participants: [String: Int] = [:]
        var createdSeq: Int
    }

    public enum SaveResult: Sendable {
        case saved(tag: Int)
        case conflict(server: SyncRecord, tag: Int)
        case zoneNotFound
    }

    public struct Changes: Sendable {
        public var records: [(record: SyncRecord, tag: Int)] = []
        public var deletions: [SyncRecordRef] = []
        public var goneZones: [SyncZone] = []
        public var cursor: Int
    }

    private var zones: [ZoneKey: Zone] = [:]
    /// Zones a person lost (deleted, unshared, left), with when.
    private var gone: [(user: String, zone: SyncZone, seq: Int)] = []
    private var seq = 0
    private var nextTag = 0

    public init() {}

    private func tick() -> Int {
        seq += 1
        return seq
    }

    /// The server's key of [zone] as [user] names it: their own zones have no owner name.
    private func key(_ zone: SyncZone, for user: String) -> ZoneKey {
        ZoneKey(owner: zone.isOwned ? user : zone.ownerName, zoneName: zone.zoneName)
    }

    /// [zone] as [user] sees it: private if theirs, shared under its owner's name if not.
    private func view(_ key: ZoneKey, profileId: UUID, for user: String) -> SyncZone {
        key.owner == user
            ? SyncZone(profileId: profileId, ownerName: SyncZone.currentUser, scope: .private)
            : SyncZone(profileId: profileId, ownerName: key.owner, scope: .shared)
    }

    private func view(_ record: SyncRecord, in key: ZoneKey, for user: String) -> SyncRecord {
        var record = record
        record.zone = view(key, profileId: record.zone.profileId, for: user)
        return record
    }

    private func canSee(_ key: ZoneKey, _ user: String) -> Bool {
        guard let zone = zones[key] else { return false }
        return key.owner == user || zone.participants[user] != nil
    }

    // MARK: Zones and shares

    func createZone(_ zone: SyncZone, by user: String) {
        let key = key(zone, for: user)
        if zones[key] == nil { zones[key] = Zone(createdSeq: tick()) }
    }

    /// [owner] shares [zone] and [participant] accepts, in one step.
    public func share(_ zone: SyncZone, of owner: String, with participant: String) {
        let key = ZoneKey(owner: owner, zoneName: zone.zoneName)
        zones[key]?.participants[participant] = tick()
    }

    func stopSharing(_ zone: SyncZone, by owner: String) {
        let key = ZoneKey(owner: owner, zoneName: zone.zoneName)
        guard let participants = zones[key]?.participants.keys else { return }
        let at = tick()
        for user in participants {
            gone.append((user, view(key, profileId: zone.profileId, for: user), at))
        }
        zones[key]?.participants = [:]
    }

    func leave(_ zone: SyncZone, by user: String) {
        let key = key(zone, for: user)
        guard zones[key]?.participants.removeValue(forKey: user) != nil else { return }
        gone.append((user, zone, tick()))
    }

    func deleteZone(_ zone: SyncZone, by user: String) {
        let key = key(zone, for: user)
        guard let removed = zones.removeValue(forKey: key), key.owner == user else { return }
        let at = tick()
        for person in [user] + removed.participants.keys {
            gone.append((person, view(key, profileId: zone.profileId, for: person), at))
        }
    }

    // MARK: Records

    func save(_ record: SyncRecord, baseTag: Int?, by user: String) -> SaveResult {
        let key = key(record.zone, for: user)
        guard canSee(key, user), var zone = zones[key] else { return .zoneNotFound }
        let name = record.ref.recordName
        if let stored = zone.records[name], stored.tag != baseTag {
            return .conflict(server: view(stored.record, in: key, for: user), tag: stored.tag)
        }
        nextTag += 1
        zone.records[name] = StoredRecord(record: record, tag: nextTag, seq: tick())
        zone.tombstones[name] = nil
        zones[key] = zone
        return .saved(tag: nextTag)
    }

    /// Removes the record; false when the zone is not there for [user].
    func delete(_ ref: SyncRecordRef, by user: String) -> Bool {
        let key = key(ref.zone, for: user)
        guard canSee(key, user) else { return false }
        if zones[key]?.records.removeValue(forKey: ref.recordName) != nil {
            zones[key]?.tombstones[ref.recordName] = (ref, tick())
        }
        return true
    }

    /// What [user] may see that changed after [cursor].
    func changes(for user: String, since cursor: Int) -> Changes {
        var changes = Changes(cursor: seq)
        for (key, zone) in zones where canSee(key, user) {
            let joined = key.owner == user ? zone.createdSeq : zone.participants[user] ?? 0
            let everything = joined > cursor
            for stored in zone.records.values where everything || stored.seq > cursor {
                changes.records.append((view(stored.record, in: key, for: user), stored.tag))
            }
            for (_, tombstone) in zone.tombstones where !everything && tombstone.seq > cursor {
                var ref = tombstone.ref
                ref.zone = view(key, profileId: ref.zone.profileId, for: user)
                changes.deletions.append(ref)
            }
        }
        changes.goneZones = gone.filter { $0.user == user && $0.seq > cursor }.map(\.zone)
        return changes
    }

    /// The server's copy of a record, as its owner sees it: for tests.
    public func record(_ ref: SyncRecordRef, ownedBy owner: String) -> SyncRecord? {
        zones[ZoneKey(owner: owner, zoneName: ref.zone.zoneName)]?.records[ref.recordName]?.record
    }
}

/// `SyncTransport` over an `InMemoryCloud`, as one person on one phone. Like `CKSyncEngine`, it
/// keeps its own pending list, filled by `outgoingChanged` and drained by `sendNow`, and its state
/// (here the change cursor) goes into the store, so a new transport on the same store resumes.
public actor InMemorySyncTransport: SyncTransport {
    public let cloud: InMemoryCloud
    public let user: String
    private let store: SyncStore
    private let now: @Sendable () -> Int64
    private var pending: [SyncRecordRef: OutgoingKind] = [:]
    private var cursor = 0

    private struct State: Codable {
        var cursor: Int
    }

    public init(cloud: InMemoryCloud, user: String, store: SyncStore, now: @escaping @Sendable () -> Int64) {
        self.cloud = cloud
        self.user = user
        self.store = store
        self.now = now
    }

    public func start() async throws {
        if let data = try await store.engineState(.private) {
            cursor = try JSONDecoder().decode(State.self, from: data).cursor
        }
        try await store.rehand()
        await outgoingChanged()
    }

    public func accountStatus() async -> SyncAccountStatus { .available }

    public func outgoingChanged() async {
        guard let due = try? await store.takeDue(at: now()) else { return }
        for change in due { pending[change.ref] = change.kind }
    }

    public func sendNow() async throws {
        await outgoingChanged()
        // A conflict this phone wins goes round once more with the server's tag.
        for _ in 0..<2 where !pending.isEmpty {
            let batch = pending
            pending = [:]
            for (ref, kind) in batch.sorted(by: { $0.key.key < $1.key.key }) {
                try await send(kind, ref)
            }
            await outgoingChanged()
        }
    }

    private func send(_ kind: OutgoingKind, _ ref: SyncRecordRef) async throws {
        switch kind {
        case .delete:
            _ = await cloud.delete(ref, by: user)
            try await store.setSystemFields(nil, for: ref)
            try await store.confirm(.delete, of: ref)
        case .save:
            guard let record = try await store.record(ref) else { return }
            let baseTag = try await store.systemFields(ref).flatMap { Int(String(decoding: $0, as: UTF8.self)) }
            switch await cloud.save(record, baseTag: baseTag, by: user) {
            case .saved(let tag):
                try await store.setSystemFields(Data(String(tag).utf8), for: ref)
                try await store.confirm(.save, of: ref)
            case .conflict(let server, let tag):
                try await store.setSystemFields(Data(String(tag).utf8), for: ref)
                let kept = try await store.apply([server])
                if !kept.isEmpty { try await store.rehand(kept) }
            case .zoneNotFound:
                if ref.zone.isOwned {
                    await cloud.createZone(ref.zone, by: user)
                    try await store.rehand([ref])
                } else {
                    try await store.removeZone(ref.zone)
                }
            }
        }
    }

    public func fetchNow() async throws {
        let changes = await cloud.changes(for: user, since: cursor)
        for (record, tag) in changes.records {
            try await store.setSystemFields(Data(String(tag).utf8), for: record.ref)
        }
        let kept = try await store.apply(changes.records.map(\.record), deletions: changes.deletions)
        if !kept.isEmpty { try await store.rehand(kept) }
        for zone in changes.goneZones { try await store.removeZone(zone) }
        cursor = changes.cursor
        try await store.setEngineState(try JSONEncoder().encode(State(cursor: cursor)), for: .private)
    }

    public func createZone(_ zone: SyncZone) async throws {
        guard zone.isOwned else { throw SyncTransportError.notOwner }
        await cloud.createZone(zone, by: user)
    }

    public func removeZone(_ zone: SyncZone) async throws {
        if zone.isOwned {
            await cloud.deleteZone(zone, by: user)
        } else {
            await cloud.leave(zone, by: user)
        }
        try await store.removeZone(zone)
    }

    public func stopSharing(_ zone: SyncZone) async throws {
        guard zone.isOwned else { throw SyncTransportError.notOwner }
        await cloud.stopSharing(zone, by: user)
    }
}
