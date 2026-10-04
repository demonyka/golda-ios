import Foundation
import Testing

@testable import Golda

/// Where a note asked for from outside the app is taken: recorded without the app only when it can
/// go all the way without a screen; otherwise the app comes up as before.
@Suite struct VoiceNoteRouteTests {
    /// Everything in place, the app out of sight.
    private let ready = VoiceNoteRoute.Conditions(
        appIsActive: false, isRecordingOutside: false, isRecordingInApp: false, hasBooks: true, hasConsent: true, hasKey: true,
        microphone: .granted, allowsLiveActivities: true
    )

    private func route(_ change: (inout VoiceNoteRoute.Conditions) -> Void) -> VoiceNoteRoute {
        var conditions = ready
        change(&conditions)
        return VoiceNoteRoute.of(conditions)
    }

    @Test func withEverythingInPlaceTheNoteIsRecordedWhereThePersonIs() {
        #expect(VoiceNoteRoute.of(ready) == .background)
    }

    /// The consent screen, the system's prompt, the toast about the key and onboarding are screens
    /// of the app: the first note brings it up, as before.
    @Test func whatANoteStillNeedsBringsTheAppUp() {
        #expect(route { $0.hasConsent = false } == .inApp)
        #expect(route { $0.hasKey = false } == .inApp)
        #expect(route { $0.microphone = .undetermined } == .inApp)
        #expect(route { $0.microphone = .denied } == .inApp)
        #expect(route { $0.hasBooks = false } == .inApp)
        // iOS records in the background only beside a Live Activity.
        #expect(route { $0.allowsLiveActivities = false } == .inApp)
    }

    @Test func theAppOnScreenTakesTheNoteWithItsOwnMic() {
        #expect(route { $0.appIsActive = true } == .inApp)
    }

    /// Asked again while a note from outside listens, as a second tap on the mic: it ends, even
    /// with the app opened in the meantime.
    @Test func askingAgainWhileListeningEndsTheNote() {
        #expect(route { $0.isRecordingOutside = true } == .stop)
        #expect(route {
            $0.isRecordingOutside = true
            $0.appIsActive = true
        } == .stop)
    }

    /// The app's own mic still listening after the person went home (the audio mode keeps it on):
    /// a press ends that note, as a second tap would, instead of starting a second recorder beside
    /// it. With the app on screen its mic is there to tap, and the request is left to it as before.
    @Test func askingWhileTheAppsMicListensOutOfSightEndsThatNote() {
        #expect(route { $0.isRecordingInApp = true } == .stopInApp)
        #expect(route {
            $0.isRecordingInApp = true
            $0.hasKey = false
        } == .stopInApp)
        #expect(route {
            $0.isRecordingInApp = true
            $0.appIsActive = true
        } == .inApp)
    }
}
