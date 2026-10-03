import Foundation
import Observation
import SwiftUI

/// A screen presented over the tabs. Every way into one goes through `AppRouter`, so the tabs,
/// their toolbars and the rows that lead somewhere never need to know what the screen is.
enum AppRoute: Equatable, Identifiable, Sendable {
    /// The operation form: new from "+", an operation from its row, a purchase being weighed up.
    case entry(EntryRequest)
    /// This phone's settings, from the gear.
    case settings
    /// The profiles of this phone, from the profile menu.
    case profiles
    /// Asks before the first recording goes to the voice provider (D9).
    case voiceConsent

    /// A new identity re-presents the sheet, so the form for another operation starts afresh.
    var id: String {
        switch self {
        case .entry(let request):
            "entry." + (request.editing?.op.id.uuidString ?? request.wishId?.uuidString ?? "new")
        case .settings: "settings"
        case .profiles: "profiles"
        case .voiceConsent: "voiceConsent"
        }
    }
}

/// What is presented over the tabs. `MainTabs` owns one and puts it in the environment; anything
/// under it opens a screen with `router.present(...)`:
///
///     @Environment(AppRouter.self) private var router
///     Button("Settings") { router.present(.settings) }
@MainActor @Observable
final class AppRouter {
    /// The screen over the tabs; nil when the tabs show.
    var presented: AppRoute?

    init(presented: AppRoute? = nil) {
        self.presented = presented
    }

    /// Opens [route] over whatever tab or page is on screen.
    func present(_ route: AppRoute) {
        presented = route
    }

    func dismiss() {
        presented = nil
    }
}

/// The screen for a route, over the tabs of the profile on screen. Each destination lives in a file
/// of its own and keeps this signature, so filling one in leaves `MainTabs` alone.
struct RouteDestination: View {
    let route: AppRoute
    let data: AppData

    var body: some View {
        switch route {
        case .entry(let request): EntrySheet(data: data, request: request)
        case .settings: SettingsScreen(data: data)
        case .profiles: ProfilesScreen()
        case .voiceConsent: VoiceConsentScreen()
        }
    }
}
