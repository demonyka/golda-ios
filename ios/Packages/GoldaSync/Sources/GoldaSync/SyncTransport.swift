import Foundation
import GoldaData

/// Whether this phone can sync: the iCloud account as CloudKit sees it.
public enum SyncAccountStatus: String, Sendable {
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine
}

/// What went wrong with iCloud, in words the app can turn into a sentence. No CloudKit types, so
/// the app and its tests can name every case.
public enum SyncProblem: Error, Equatable, Sendable {
    /// Not signed in to iCloud, or iCloud is off for the app.
    case noAccount
    /// The iCloud storage of the profile's owner is full.
    case iCloudFull
    /// The server asked to wait this many seconds before trying again (a full quota it reports
    /// as temporary, throttling, a busy zone).
    case retryLater(seconds: Int)
    /// No network, or iCloud did not answer.
    case offline
    /// The owner gave this person read-only access, or took it away.
    case notPermitted
    /// Anything else, with CloudKit's code for the log.
    case other(code: Int)
}

/// One line of what the transport did, for the debug log.
public struct SyncLogEntry: Sendable, Identifiable {
    public let id = UUID()
    public let date: Date
    public let scope: SyncScope?
    public let message: String

    public init(date: Date = Date(), scope: SyncScope?, message: String) {
        self.date = date
        self.scope = scope
        self.message = message
    }
}

/// A person a profile is shared with, as the owner and the participants see them.
public struct SyncParticipant: Equatable, Sendable, Identifiable {
    public enum Status: Sendable {
        case invited
        case joined
        case removed
    }

    public var id: String
    /// The name iCloud knows them by, nil when it does not tell (an invitation not yet accepted).
    public var name: String?
    public var isOwner: Bool
    public var isCurrentUser: Bool
    public var status: Status
    public var canWrite: Bool

    public init(id: String, name: String?, isOwner: Bool, isCurrentUser: Bool, status: Status, canWrite: Bool) {
        self.id = id
        self.name = name
        self.isOwner = isOwner
        self.isCurrentUser = isCurrentUser
        self.status = status
        self.canWrite = canWrite
    }
}

/// The server side of sync: CloudKit in the app (`CloudKitSyncTransport`), memory in tests
/// (`InMemorySyncTransport`). The local side is the `SyncStore` the transport was made with: the
/// transport takes the due part of its queue and writes into it what the server sends.
public protocol SyncTransport: AnyObject, Sendable {
    /// Picks up where the last process stopped and starts following the server. [accountChanged]
    /// hears that the iCloud account signed in, out or switched, after the store forgot what
    /// belonged to the old one.
    func start(accountChanged: @escaping @Sendable () async -> Void) async throws
    func accountStatus() async -> SyncAccountStatus
    /// Hands the store's due changes over; called after every local change. A delete waiting out
    /// its undo window, or a change the server asked to wait, is handed over when its time comes.
    func outgoingChanged() async
    /// Hands over what is due and sends it now.
    func sendNow() async throws
    /// Asks the server for what changed now, in both databases.
    func fetchNow() async throws
    /// Creates the zone of a profile this person owns.
    func createZone(_ zone: SyncZone) async throws
    /// Tells the server the profile left this phone: the owner deletes the zone, and with it the
    /// profile of everyone it was shared with; a participant leaves the share. The local books are
    /// already gone (`Repository.deleteProfile`).
    func removeZone(_ zone: SyncZone) async throws
    /// The owner stops sharing the zone: the participants lose it, the owner keeps it.
    func stopSharing(_ zone: SyncZone) async throws
    /// Who the zone is shared with, its owner included; empty when it is not shared.
    func participants(of zone: SyncZone) async throws -> [SyncParticipant]
}
