import Foundation

/// The links the widgets open, `golda://…`; the app claims the scheme in Info.plist. Compiled into
/// the widgets too, which build their links from here.
enum AppLink: Equatable, Sendable {
    /// The mic: a voice note, as a tap on it (`VoiceEntry`).
    case voice
    /// "+": the form for a new operation, as the toolbar's "+".
    case newOperation
    /// A tap beside the buttons: Home, where «Можно сегодня» is.
    case home

    /// Schemes and hosts are case-insensitive; a trailing slash is the same link.
    init?(_ url: URL) {
        guard url.scheme?.lowercased() == "golda" else { return nil }
        switch url.host()?.lowercased() {
        case "voice": self = .voice
        case "new": self = .newOperation
        case "home": self = .home
        default: return nil
        }
    }

    var url: URL {
        switch self {
        case .voice: VoiceEntry.url
        case .newOperation: URL(string: "golda://new")!
        case .home: URL(string: "golda://home")!
        }
    }
}
