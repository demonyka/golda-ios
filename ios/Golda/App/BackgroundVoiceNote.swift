import Foundation
import GoldaCore
import GoldaData
import OSLog

private let log = Logger(subsystem: "com.f4studio.golda", category: "Voice")

/// One Live Activity of a note recorded outside the app. ActivityKit's own is behind it in the app;
/// tests keep the states they are given.
@MainActor
protocol VoiceActivityHandle: AnyObject {
    func update(_ state: VoiceActivityAttributes.ContentState) async
    /// Ends the activity on [state], which stays for [lingering]; nil state ends it at once.
    func end(_ state: VoiceActivityAttributes.ContentState?, lingering: Duration) async
}

/// The Live Activities of notes recorded outside the app.
@MainActor
protocol VoiceActivities: AnyObject {
    /// Whether the person allows them; without one iOS does not record in the background.
    var areAllowed: Bool { get }
    /// Starts an activity on [state]. Throws when the system refuses one.
    func begin(_ state: VoiceActivityAttributes.ContentState) throws -> any VoiceActivityHandle
    /// The activity whose «Отменить» carries [ticket] now says «Отменено» and goes.
    func showUndone(_ ticket: VoiceUndoTicket) async
    /// Ends at once every activity still running that no note of this run began: one left by a
    /// run that died mid-note would otherwise say the microphone is on for hours.
    func endStale()
}

/// The app's own mic, as a note asked for from outside sees it (`VoiceMicModel`).
@MainActor
protocol InAppVoiceMic: AnyObject {
    /// Recording, or about to once the rising chime is over.
    var isListening: Bool { get }
    /// Ends that note as a second tap would.
    func stopListening()
}

extension VoiceMicModel: InAppVoiceMic {}

/// A notification about a note that needs the app; a tap opens it, where the toast or the form waits.
@MainActor
protocol VoiceAlerts: AnyObject {
    func post(_ message: String) async
}

/// A voice note recorded with the app out of sight, the iOS 18 `AudioRecordingIntent` way: the
/// rising chime, the microphone beside a Live Activity, and at «Стоп» (or the minute running out,
/// or a second press) the falling chime and the same voice service as the mic in the app. What the
/// note became is on the Live Activity, with «Отменить» for what it booked, as the toast has.
///
/// Voice notes book at once and are undone, as in the app (SPEC: a record is made by hand or by
/// voice; the voice is the person's own act). What the app confirms with a screen, a purchase to
/// weigh up, stays in the app: the activity and a notification lead there, and the mic's toast or
/// form waits (`VoiceMicModel.keepUntilShown`).
@MainActor
final class BackgroundVoiceNote {
    private let model: AppModel
    private let recorder: any VoiceRecording
    private let notes: any VoiceNotes
    private let cues: any VoiceCues
    private let activities: any VoiceActivities
    private let alerts: any VoiceAlerts
    private let hasKey: @MainActor () -> Bool
    private let locale: Locale
    private let levelInterval: Duration
    /// The app's own mic: a press while it listens out of sight ends its note (`stopInApp`).
    private weak var inAppMic: (any InAppVoiceMic)?
    /// Keeps the app running once the microphone is off, while the note goes to Gemini: the audio
    /// no longer does. Returns what lets it go. iOS may take the time away first; the closure it
    /// is given then runs, before the app is suspended.
    private let keepRunning: @MainActor (_ onExpiry: @escaping @MainActor () async -> Void) -> (@MainActor () -> Void)
    /// Where an outcome goes when the app has never been on screen (`VoiceMicModel.keepUntilShown`).
    private let handOff: @MainActor (VoiceOutcome) -> Void

    private struct Note {
        let activity: any VoiceActivityHandle
        let startedAt: Date
        let profileId: UUID
    }

    /// Listening now.
    private var note: Note?
    /// The chime sounds and the recorder is about to start.
    private var isStarting = false
    /// A second press came during the chime: the recorder does not start, the activity goes.
    private var startCalledOff = false
    private var meter: Task<Void, Never>?

    init(
        model: AppModel, recorder: any VoiceRecording, notes: any VoiceNotes, cues: any VoiceCues,
        activities: any VoiceActivities, alerts: any VoiceAlerts, hasKey: @escaping @MainActor () -> Bool,
        locale: Locale = VoiceMicModel.interfaceLocale, levelInterval: Duration = .milliseconds(100),
        inAppMic: (any InAppVoiceMic)? = nil,
        keepRunning: @escaping @MainActor (_ onExpiry: @escaping @MainActor () async -> Void) -> (@MainActor () -> Void) = { _ in {} },
        handOff: @escaping @MainActor (VoiceOutcome) -> Void = { _ in }
    ) {
        self.model = model
        self.recorder = recorder
        self.notes = notes
        self.cues = cues
        self.activities = activities
        self.alerts = alerts
        self.hasKey = hasKey
        self.locale = locale
        self.levelInterval = levelInterval
        self.inAppMic = inAppMic
        self.keepRunning = keepRunning
        self.handOff = handOff
    }

    var isRecording: Bool { note != nil || isStarting }

    /// Where a note asked for now goes. The books are read first when the app was launched for
    /// this alone, so the open profile and onboarding are known.
    func route(appIsActive: Bool) async -> VoiceNoteRoute {
        if !isRecording, !appIsActive { await model.start() }
        return VoiceNoteRoute.of(VoiceNoteRoute.Conditions(
            appIsActive: appIsActive,
            isRecordingOutside: isRecording,
            isRecordingInApp: inAppMic?.isListening ?? false,
            hasBooks: model.device.onboarded && model.activeProfileId != nil,
            hasConsent: model.hasVoiceConsent,
            hasKey: hasKey(),
            microphone: recorder.permission,
            allowsLiveActivities: activities.areAllowed
        ))
    }

    enum StartError: Error {
        case noProfile
        case busy
    }

    /// Starts listening: the Live Activity first (iOS records in the background only beside one),
    /// then the rising chime, then the microphone. Throws when any of them refuses; nothing is
    /// left running then, and the caller brings the app up instead.
    func start() async throws {
        guard !isRecording else { throw StartError.busy }
        guard let profileId = model.activeProfileId else { throw StartError.noProfile }
        let startedAt = Date()
        let activity = try activities.begin(VoiceActivityContent.listening(since: startedAt))
        isStarting = true
        startCalledOff = false
        defer {
            isStarting = false
            startCalledOff = false
        }
        var started = false
        do {
            try await cues.listen {
                // Pressed again during the chime: nothing is recorded, nothing is sent.
                guard !startCalledOff else { return }
                let file = try notes.newNote(profileId: profileId, recordedAt: model.environment.clock())
                try recorder.start(into: file)
                started = true
            }
        } catch {
            log.error("A note from outside the app could not start: \(String(describing: error))")
            await activity.end(nil, lingering: .zero)
            throw error
        }
        guard started else {
            await activity.end(nil, lingering: .zero)
            return
        }
        note = Note(activity: activity, startedAt: startedAt, profileId: profileId)
        let interval = levelInterval
        meter = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self, self.note != nil else { return }
                self.sampleLevel()
            }
        }
    }

    /// One look at the recorder: the level feeds the silence check, and a recorder that stopped by
    /// itself (the minute ran out, a call came in) ends the note as «Стоп» would.
    func sampleLevel() {
        guard note != nil else { return }
        guard recorder.isRecording else {
            stop()
            return
        }
        _ = recorder.level()
    }

    /// Ends the note: the falling chime, then «Разбираю…», then what it became. Returns the work
    /// that follows the stop, so a test can wait for it; nil when nothing was listening. During
    /// the rising chime the note is called off. With no note of this run at all, «Стоп» came from
    /// an activity a dead run left behind, and such activities go.
    @discardableResult
    func stop() -> Task<Void, Never>? {
        guard let note else {
            if isStarting {
                startCalledOff = true
            } else {
                activities.endStale()
            }
            return nil
        }
        self.note = nil
        meter?.cancel()
        meter = nil
        let file = cues.stop { recorder.stop() }
        return Task { await self.finish(note, file: file) }
    }

    private func finish(_ note: Note, file: URL?) async {
        guard let file else {
            // A stray press or silence: nothing was sent, nothing to show.
            await note.activity.end(nil, lingering: .zero)
            return
        }
        let letGo = keepRunning { [activity = note.activity, alerts, locale] in
            // The app is about to be suspended with the note still at the model: it waits in the
            // queue, and the activity stops saying «Разбираю…» and leads to the app instead.
            let ending = VoiceActivityContent.expired(since: note.startedAt, locale: locale)
            await activity.end(ending.state, lingering: VoiceActivityContent.lingering)
            if let alert = ending.alert { await alerts.post(alert) }
        }
        defer { letGo() }
        await note.activity.update(VoiceActivityContent.thinking(since: note.startedAt))
        let outcome = await notes.understand(note: file)
        handOff(outcome)
        let books: VoiceBooks? = if case .done(let done) = outcome { await model.voiceBooks(profileId: done.profileId) } else { nil }
        let ending = VoiceActivityContent.ending(of: outcome, books: books, since: note.startedAt, locale: locale)
        await note.activity.end(ending.state, lingering: VoiceActivityContent.lingering)
        if let alert = ending.alert { await alerts.post(alert) }
    }

    /// At launch: activities a run that died mid-note left behind go (`VoiceActivities.endStale`).
    func endLeftovers() {
        activities.endStale()
    }

    /// The app's mic listens out of sight and a press came from outside: its note ends.
    func stopInApp() {
        inAppMic?.stopListening()
    }

    /// «Отменить» on the Live Activity: what the note booked goes, from the profile it was booked
    /// into, and the activity says so.
    func undo(_ ticket: VoiceUndoTicket) async {
        await model.undoVoiceNote(profileId: ticket.profileId, operationIds: ticket.operationIds)
        await activities.showUndone(ticket)
    }
}

/// The app's end of the voice intents: the one note recorded outside the app, and where a request
/// goes. Set at launch (`AppLaunch.open`); empty in the unit-test host, where requests stay in the
/// app as before.
@MainActor
final class VoiceNoteLauncher {
    static let shared = VoiceNoteLauncher()

    var background: BackgroundVoiceNote?
    /// Whether the app is on screen; UIKit's answer in the app.
    var appIsActive: @MainActor () -> Bool = { true }

    /// `StartVoiceNoteIntent`: records outside the app when it can, and otherwise brings the app
    /// up ([foreground]) and leaves the request to its mic, as before.
    func start(foreground: () async throws -> Void) async throws {
        let active = appIsActive()
        if let background {
            let route = await background.route(appIsActive: active)
            log.info("A voice note asked for from outside, the app \(active ? "on screen" : "out of sight"): \(String(describing: route))")
            switch route {
            case .stop:
                background.stop()
                return
            case .stopInApp:
                background.stopInApp()
                return
            case .background:
                do {
                    try await background.start()
                    return
                } catch {
                    // The system refused the activity or the microphone: the app records instead.
                    log.error("Recording outside the app failed, the app takes the note: \(String(describing: error))")
                }
            case .inApp:
                break
            }
        }
        if !active { try await foreground() }
        VoiceEntryRequests.shared.post()
    }

    /// «Стоп» on the Live Activity.
    func stop() {
        background?.stop()
    }

    /// The mic in the app was tapped: a note from outside still listening ends instead.
    func stopOutsideNote() -> Bool {
        guard let background, background.isRecording else { return false }
        background.stop()
        return true
    }

    func undo(_ ticket: VoiceUndoTicket) async {
        await background?.undo(ticket)
    }
}
