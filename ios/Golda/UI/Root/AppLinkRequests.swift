import Foundation
import Observation

/// What the tabs do with a widget's link.
enum AppLinkStep: Equatable, Sendable {
    case showHome
    /// The form for a new operation, as the toolbar's "+" opens it.
    case newOperation
}

/// A widget's link kept until the tabs can follow it, as `VoiceEntryRequests` keeps a voice note:
/// a link that launches the app waits for the books and the tabs, and one that comes during
/// onboarding waits for its end. A newer link replaces an older one.
///
/// One for the process: the link may arrive before SwiftUI has built a single view.
@MainActor @Observable
final class AppLinkRequests {
    static let shared = AppLinkRequests()

    /// `.home` or `.newOperation`; a voice note waits with the mic's requests instead.
    private(set) var pending: AppLink?

    /// Takes [url] if it is one of the widgets' links.
    @discardableResult
    func open(_ url: URL) -> Bool {
        guard let link = AppLink(url) else { return false }
        if link == .voice {
            VoiceEntryRequests.shared.post()
        } else {
            post(link)
        }
        return true
    }

    func post(_ link: AppLink) {
        pending = link
    }

    /// What the tabs do now, with [presented] over them. Home shows at once. The form waits while
    /// another screen is over the tabs, which keeps what is typed in it, as a voice note does; a
    /// form for a new operation already open is the one asked for. A link followed is used up.
    func take(over presented: AppRoute?) -> AppLinkStep? {
        switch pending {
        case .home:
            pending = nil
            return .showHome
        case .newOperation:
            if presented == .entry(EntryRequest()) {
                pending = nil
                return nil
            }
            guard presented == nil else { return nil }
            pending = nil
            return .newOperation
        case .voice, nil:
            return nil
        }
    }
}
