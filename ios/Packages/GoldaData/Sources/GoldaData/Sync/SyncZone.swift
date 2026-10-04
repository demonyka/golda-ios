import Foundation

/// Which of the person's two CloudKit databases a zone lives in: their own profiles sit in the
/// private one, the profiles others shared with them in the shared one.
public enum SyncScope: String, Codable, Sendable, CaseIterable {
    case `private`
    case shared
}

/// A profile's zone (D21): one zone per profile, named after it, shared whole with one `CKShare`.
///
/// The value carries no CloudKit type, so the queue, the store and the stub transport stay free of
/// it; `CloudKitMapping` (GoldaSync) converts it to `CKRecordZone.ID`.
public struct SyncZone: Hashable, Codable, Sendable {
    public static let namePrefix = "profile-"
    /// CloudKit's name for the signed-in person as a zone's owner (`CKCurrentUserDefaultName`). Every
    /// zone of the private database is theirs; a shared zone names its real owner instead.
    public static let currentUser = "__defaultOwner__"

    public var profileId: UUID
    public var ownerName: String
    public var scope: SyncScope

    public init(profileId: UUID, ownerName: String = SyncZone.currentUser, scope: SyncScope = .private) {
        self.profileId = profileId
        self.ownerName = ownerName
        self.scope = scope
    }

    /// The zone of a profile this person owns.
    public static func own(_ profileId: UUID) -> SyncZone { SyncZone(profileId: profileId) }

    /// `profile-<uuid>`, lowercased so the name is the same whoever formats the UUID.
    public var zoneName: String { Self.namePrefix + profileId.uuidString.lowercased() }

    /// The zone called [zoneName], or nil for a zone that is not a profile's (CloudKit's default zone,
    /// a zone of a later version).
    public init?(zoneName: String, ownerName: String, scope: SyncScope) {
        guard zoneName.hasPrefix(Self.namePrefix),
              let id = UUID(uuidString: String(zoneName.dropFirst(Self.namePrefix.count)))
        else { return nil }
        self.init(profileId: id, ownerName: ownerName, scope: scope)
    }

    /// Whether this person owns the zone and so may share it, stop sharing it and delete it.
    public var isOwned: Bool { scope == .private }

    /// One string per zone, for keys of the store's tables.
    public var key: String { "\(scope.rawValue)|\(ownerName)|\(zoneName)" }
}
