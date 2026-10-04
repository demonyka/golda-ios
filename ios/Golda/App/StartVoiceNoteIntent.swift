import AppIntents
import Foundation

/// "Записать голосом": the one intent behind every way into a voice note from outside the app,
/// Control Center's control, the Action Button, Siri and Spotlight (`GoldaShortcuts`).
///
/// The app comes to the foreground first: the microphone records only there, and the consent
/// screen or the toast a tap on the mic would bring must be seen. Compiled into the widgets as well,
/// where the control names it; the system still runs it in the app.
struct StartVoiceNoteIntent: AppIntent {
    static let title = LocalizedStringResource("Say a purchase", table: "EntryPoints", comment: "The voice entry point: Shortcuts, Siri, Control Center, the quick action.")
    // Typed as the requirement is: a plain `IntentDescription` would not witness it.
    static let description: IntentDescription? = IntentDescription(LocalizedStringResource("Opens Golda and starts recording, as a tap on the mic does.", table: "EntryPoints", comment: "What the voice entry point does, in Shortcuts."))
    /// The app is brought up before `perform` runs: iOS 26's form of `openAppWhenRun`, now deprecated.
    static let supportedModes: IntentModes = .foreground(.immediate)

    @MainActor
    func perform() async throws -> some IntentResult {
        VoiceEntryRequests.shared.post()
        return .result()
    }
}
