import Foundation
import GoldaCore
import GoldaData
import Testing

@testable import Golda

/// The mic's state machine over a fake microphone and a fake voice service: Android's
/// `rememberVoice` toggle, with consent first (App Review 5.1.2(i)).
@MainActor @Suite struct VoiceMicModelTests {
    @Test func aNoteGoesFromIdleThroughRecordingAndThinkingBackToIdle() async throws {
        let h = try MicHarness()
        try await h.open()
        let gate = Gate()
        h.notes.hold(gate)
        #expect(h.mic.state == .idle)

        h.mic.tap()
        #expect(h.mic.state == .recording)
        // Named for the moment and the profile open then, as the queue reads it back.
        let file = try #require(h.recorder.started.first)
        #expect(file.lastPathComponent == "\(AppHarness.now).\(h.profileId.uuidString).wav")

        h.recorder.levels = [0.2, 0.05]
        h.mic.sampleLevel()
        #expect(h.mic.level == 0.2)
        h.mic.sampleLevel()
        #expect(h.mic.level == 0.05)

        h.mic.tap()
        #expect(h.recorder.stops == 1)
        #expect(h.mic.state == .thinking)
        #expect(h.mic.level == 0)

        // While the note is worked out a tap does nothing.
        h.mic.tap()
        #expect(h.recorder.stops == 1)
        #expect(h.recorder.started.count == 1)
        #expect(h.mic.state == .thinking)

        await eventually { h.notes.understood == [file] }
        await gate.open()
        await eventually { h.mic.state == .idle }
        #expect(h.recorder.started.count == 1)
    }

    @Test func aStrayTapOrSilenceSendsNothing() async throws {
        let h = try MicHarness()
        try await h.open()
        // The recorder judges the note (`RecordingJudge`) and throws it away.
        h.recorder.keepsNote = false

        h.mic.tap()
        h.mic.tap()
        #expect(h.mic.state == .idle)
        #expect(h.recorder.stops == 1)
        try await Task.sleep(for: .milliseconds(50))
        #expect(h.notes.understood.isEmpty)
        #expect(h.mic.toast == nil)

        // And the mic is ready for the next one.
        h.recorder.keepsNote = true
        h.mic.tap()
        #expect(h.mic.state == .recording)
    }

    @Test func theMinuteRunningOutEndsTheNoteAsATapWould() async throws {
        let h = try MicHarness()
        try await h.open()
        h.mic.tap()
        h.recorder.isRecording = false

        h.mic.sampleLevel()
        #expect(h.recorder.stops == 1)
        await eventually { h.notes.understood.count == 1 }
        await eventually { h.mic.state == .idle }
    }

    @Test func aDeniedMicrophoneSaysSoAndLeadsToTheSystemSettings() async throws {
        let h = try MicHarness()
        try await h.open()
        h.recorder.permission = .denied

        h.mic.tap()
        #expect(h.mic.state == .idle)
        #expect(h.recorder.started.isEmpty)
        #expect(h.recorder.permissionRequests == 0)
        let toast = try #require(h.mic.toast)
        #expect(toast.message == "Без доступа к микрофону голос не работает")
        #expect(toast.actionTitle == "Настройки")
        toast.action()
        #expect(h.calls.systemSettings == 1)
        #expect(h.mic.route == nil)
    }

    @Test func theFirstTapAsksForTheMicrophoneAndRecordsOnceAllowed() async throws {
        let h = try MicHarness()
        try await h.open()
        h.recorder.permission = .undetermined

        h.mic.tap()
        await eventually { h.mic.state == .recording }
        #expect(h.recorder.permissionRequests == 1)
        #expect(h.recorder.started.count == 1)
        #expect(h.mic.toast == nil)
    }

    @Test func refusingTheMicrophoneAtTheFirstTapSaysSo() async throws {
        let h = try MicHarness(locale: Locale(identifier: "en"))
        try await h.open()
        h.recorder.permission = .undetermined
        h.recorder.grants = false

        h.mic.tap()
        await eventually { h.mic.toast != nil }
        #expect(h.mic.toast?.message == "Voice needs microphone access")
        #expect(h.mic.toast?.actionTitle == "Settings")
        #expect(h.mic.state == .idle)
        #expect(h.recorder.started.isEmpty)
    }

    @Test func aBusyMicrophoneSaysSo() async throws {
        let h = try MicHarness()
        try await h.open()
        h.recorder.startError = VoiceRecorderError.unavailable

        h.mic.tap()
        #expect(h.mic.state == .idle)
        #expect(h.mic.toast?.message == "Микрофон занят или недоступен")
        #expect(h.mic.toast?.actionTitle == "ОК")
        #expect(h.mic.toast?.length == .short)
    }

    // MARK: Consent

    @Test func withoutConsentTheTapOpensTheConsentScreenAndRecordsAfterAgreeing() async throws {
        let h = try MicHarness()
        try await h.open(consent: false)

        h.mic.tap()
        #expect(h.mic.route == .voiceConsent)
        #expect(h.mic.state == .idle)
        #expect(h.recorder.started.isEmpty)
        #expect(h.recorder.permissionRequests == 0)

        // The shell presents it and clears the request.
        h.mic.route = nil
        h.mic.answerConsent(true)
        #expect(h.app.device.current.voiceConsent)
        #expect(h.mic.state == .recording)
        #expect(h.recorder.started.count == 1)
        // Notes kept while there was no consent can go now.
        await eventually { h.notes.queueRuns == 1 }
    }

    @Test func notNowRecordsNothingAndTheNextTapAsksAgain() async throws {
        let h = try MicHarness()
        try await h.open(consent: false)

        h.mic.tap()
        h.mic.route = nil
        h.mic.answerConsent(false)
        #expect(!h.app.device.current.voiceConsent)
        #expect(h.mic.state == .idle)
        #expect(h.recorder.started.isEmpty)

        h.mic.tap()
        #expect(h.mic.route == .voiceConsent)
        #expect(h.recorder.started.isEmpty)
    }

    /// Agreeing on a consent screen opened from elsewhere (settings) starts nothing.
    @Test func consentWithoutATapOnlyKeepsTheAnswer() async throws {
        let h = try MicHarness()
        try await h.open(consent: false)

        h.mic.answerConsent(true)
        #expect(h.app.device.current.voiceConsent)
        #expect(h.mic.state == .idle)
        #expect(h.recorder.started.isEmpty)
    }

    /// The stub mic of previews keeps the protocol's new duties trivially.
    @Test func theStubMicCarriesNoVoice() {
        let stub = StubMicModel()
        stub.answerConsent(true)
        #expect(stub.toast == nil)
        #expect(stub.route == nil)
    }
}

/// The chimes around a note in the app, as a voice assistant makes them: the rising one is over
/// before the microphone starts, the falling one follows the stop, so neither is in the note.
@MainActor @Suite struct VoiceMicChimeTests {
    @Test func theRisingChimeEndsBeforeTheMicrophoneAndTheFallingOneFollowsTheStop() async throws {
        let h = try MicHarness()
        try await h.open()
        let events = EventLog()
        let cues = FakeCues(events: events)
        let gate = Gate()
        cues.gate = gate
        h.recorder.events = events
        let mic = VoiceMicModel(
            model: h.app.model, recorder: h.recorder, notes: h.notes, locale: Locale(identifier: "ru"),
            levelInterval: .seconds(3_600), cues: cues
        )

        mic.tap()
        await eventually { events.events == ["rising chime"] }
        #expect(mic.state == .idle)
        #expect(h.recorder.started.isEmpty)
        // A tap while it sounds changes nothing: the note is on its way.
        mic.tap()

        await gate.open()
        await eventually { mic.state == .recording }
        #expect(events.events == ["rising chime", "rising chime over", "record"])
        #expect(h.recorder.started.count == 1)

        mic.tap()
        #expect(events.events.suffix(2) == ["stop", "falling chime"])
        #expect(mic.state == .thinking)
        await eventually { h.notes.understood.count == 1 }
    }

    /// A stray tap still ends with the falling chime, as the start had its rising one.
    @Test func aStrayTapEndsWithTheFallingChimeToo() async throws {
        let h = try MicHarness()
        try await h.open()
        let events = EventLog()
        h.recorder.events = events
        h.recorder.keepsNote = false
        let mic = VoiceMicModel(
            model: h.app.model, recorder: h.recorder, notes: h.notes, locale: Locale(identifier: "ru"),
            levelInterval: .seconds(3_600), cues: FakeCues(events: events)
        )
        mic.tap()
        await eventually { mic.state == .recording }
        mic.tap()
        #expect(events.events == ["rising chime", "rising chime over", "record", "stop", "falling chime"])
        #expect(mic.state == .idle)
    }

    /// A note recorded outside the app before the app was ever on screen: its toast is said once the
    /// mic starts. Once the mic follows the service, outcomes reach it by themselves.
    @Test func aNoteFromOutsideIsSaidOnceTheMicStarts() async throws {
        let h = try MicHarness()
        try await h.open()
        h.mic.keepUntilShown(.waiting(.offline))
        #expect(h.mic.toast == nil)

        await h.mic.start()
        #expect(h.mic.toast?.message == "Нет связи — запись разберётся позже")

        h.mic.toast = nil
        h.mic.keepUntilShown(.waiting(.noKey))
        try await Task.sleep(for: .milliseconds(50))
        #expect(h.mic.toast == nil)
    }
}
