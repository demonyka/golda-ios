import Foundation
import GoldaCore
import GoldaData
import Testing

@testable import Golda

/// A voice note recorded with the app out of sight: the Live Activity, the chimes around the
/// microphone, the same voice service as the mic, and what the note became on the activity.
@MainActor @Suite struct BackgroundVoiceNoteTests {
    /// The mic's harness, and beside it a note from outside with its own fake microphone, chimes,
    /// Live Activities and notifications, all writing into one log.
    @MainActor final class Harness {
        let mic: MicHarness
        let events = EventLog()
        let recorder = FakeRecorder()
        let activities = FakeActivities()
        let alerts = FakeAlerts()
        let cues: FakeCues
        var hasKey = true
        private(set) var handedOff: [VoiceOutcome] = []
        private(set) var keptRunning = 0
        private(set) var letGo = 0
        /// What the note does when iOS takes its background time away.
        private(set) var expiry: (@MainActor () async -> Void)?
        var note: BackgroundVoiceNote!

        init() throws {
            mic = try MicHarness()
            cues = FakeCues(events: events)
            recorder.events = events
            activities.events = events
            note = BackgroundVoiceNote(
                model: mic.app.model, recorder: recorder, notes: mic.notes, cues: cues, activities: activities, alerts: alerts,
                // Weak: a note's work may outlive the test that started it.
                hasKey: { [weak self] in self?.hasKey ?? false }, locale: Locale(identifier: "ru"), levelInterval: .seconds(3_600),
                inAppMic: mic.mic,
                keepRunning: { [weak self] onExpiry in
                    self?.expiry = onExpiry
                    self?.keptRunning += 1
                    return { self?.letGo += 1 }
                },
                handOff: { [weak self] in self?.handedOff.append($0) }
            )
        }

        func open(consent: Bool = true) async throws {
            try await mic.open(consent: consent)
        }

        var activity: FakeActivities.Handle? { activities.started.last }
    }

    // MARK: Where a note goes

    @Test func withEverythingInPlaceANoteFromOutsideStaysOutside() async throws {
        let h = try Harness()
        try await h.open()
        #expect(await h.note.route(appIsActive: false) == .background)
        #expect(await h.note.route(appIsActive: true) == .inApp)
    }

    /// The first note's screens are the app's: no consent, no key, no microphone yet, no Live
    /// Activities allowed.
    @Test func whatTheNoteStillNeedsBringsTheAppUp() async throws {
        let h = try Harness()
        try await h.open(consent: false)
        #expect(await h.note.route(appIsActive: false) == .inApp)
        h.mic.app.device.update { $0.voiceConsent = true }
        #expect(await h.note.route(appIsActive: false) == .background)

        h.hasKey = false
        #expect(await h.note.route(appIsActive: false) == .inApp)
        h.hasKey = true
        h.recorder.permission = .undetermined
        #expect(await h.note.route(appIsActive: false) == .inApp)
        h.recorder.permission = .granted
        h.activities.areAllowed = false
        #expect(await h.note.route(appIsActive: false) == .inApp)
    }

    // MARK: The note

    /// The activity first (iOS records in the background only beside one), then the rising chime,
    /// and only once it is over the microphone, so the note does not carry it. «Стоп»: the
    /// microphone off, then the falling chime, «Разбираю…», and what the note booked with «Отменить».
    @Test func aNoteRunsFromTheChimeToWhatItBooked() async throws {
        let h = try Harness()
        try await h.open()
        let lari = try await Account.named("Карта ₾", in: h.mic.profileId, h.mic.app)
        let draft = Draft(type: .expense, timestamp: AppHarness.now, accountId: lari.id, amountMinor: 1_500, categoryKey: "eating_out", note: "Шаурма")
        let id = try await h.mic.app.repository.save(draft, profileId: h.mic.profileId)
        let done = VoiceOutcome.Done(
            profileId: h.mic.profileId, transcript: "Шаурма 15 лари", recorded: [VoiceOutcome.Recorded(operationId: id, draft: draft)],
            considering: [], misunderstood: false, late: false, impact: nil
        )
        h.mic.notes.answer(.done(done))

        try await h.note.start()
        #expect(h.events.events == ["activity", "rising chime", "rising chime over", "record"])
        #expect(h.note.isRecording)
        let activity = try #require(h.activity)
        #expect(activity.states.map(\.phase) == [.listening])
        // Named for the moment and the profile open then, as the queue reads it back.
        let file = try #require(h.recorder.started.first)
        #expect(file.lastPathComponent == "\(AppHarness.now).\(h.mic.profileId.uuidString).wav")

        let work = try #require(h.note.stop())
        #expect(!h.note.isRecording)
        await work.value
        #expect(h.events.events.suffix(3) == ["stop", "falling chime", "activity ended"])
        #expect(h.mic.notes.understood == [file])
        #expect(activity.states.map(\.phase) == [.listening, .thinking])
        let ending = try #require(activity.ending)
        let state = try #require(ending.state)
        #expect(state.phase == .recorded)
        #expect(state.headline == "Шаурма 15 ₾")
        #expect(state.undo == VoiceUndoTicket(profileId: h.mic.profileId, operationIds: [id]))
        #expect(ending.lingering == VoiceActivityContent.lingering)
        // Booked and undoable right there: no notification.
        #expect(h.alerts.posted.isEmpty)
        // The app hears it too, should it never have been on screen.
        #expect(h.handedOff == [.done(done)])
        // Kept running only while the note went to the model.
        #expect(h.keptRunning == 1 && h.letGo == 1)

        // «Отменить» on the activity.
        await h.note.undo(try #require(state.undo))
        let profileId = h.mic.profileId
        await eventuallyAsync { try await h.mic.app.environment.database.read { try $0.operation(id, profileId: profileId) } == nil }
        #expect(h.activities.undone == [VoiceUndoTicket(profileId: profileId, operationIds: [id])])
    }

    /// A purchase to weigh up waits in the app's form: the activity and a notification lead there.
    @Test func aPurchaseToWeighUpLeavesANotification() async throws {
        let h = try Harness()
        try await h.open()
        let headphones = Consider(title: "Наушники", amountMinor: 12_000, currency: "USD")
        h.mic.notes.answer(.done(VoiceOutcome.Done(
            profileId: h.mic.profileId, transcript: "Хочу купить наушники", recorded: [], considering: [headphones],
            misunderstood: false, late: false, impact: nil
        )))

        try await h.note.start()
        await h.note.stop()?.value
        #expect(h.activity?.ending?.state?.phase == .needsApp)
        #expect(h.alerts.posted == ["Сомневаюсь: Наушники 120 $. Реши в Golda"])
    }

    /// A stray press or silence: the recorder keeps nothing, nothing is sent, the activity goes.
    @Test func aStrayPressSendsNothing() async throws {
        let h = try Harness()
        try await h.open()
        h.recorder.keepsNote = false

        try await h.note.start()
        await h.note.stop()?.value
        #expect(h.mic.notes.understood.isEmpty)
        let ending = try #require(h.activity?.ending)
        #expect(ending.state == nil)
        #expect(h.events.events.suffix(3) == ["stop", "falling chime", "activity ended"])
    }

    @Test func theMinuteRunningOutEndsTheNoteAsStopWould() async throws {
        let h = try Harness()
        try await h.open()
        try await h.note.start()
        h.recorder.isRecording = false

        h.note.sampleLevel()
        #expect(h.recorder.stops == 1)
        await eventually { h.mic.notes.understood.count == 1 }
    }

    /// A microphone that will not start ends the activity at once and lets the caller bring the app
    /// up; so does a refused activity, before any chime.
    @Test func aRefusalLeavesNothingRunning() async throws {
        let h = try Harness()
        try await h.open()
        h.recorder.startError = VoiceRecorderError.unavailable
        await #expect(throws: VoiceRecorderError.self) { try await h.note.start() }
        #expect(!h.note.isRecording)
        #expect(h.activity?.ending?.state == nil && h.activity?.ending != nil)

        h.recorder.startError = nil
        h.activities.refuses = true
        h.events.add("—")
        await #expect(throws: VoiceRecorderError.self) { try await h.note.start() }
        #expect(h.events.events.last == "—")
        #expect(!h.note.isRecording)
    }

    /// The mic in the app, tapped while a note from outside listens, ends that note instead of
    /// starting a second recorder beside it.
    @Test func theAppsMicEndsANoteFromOutside() async throws {
        let h = try Harness()
        try await h.open()
        try await h.note.start()
        let launcher = VoiceNoteLauncher()
        launcher.background = h.note
        let mic = VoiceMicModel(
            model: h.mic.app.model, recorder: h.mic.recorder, notes: h.mic.notes, locale: Locale(identifier: "ru"),
            levelInterval: .seconds(3_600), stopsOutsideNote: { launcher.stopOutsideNote() }
        )

        mic.tap()
        #expect(!h.note.isRecording)
        #expect(h.recorder.stops == 1)
        #expect(h.mic.recorder.started.isEmpty)
        #expect(mic.state == .idle)
    }

    // MARK: A press at an awkward moment

    /// A second press while the rising chime still sounds: the note is called off before the
    /// microphone opens, rather than recorded for a whole minute and booked.
    @Test func aPressDuringTheChimeCallsTheNoteOff() async throws {
        let h = try Harness()
        try await h.open()
        let gate = Gate()
        h.cues.gate = gate
        let starting = Task { try await h.note.start() }
        await eventually { h.events.events.contains("rising chime") }
        #expect(h.note.isRecording)
        #expect(await h.note.route(appIsActive: false) == .stop)

        #expect(h.note.stop() == nil)
        await gate.open()
        try await starting.value
        #expect(!h.note.isRecording)
        #expect(h.recorder.started.isEmpty)
        let ending = try #require(h.activity?.ending)
        #expect(ending.state == nil)
        #expect(h.mic.notes.understood.isEmpty)
    }

    /// The app's mic still listening after the person went home: a press outside ends that note,
    /// as a second tap would, instead of a second recorder booking the same purchase again.
    @Test func aPressWhileTheAppsMicListensOutOfSightEndsThatNote() async throws {
        let h = try Harness()
        try await h.open()
        h.mic.mic.tap()
        #expect(h.mic.mic.state == .recording)
        #expect(await h.note.route(appIsActive: false) == .stopInApp)

        let launcher = VoiceNoteLauncher()
        launcher.background = h.note
        launcher.appIsActive = { false }
        var broughtUp = false
        try await launcher.start { broughtUp = true }
        #expect(h.mic.mic.state != .recording)
        #expect(h.mic.recorder.stops == 1)
        #expect(h.recorder.started.isEmpty && h.activities.started.isEmpty)
        #expect(!broughtUp)
        await eventually { h.mic.notes.understood.count == 1 }
    }

    /// The app's mic pressed off during its own rising chime opens no microphone at all.
    @Test func theAppsMicStoppedDuringItsChimeRecordsNothing() async throws {
        let h = try Harness()
        try await h.open()
        let gate = Gate()
        let cues = FakeCues(events: EventLog())
        cues.gate = gate
        let mic = VoiceMicModel(
            model: h.mic.app.model, recorder: h.mic.recorder, notes: h.mic.notes, locale: Locale(identifier: "ru"),
            levelInterval: .seconds(3_600), cues: cues
        )
        mic.tap()
        await eventually { cues.events.events.contains("rising chime") }
        #expect(mic.isListening)

        mic.stopListening()
        await gate.open()
        await eventually { !mic.isListening }
        #expect(h.mic.recorder.started.isEmpty)
        #expect(mic.state == .idle)
    }

    // MARK: When the process cannot finish

    /// iOS takes the background time away while the note is worked out: the activity stops
    /// saying «Разбираю…» and leads to the app, where the note waits, before the app is suspended.
    @Test func runningOutOfBackgroundTimeLeadsToTheApp() async throws {
        let h = try Harness()
        try await h.open()
        let gate = Gate()
        h.mic.notes.hold(gate)
        try await h.note.start()
        let work = try #require(h.note.stop())
        await eventually { h.activity?.states.last?.phase == .thinking }

        let expire = try #require(h.expiry)
        await expire()
        let state = try #require(h.activity?.ending?.state)
        #expect(state.phase == .needsApp)
        #expect(state.headline == "Открой Golda, чтобы закончить запись")
        #expect(h.alerts.posted == ["Открой Golda, чтобы закончить запись"])

        await gate.open()
        await work.value
    }

    /// A run that died mid-note left its activity saying the microphone is on. The next launch
    /// ends it, and so does its «Стоп», which finds no note of this run to stop.
    @Test func anActivityNoNoteOwnsIsEnded() async throws {
        let h = try Harness()
        try await h.open()
        h.note.endLeftovers()
        #expect(h.activities.staleEnds == 1)

        #expect(h.note.stop() == nil)
        #expect(h.activities.staleEnds == 2)

        // A note of this run is stopped as usual; nothing else is swept.
        try await h.note.start()
        await h.note.stop()?.value
        #expect(h.activities.staleEnds == 2)
    }
}
