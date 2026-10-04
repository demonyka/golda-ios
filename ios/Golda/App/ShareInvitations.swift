import CloudKit
import OSLog

private let log = Logger(subsystem: "com.f4studio.golda", category: "Sharing")

/// Where an accepted iCloud invitation goes. The system hands it to the scene (`SceneDelegate`),
/// at a cold launch with the connection options and later through the delegate; both come here,
/// and go on to the app's sync once the launch has made it (`AppLaunch`). One that comes first
/// waits for it.
@MainActor
enum ShareInvitations {
    private static var sync: AppSync?
    private static var waiting: [CKShare.Metadata] = []

    static func accept(_ metadata: CKShare.Metadata) {
        guard let sync else {
            log.notice("An invitation arrived before the app's data was open; it waits")
            waiting.append(metadata)
            return
        }
        sync.accept(metadata)
    }

    /// The launch's sync takes the invitations from now on, and those that waited.
    static func attach(_ sync: AppSync) {
        self.sync = sync
        let invitations = waiting
        waiting = []
        invitations.forEach(sync.accept)
    }
}
