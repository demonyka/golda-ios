import Foundation
import GoldaCore
import GoldaData

/// The kinds of record a profile's zone holds. The raw values are CloudKit record types, so they
/// are part of the server schema and never change.
///
/// Stage 5a carries the profile and its operations with their postings; accounts, obligations,
/// goals and wishes join in 5b the same way.
public enum SyncRecordType: String, Codable, Sendable, CaseIterable {
    case profile = "Profile"
    case operation = "Operation"
    case posting = "Posting"
}

/// Where a record lives: its zone, its type and its id. The CloudKit record name is
/// `<Type>.<uuid>`, so a name says what it is without fetching the record, and two kinds can never
/// collide even if an id were reused.
public struct SyncRecordRef: Hashable, Codable, Sendable {
    public var zone: SyncZone
    public var type: SyncRecordType
    public var id: UUID

    public init(zone: SyncZone, type: SyncRecordType, id: UUID) {
        self.zone = zone
        self.type = type
        self.id = id
    }

    public var recordName: String { "\(type.rawValue).\(id.uuidString.lowercased())" }

    /// The record called [recordName] in [zone], or nil for a name this version does not know
    /// (the zone's `CKShare`, a type of a later version).
    public init?(recordName: String, zone: SyncZone) {
        let parts = recordName.split(separator: ".", maxSplits: 1)
        guard parts.count == 2, let type = SyncRecordType(rawValue: String(parts[0])),
              let id = UUID(uuidString: String(parts[1]))
        else { return nil }
        self.init(zone: zone, type: type, id: id)
    }

    /// One string per record, for keys of the store's tables.
    var key: String { "\(zone.key)|\(recordName)" }
}

/// What a record says, as the app's own values.
public enum SyncPayload: Equatable, Codable, Sendable {
    /// The zone's root: the profile's name and settings (D16, D21). Its id is the zone's profile.
    case profile(Profile)
    /// An operation's header. [postingCount] lets a receiver hold the operation back until all its
    /// postings have arrived, since CloudKit may deliver them in different batches.
    case operation(GoldaCore.Operation, postingCount: Int)
    case posting(Posting)

    public var type: SyncRecordType {
        switch self {
        case .profile: .profile
        case .operation: .operation
        case .posting: .posting
        }
    }

    public var id: UUID {
        switch self {
        case .profile(let profile): profile.id
        case .operation(let operation, _): operation.id
        case .posting(let posting): posting.id
        }
    }
}

/// A record of a profile's zone as the app sees it: the payload, and who wrote it last and when.
public struct SyncRecord: Equatable, Codable, Sendable {
    public var zone: SyncZone
    public var payload: SyncPayload
    /// When the record was last written, in milliseconds since 1970, by the writer's clock. The
    /// last writer wins on conflicts (ARCHITECTURE, «Правила»).
    public var updatedAt: Int64
    /// The phone that wrote it last, so a conflict between equal times still has one winner and
    /// the spike can show who wrote what.
    public var authorDevice: String

    public init(zone: SyncZone, payload: SyncPayload, updatedAt: Int64, authorDevice: String) {
        self.zone = zone
        self.payload = payload
        self.updatedAt = updatedAt
        self.authorDevice = authorDevice
    }

    public var ref: SyncRecordRef { SyncRecordRef(zone: zone, type: payload.type, id: payload.id) }
}

/// Last writer wins, per record (ARCHITECTURE, «Конфликты»).
public enum SyncConflict {
    /// Whether [incoming] replaces [local]. Equal times fall to the larger device name, so both
    /// phones settle on the same record whichever of them resolves the conflict.
    public static func incomingWins(_ incoming: SyncRecord, over local: SyncRecord) -> Bool {
        if incoming.updatedAt != local.updatedAt { return incoming.updatedAt > local.updatedAt }
        return incoming.authorDevice >= local.authorDevice
    }
}
