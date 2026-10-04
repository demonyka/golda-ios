import AppIntents
import Foundation

/// "Записать голосом": the one intent behind every way into a voice note from outside the app,
/// Control Center's control, the Action Button, Siri and Spotlight (`GoldaShortcuts`), and the mic
/// of the «Можно сегодня» widget.
///
/// An `AudioRecordingIntent` (iOS 18): it records where the person is, without the app, beside a
/// Live Activity (`BackgroundVoiceNote`), once everything a note needs is in place. A
/// `LiveActivityIntent` too: only such an intent may start an activity with the app out of sight
/// (ActivityKit refuses the others with `visibility`, as the simulator showed). Otherwise, and
/// whenever the app is on screen, the app comes up and its mic records as a tap would: the consent
/// screen, the microphone prompt or the toast about the key must be seen. Asked again while a note
/// from outside listens, it ends that note.
///
/// Compiled into the widgets as well, where the control and the widget's button name it; the
/// system runs it in the app, the only process that can record.
struct StartVoiceNoteIntent: AudioRecordingIntent, LiveActivityIntent {
    static let title = LocalizedStringResource("Say a purchase", table: "EntryPoints", comment: "The voice entry point: Shortcuts, Siri, Control Center, the quick action.")
    // Typed as the requirement is: a plain `IntentDescription` would not witness it.
    static let description: IntentDescription? = IntentDescription(LocalizedStringResource(
        "Records a purchase by voice and opens Golda only when it has to.", table: "EntryPoints",
        comment: "What the voice entry point does, in Shortcuts."
    ))
    /// Starts in the background; `continueInForeground` brings the app up when the note needs it.
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !GOLDA_WIDGETS
        try await VoiceNoteLauncher.shared.start {
            // No question asked: the person pressed the button to record, and the app is how.
            try await continueInForeground(alwaysConfirm: false)
        }
        #endif
        return .result()
    }
}

/// «Стоп» on the Live Activity of a note recorded outside the app. A Live Activity intent, so the
/// system runs it in the app, which holds the microphone, even from the Lock Screen.
struct StopVoiceNoteIntent: LiveActivityIntent {
    static let title = LocalizedStringResource("Stop recording", table: "VoiceActivity", comment: "The Live Activity's button that ends a voice note; also its name in Shortcuts.")
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !GOLDA_WIDGETS
        VoiceNoteLauncher.shared.stop()
        #endif
        return .result()
    }
}

/// «Отменить» on the Live Activity: deletes what the note booked, as the toast's button does. It
/// carries the ids, since the app may have been relaunched in between. Deleting from the books asks
/// for the phone to be unlocked; recording does not, as a note only adds.
struct UndoVoiceNoteIntent: LiveActivityIntent {
    static let title = LocalizedStringResource("Undo the voice note", table: "VoiceActivity", comment: "The Live Activity's button that deletes what a voice note booked; also its name in Shortcuts.")
    static let isDiscoverable = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: LocalizedStringResource("Profile", table: "VoiceActivity", comment: "Hidden parameter of the voice note's undo: the profile it booked into."))
    var profileId: String

    @Parameter(title: LocalizedStringResource("Operations", table: "VoiceActivity", comment: "Hidden parameter of the voice note's undo: what it booked."))
    var operationIds: [String]

    init() {}

    init(_ ticket: VoiceUndoTicket) {
        profileId = ticket.profileId.uuidString
        operationIds = ticket.operationIds.map(\.uuidString)
    }

    var ticket: VoiceUndoTicket? {
        guard let profile = UUID(uuidString: profileId) else { return nil }
        return VoiceUndoTicket(profileId: profile, operationIds: operationIds.compactMap(UUID.init(uuidString:)))
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !GOLDA_WIDGETS
        if let ticket { await VoiceNoteLauncher.shared.undo(ticket) }
        #endif
        return .result()
    }
}
