import Foundation
import GoldaData

/// A CloudKit stand-in for tests: zones owned by people, shares that let others in, change tags
/// that turn a stale save into a conflict, one change counter per server, so phones can fetch
/// what changed since they last looked, refusals with a time to wait, as a full quota gives, and
/// read-only participants, whose changes the server refuses.
/// No network and no iCloud.
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
        /// Participants who may only read.
        var readOnly: Set<String> = []
        var createdSeq: Int
    }

    public enum SaveResult: Sendable {
        case saved(tag: Int)
        case conflict(server: SyncRecord, tag: Int)
        case zoneNotFound
        case retryLater(seconds: Int)
        /// The person may only read the zone (CloudKit's `permissionFailure`).
        case permissionFailure
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
    private var refusals: [(left: Int, seconds: Int)] = []
    /// Every save the server took, in order: what a test can count.
    public private(set) var savesTaken = 0

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

    private func canWrite(_ key: ZoneKey, _ user: String) -> Bool {
        key.owner == user || zones[key]?.readOnly.contains(user) == false
    }

    // MARK: Zones and shares

    func createZone(_ zone: SyncZone, by user: String) {
        let key = key(zone, for: user)
        if zones[key] == nil { zones[key] = Zone(createdSeq: tick()) }
    }

    /// [owner] shares the zone of [profileId] and [participant] accepts, in one step.
    public func share(_ profileId: UUID, of owner: String, with participant: String, readOnly: Bool = false) {
        let key = ZoneKey(owner: owner, zoneName: SyncZone.own(profileId).zoneName)
        zones[key]?.participants[participant] = tick()
        if readOnly { zones[key]?.readOnly.insert(participant) }
    }

    /// Whether the server has a zone for [profileId] of [owner]: for tests.
    public func hasZone(_ profileId: UUID, of owner: String) -> Bool {
        zones[ZoneKey(owner: owner, zoneName: SyncZone.own(profileId).zoneName)] != nil
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
        guard key.owner == user, let removed = zones.removeValue(forKey: key) else { return }
        let at = tick()
        for person in [user] + removed.participants.keys {
            gone.append((person, view(key, profileId: zone.profileId, for: person), at))
        }
    }

    func participants(of zone: SyncZone, for user: String) -> [SyncParticipant] {
        let key = key(zone, for: user)
        guard canSee(key, user), let stored = zones[key], !stored.participants.isEmpty else { return [] }
        let owner = SyncParticipant(id: key.owner, name: key.owner, isOwner: true, isCurrentUser: key.owner == user, status: .joined, canWrite: true)
        return [owner] + stored.participants.keys.sorted().map {
            SyncParticipant(id: $0, name: $0, isOwner: false, isCurrentUser: $0 == user, status: .joined, canWrite: !stored.readOnly.contains($0))
        }
    }

    // MARK: Records

    /// The next [count] saves are refused with "try again in [seconds]".
    public func refuseNextSaves(_ count: Int, retryAfter seconds: Int) {
        refusals.append((count, seconds))
    }

    func save(_ record: SyncRecord, baseTag: Int?, by user: String) -> SaveResult {
        if let first = refusals.first {
            refusals[0].left -= 1
            if refusals[0].left <= 0 { refusals.removeFirst() }
            return .retryLater(seconds: first.seconds)
        }
        let key = key(record.zone, for: user)
        guard canSee(key, user), var zone = zones[key] else { return .zoneNotFound }
        guard canWrite(key, user) else { return .permissionFailure }
        let name = record.ref.recordName
        if let stored = zone.records[name], stored.tag != baseTag {
            return .conflict(server: view(stored.record, in: key, for: user), tag: stored.tag)
        }
        nextTag += 1
        var stored = record
        stored.zone = view(key, profileId: record.zone.profileId, for: key.owner)
        zone.records[name] = StoredRecord(record: stored, tag: nextTag, seq: tick())
        zone.tombstones[name] = nil
        zones[key] = zone
        savesTaken += 1
        return .saved(tag: nextTag)
    }

    /// Removes the record.
    func delete(_ ref: SyncRecordRef, by user: String) -> SaveResult {
        let key = key(ref.zone, for: user)
        guard canSee(key, user) else { return .zoneNotFound }
        guard canWrite(key, user) else { return .permissionFailure }
        if zones[key]?.records.removeValue(forKey: ref.recordName) != nil {
            zones[key]?.tombstones[ref.recordName] = (ref, tick())
        }
        return .saved(tag: 0)
    }

    /// The server's copy of [ref] as [user] sees it, with its tag; nil when there is none.
    func fetch(_ ref: SyncRecordRef, for user: String) -> (record: SyncRecord, tag: Int)? {
        let key = key(ref.zone, for: user)
        guard canSee(key, user), let stored = zones[key]?.records[ref.recordName] else { return nil }
        return (view(stored.record, in: key, for: user), stored.tag)
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
    /// What the server last refused with, for the tests to see.
    public private(set) var lastProblem: SyncProblem?
    public var status: SyncAccountStatus = .available

    private struct State: Codable {
        var cursor: Int
    }

    public init(cloud: InMemoryCloud, user: String, store: SyncStore, now: @escaping @Sendable () -> Int64) {
        self.cloud = cloud
        self.user = user
        self.store = store
        self.now = now
    }

    public func start(accountChanged: @escaping @Sendable () async -> Void) async throws {
        if let data = try await store.engineState(.private) {
            cursor = try JSONDecoder().decode(State.self, from: data).cursor
        }
        try await store.rehand()
        await outgoingChanged()
    }

    public func accountStatus() async -> SyncAccountStatus { status }

    public func setStatus(_ status: SyncAccountStatus) {
        self.status = status
    }

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
            // In a fixed order, so a run repeats; the receiver copes with any (`SyncInbox`).
            for (ref, kind) in batch.sorted(by: { $0.key.key < $1.key.key }) {
                try await send(kind, ref)
            }
            await outgoingChanged()
        }
    }

    private func send(_ kind: OutgoingKind, _ ref: SyncRecordRef) async throws {
        switch kind {
        case .delete:
            if case .permissionFailure = await cloud.delete(ref, by: user) {
                try await refused(ref)
                return
            }
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
                    try await store.zoneGone(ref.zone, .deleted)
                }
            case .retryLater(let seconds):
                // As `CloudKitSyncTransport` does with `retryAfterSeconds`: not a moment before.
                lastProblem = .retryLater(seconds: seconds)
                try await store.postpone([ref], until: now() + Int64(seconds) * 1000)
            case .permissionFailure:
                try await refused(ref)
            }
        }
    }

    /// As `CloudKitSyncTransport` does with `permissionFailure`: the change will never be taken,
    /// so the server's version replaces it here.
    private func refused(_ ref: SyncRecordRef) async throws {
        lastProblem = .notPermitted
        let server = await cloud.fetch(ref, for: user)
        if let server { try await store.setSystemFields(Data(String(server.tag).utf8), for: ref) }
        try await store.refused(ref, serverVersion: server?.record)
    }

    public func fetchNow() async throws {
        let changes = await cloud.changes(for: user, since: cursor)
        for (record, tag) in changes.records {
            try await store.setSystemFields(Data(String(tag).utf8), for: record.ref)
        }
        let kept = try await store.apply(changes.records.map(\.record), deletions: changes.deletions)
        if !kept.isEmpty { try await store.rehand(kept) }
        for zone in changes.goneZones { try await store.zoneGone(zone, .deleted) }
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
    }

    public func stopSharing(_ zone: SyncZone) async throws {
        guard zone.isOwned else { throw SyncTransportError.notOwner }
        await cloud.stopSharing(zone, by: user)
    }

    public func participants(of zone: SyncZone) async throws -> [SyncParticipant] {
        await cloud.participants(of: zone, for: user)
    }
}

public enum SyncTransportError: Error, Sendable {
    /// Only the owner may create, share and stop sharing a zone.
    case notOwner
    case shareNotSaved
}
