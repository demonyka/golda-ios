import CloudKit
import OSLog

private let log = Logger(subsystem: "com.f4studio.golda", category: "Sharing")

/// Where an accepted iCloud invitation goes. The system hands it to the scene (`SceneDelegate`),
/// at a cold launch with the connection options and later through the delegate; both come here.
///
/// Until stage 5c only the debug build's sync spike takes invitations; a release build has no
/// sync yet, so it notes the invitation and leaves it unaccepted.
@MainActor
enum ShareInvitations {
    static func accept(_ metadata: CKShare.Metadata) {
        #if DEBUG
        Task { await SyncSpike.shared.accept(metadata) }
        #else
        log.notice("A share invitation arrived; this build does not sync yet")
        #endif
    }
}
