import CloudKit
import UIKit

/// UIKit's part of the launch that SwiftUI has no modifier for: the quick action on the app icon.
///
/// A cold launch hands the action over with the scene's connection; a running app gets it through
/// the scene's delegate. Both become a voice request (`VoiceEntryRequests`).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if let item = options.shortcutItem { Self.answer(item) }
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    /// CloudKit's silent push: the other phone wrote. A closed app is launched with no window, so
    /// the sync starts here, and the widgets get the new figures without the app being opened.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        guard ReminderBackground.sync != nil else { return .noData }
        await ReminderBackground.catchUp()
        return .newData
    }

    /// Whether [item] was the app's: only the voice note is.
    @discardableResult
    static func answer(_ item: UIApplicationShortcutItem) -> Bool {
        guard VoiceEntry.isRequest(shortcutType: item.type) else { return false }
        VoiceEntryRequests.shared.post()
        return true
    }
}

/// SwiftUI keeps the window; this only hears what SwiftUI does not: the quick action while the app
/// runs, and an accepted iCloud invitation (Info.plist `CKSharingSupported`), whether it launched
/// the app or found it running.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata { ShareInvitations.accept(metadata) }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        ShareInvitations.accept(cloudKitShareMetadata)
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(AppDelegate.answer(shortcutItem))
    }
}
