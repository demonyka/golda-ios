import Foundation

/// Whether this phone can sync: the iCloud account as CloudKit sees it.
public enum SyncAccountStatus: String, Sendable {
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine
}

/// One line of what the transport did, for the debug log and the spike's report.
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

/// The server side of sync: CloudKit in the app (`CloudKitSyncTransport`), memory in tests
/// (`InMemorySyncTransport`). The local side is the `SyncStore` the transport was made with: the
/// transport takes the due part of its queue and writes into it what the server sends.
public protocol SyncTransport: AnyObject, Sendable {
    /// Picks up where the last process stopped and starts following the server.
    func start() async throws
    func accountStatus() async -> SyncAccountStatus
    /// Hands the store's due changes over; called after every local change. A delete waiting out
    /// its undo window is handed over when the window ends.
    func outgoingChanged() async
    /// Hands over what is due and sends it now.
    func sendNow() async throws
    /// Asks the server for what changed now, in both databases.
    func fetchNow() async throws
    /// Creates the zone of a profile this person owns.
    func createZone(_ zone: SyncZone) async throws
    /// Takes the profile away from this phone: the owner deletes the zone, and with it the profile
    /// of everyone it was shared with; a participant leaves the share. Local data goes either way.
    func removeZone(_ zone: SyncZone) async throws
    /// The owner stops sharing the zone: the participants lose it, the owner keeps it.
    func stopSharing(_ zone: SyncZone) async throws
}
