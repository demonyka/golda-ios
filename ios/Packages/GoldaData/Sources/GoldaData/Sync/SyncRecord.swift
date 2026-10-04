import Foundation
import GoldaCore

/// The kinds of record a profile's zone holds, one per table of the books except `posting`: an
/// operation's postings travel inside its record (D58), so the two are one unit for conflicts. The
/// raw values are CloudKit record types, so they are part of the server schema and never change
/// (`Posting` records of the first 5b builds are no longer read). Rates are not here: they are the
/// same for everyone and every phone fetches its own.
public enum SyncRecordType: String, Codable, Sendable, CaseIterable {
    case profile = "Profile"
    case account = "Account"
    case operation = "Operation"
    case obligation = "Obligation"
    case goal = "Goal"
    case wish = "Wish"

    /// The table the records of this type are rows of.
    var tableName: String {
        switch self {
        case .profile: "profile"
        case .account: "account"
        case .operation: "operation"
        case .obligation: "obligation"
        case .goal: "goal"
        case .wish: "wish"
        }
    }

    init?(tableName: String) {
        guard let type = Self.allCases.first(where: { $0.tableName == tableName }) else { return nil }
        self = type
    }
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
    public var key: String { "\(zone.key)|\(recordName)" }
}

/// What a record says, as the app's own values: one row of the books.
public enum SyncPayload: Equatable, Codable, Sendable {
    /// The zone's root: the profile's name and settings (D16, D21). Its id is the zone's profile.
    /// Its `sort` travels but is not applied: the order of profiles is each phone's own.
    case profile(Profile)
    case account(Account)
    /// An operation with all its postings, in the order the ledger wrote them. One record, so a
    /// receiver never sees half a transfer, and last writer wins for the whole: two phones editing
    /// one operation never mix the legs of one version with the header of another.
    case operation(GoldaCore.Operation, postings: [Posting])
    /// A monthly payment with its place in the creation order (payments of one day are listed in it).
    case obligation(Obligation, createdAt: Int64)
    /// A goal with its place in the creation order (the oldest becomes main, D27).
    case goal(Goal, createdAt: Int64)
    case wish(Wish)

    public var type: SyncRecordType {
        switch self {
        case .profile: .profile
        case .account: .account
        case .operation: .operation
        case .obligation: .obligation
        case .goal: .goal
        case .wish: .wish
        }
    }

    public var id: UUID {
        switch self {
        case .profile(let profile): profile.id
        case .account(let account): account.id
        case .operation(let operation, _): operation.id
        case .obligation(let obligation, _): obligation.id
        case .goal(let goal, _): goal.id
        case .wish(let wish): wish.id
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
    /// The phone that wrote it last, so a conflict between equal times still has one winner.
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
        incomingWins(updatedAt: incoming.updatedAt, author: incoming.authorDevice, overUpdatedAt: local.updatedAt, author: local.authorDevice)
    }

    static func incomingWins(updatedAt: Int64, author: String, overUpdatedAt localUpdatedAt: Int64, author localAuthor: String) -> Bool {
        if updatedAt != localUpdatedAt { return updatedAt > localUpdatedAt }
        return author >= localAuthor
    }
}
