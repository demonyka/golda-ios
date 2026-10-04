import Foundation

/// What is to be done to a record on the server.
public enum OutgoingKind: String, Codable, Sendable {
    case save
    case delete
}

/// One record's change waiting to reach the server. The queue keeps one entry per record: the
/// latest wish wins, so a save then a delete sends only the delete, and a delete undone by a save
/// sends only the save.
public struct OutgoingChange: Equatable, Codable, Sendable {
    public var ref: SyncRecordRef
    public var kind: OutgoingKind
    /// Grows with each change of the entry, so a confirmation of an older send does not drop a
    /// newer wish that came while it was in flight.
    public var revision: Int64
    /// Not before this moment (ms since 1970): a delete waits out the undo window, so "Отменить"
    /// before it ends never reaches the server (ARCHITECTURE, «Удаление и „Отменить“»).
    public var notBefore: Int64
    /// The revision last handed to the transport, nil while it has not been.
    public var handedRevision: Int64?

    public init(ref: SyncRecordRef, kind: OutgoingKind, revision: Int64, notBefore: Int64, handedRevision: Int64? = nil) {
        self.ref = ref
        self.kind = kind
        self.revision = revision
        self.notBefore = notBefore
        self.handedRevision = handedRevision
    }

    /// Whether the transport should take it now: due, and not already handed in this revision.
    public func isDue(at now: Int64) -> Bool { notBefore <= now && handedRevision != revision }
}

/// The queue's rules, apart from where it is kept.
public enum OutgoingQueue {
    /// How long a delete waits for "Отменить": the undo toast's ten seconds.
    public static let undoWindow: Int64 = 10_000

    /// The entry for [ref] once [kind] is asked for at [now], given the one it had.
    public static func merge(
        _ existing: OutgoingChange?, kind: OutgoingKind, ref: SyncRecordRef, now: Int64, undoWindow: Int64 = undoWindow
    ) -> OutgoingChange {
        OutgoingChange(
            ref: ref, kind: kind, revision: (existing?.revision ?? 0) + 1,
            notBefore: kind == .delete ? now + undoWindow : now,
            handedRevision: existing?.handedRevision
        )
    }

    /// Whether the server's confirmation of a [kind] settles [entry]: it is the wish last handed
    /// over and nothing newer came since, which stays queued.
    public static func isSettled(_ entry: OutgoingChange, by kind: OutgoingKind) -> Bool {
        entry.kind == kind && entry.handedRevision == entry.revision
    }

    /// [entry] once the server said to try again not before [until] (CloudKit's `retryAfterSeconds`
    /// on a full quota, throttling, a busy zone): taken back from the transport, and not handed
    /// over again until then. A newer wish keeps its revision, so it is the one that goes.
    public static func postponed(_ entry: OutgoingChange, until: Int64) -> OutgoingChange {
        var entry = entry
        entry.notBefore = max(entry.notBefore, until)
        entry.handedRevision = nil
        return entry
    }
}
