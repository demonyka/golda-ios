import Foundation
import Observation

/// The ways into a voice note from outside the app, the port of Android's `ACTION_VOICE` from the
/// tile, the widget and the shortcut. Compiled into the widgets too: the widget links to [url].
enum VoiceEntry {
    /// The widget's link (`widgetURL`); the app claims the scheme in Info.plist.
    static let url = URL(string: "golda://voice")!

    /// The quick action on the app icon, `UIApplicationShortcutItems` in Info.plist.
    static let shortcutType = "com.f4studio.golda.voice"

    /// Schemes and hosts are case-insensitive; a trailing slash is the same link.
    static func isRequest(_ url: URL) -> Bool {
        url.scheme?.lowercased() == Self.url.scheme && url.host()?.lowercased() == Self.url.host()
    }

    static func isRequest(shortcutType type: String) -> Bool {
        type == shortcutType
    }
}

/// A voice note asked for from outside, kept until the mic can show it, the port of Android's
/// conflated `voiceRequests` channel: asking again before it is taken is still one note, and a
/// request made during onboarding waits for the tabs.
///
/// One for the process: the intent, the quick action and the link may each arrive before SwiftUI
/// has built a single view.
@MainActor @Observable
final class VoiceEntryRequests {
    static let shared = VoiceEntryRequests()

    private(set) var isPending = false

    func post() {
        isPending = true
    }

    /// Whether a note was asked for; the request is used up.
    func take() -> Bool {
        defer { isPending = false }
        return isPending
    }

    func discard() {
        isPending = false
    }
}
