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

    /// Whether [item] was the app's: only the voice note is.
    @discardableResult
    static func answer(_ item: UIApplicationShortcutItem) -> Bool {
        guard VoiceEntry.isRequest(shortcutType: item.type) else { return false }
        VoiceEntryRequests.shared.post()
        return true
    }
}

/// SwiftUI keeps the window; this only hears the quick action while the app runs.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(AppDelegate.answer(shortcutItem))
    }
}
