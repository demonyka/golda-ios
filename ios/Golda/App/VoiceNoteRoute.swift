import Foundation

/// Where a voice note asked for from outside the app is taken (`StartVoiceNoteIntent`: Control
/// Center, the Action Button, Siri, the widget's mic).
enum VoiceNoteRoute: Equatable, Sendable {
    /// The app comes up and its mic records, as before: everything a first note needs (the
    /// consent screen, the microphone prompt, the key) is a screen in the app.
    case inApp
    /// Recorded where the person is, with the app out of sight and a Live Activity on screen.
    case background
    /// A note from outside is being recorded: asking again ends it, as a second tap on the mic does.
    case stop

    /// What a note needs to be recorded outside the app, as things stand when it is asked for.
    struct Conditions: Equatable, Sendable {
        /// The app is on screen: its own mic takes the note.
        var appIsActive: Bool
        /// A note recorded outside the app is listening now.
        var isRecordingOutside: Bool
        /// Onboarding is over and a profile is open: there are books to write the note into.
        var hasBooks: Bool
        /// The person agreed to send voice to Gemini (App Review 5.1.2(i)).
        var hasConsent: Bool
        /// A Gemini key is saved, so the note can be understood at once.
        var hasKey: Bool
        var microphone: MicPermission
        /// The person allows the app's Live Activities: iOS records in the background only beside one.
        var allowsLiveActivities: Bool
    }

    /// Only a note that can go all the way without a screen is recorded outside the app. Anything
    /// missing (consent, the microphone, a key, books) brings the app up, where the mic shows what
    /// a tap would: the consent screen, the system's prompt, the toast about the key.
    static func of(_ conditions: Conditions) -> VoiceNoteRoute {
        if conditions.isRecordingOutside { return .stop }
        if conditions.appIsActive { return .inApp }
        let ready = conditions.hasBooks && conditions.hasConsent && conditions.hasKey
            && conditions.microphone == .granted && conditions.allowsLiveActivities
        return ready ? .background : .inApp
    }
}
