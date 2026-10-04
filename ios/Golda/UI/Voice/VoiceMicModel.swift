import Foundation
import GoldaCore
import GoldaData
import Observation
import UIKit

/// The mic of the app, the port of Android's `rememberVoice`: tap to talk, tap again when done.
///
/// idle → recording → thinking → idle. Nothing is recorded, let alone sent, before the person has
/// agreed on the consent screen (App Review 5.1.2(i)): the first tap opens that screen, and the
/// recording starts once they agree. A note goes into the profile open at the moment of recording.
///
/// Every outcome of the voice service, those of notes understood later from the queue included,
/// becomes a toast or a screen for the whole life of the app: "Шаурма 15 ₾" with "Отменить", the
/// operation form for "хочу купить", why a note waits. The queue runs at launch, when the app comes
/// back to the foreground, after consent, and when the key changes (`AppModel.processVoiceQueue`).
@MainActor @Observable
final class VoiceMicModel: MicModel {
    private(set) var state = MicState.idle
    private(set) var level = 0.0
    var toast: UndoToast?
    var route: AppRoute?

    @ObservationIgnored private let model: AppModel
    @ObservationIgnored private let recorder: any VoiceRecording
    @ObservationIgnored private let notes: any VoiceNotes
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private let levelInterval: Duration
    @ObservationIgnored private let foregrounds: AsyncStream<Void>?
    @ObservationIgnored private let openSystemSettings: @MainActor () -> Void
    @ObservationIgnored private let confirm: @MainActor () -> Void
    /// The chimes around a note; nil plays none and starts the recorder at once, as the tests that
    /// drive the mic step by step need.
    @ObservationIgnored private let cues: (any VoiceCues)?
    /// Ends a note recorded outside the app (`BackgroundVoiceNote`), if one is being recorded: a tap
    /// on the mic then stops that one instead of starting a second recorder beside it.
    @ObservationIgnored private let stopsOutsideNote: @MainActor () -> Bool
    /// Debug stub only: agree at launch, and leave a note in the queue before it first runs.
    @ObservationIgnored private let grantsConsentAtStart: Bool
    @ObservationIgnored private let beforeFirstQueueRun: (@MainActor () -> Void)?

    /// A tap that met the consent screen: recording starts once the person agrees.
    @ObservationIgnored private var startAfterConsent = false
    /// The rising chime sounds; the recorder starts when it is over.
    @ObservationIgnored private var isStarting = false
    /// Outcomes of notes recorded outside the app before this mic followed the service: they are
    /// said once the app is on screen.
    @ObservationIgnored private var keptOutcomes: [VoiceOutcome] = []
    /// "Не сейчас" this run: a waiting note does not ask again until the next launch.
    @ObservationIgnored private var consentDeclined = false
    @ObservationIgnored private var meter: Task<Void, Never>?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var started = false

    /// [locale] is the language of the toasts; [levelInterval] how often the level is read while
    /// recording; [foregrounds] ticks each time the app comes back. [openSystemSettings] and
    /// [confirm] (the success haptic) are UIKit's unless a test passes its own; [cues] play the
    /// chimes, [stopsOutsideNote] ends a note recorded from the Lock Screen.
    init(
        model: AppModel,
        recorder: any VoiceRecording,
        notes: any VoiceNotes,
        locale: Locale = VoiceMicModel.interfaceLocale,
        levelInterval: Duration = .milliseconds(50),
        foregrounds: AsyncStream<Void>? = nil,
        openSystemSettings: @escaping @MainActor () -> Void = VoiceMicModel.openAppSettings,
        confirm: @escaping @MainActor () -> Void = { UINotificationFeedbackGenerator().notificationOccurred(.success) },
        cues: (any VoiceCues)? = nil,
        stopsOutsideNote: @escaping @MainActor () -> Bool = { false },
        grantsConsentAtStart: Bool = false,
        beforeFirstQueueRun: (@MainActor () -> Void)? = nil
    ) {
        self.model = model
        self.recorder = recorder
        self.notes = notes
        self.locale = locale
        self.levelInterval = levelInterval
        self.foregrounds = foregrounds
        self.openSystemSettings = openSystemSettings
        self.confirm = confirm
        self.cues = cues
        self.stopsOutsideNote = stopsOutsideNote
        self.grantsConsentAtStart = grantsConsentAtStart
        self.beforeFirstQueueRun = beforeFirstQueueRun
    }

    isolated deinit {
        tasks.forEach { $0.cancel() }
        meter?.cancel()
    }

    /// The app's mic: the microphone and the environment's voice service, or, in a debug build
    /// launched with `-golda.voiceStub=<script>`, the stub recorder (the stub provider is already
    /// in the environment, see `AppEnvironment.make`).
    static func live(model: AppModel) -> VoiceMicModel {
        let environment = model.environment
        #if DEBUG
        if let stub = VoiceStubOptions.current {
            var leaveNote: (@MainActor () -> Void)?
            if stub.script == .late {
                leaveNote = { [weak model] in
                    guard let profileId = model?.activeProfileId else { return }
                    try? StubWAV.leaveNote(in: environment.voiceQueue, profileId: profileId, now: environment.clock())
                }
            }
            return VoiceMicModel(
                model: model, recorder: StubVoiceRecorder(), notes: environment.voice, foregrounds: foregroundSignals(),
                cues: LiveVoiceCues.shared, stopsOutsideNote: { VoiceNoteLauncher.shared.stopOutsideNote() },
                grantsConsentAtStart: stub.grantsConsent, beforeFirstQueueRun: leaveNote
            )
        }
        #endif
        return VoiceMicModel(
            model: model, recorder: LiveVoiceRecorder(), notes: environment.voice, foregrounds: foregroundSignals(),
            cues: LiveVoiceCues.shared, stopsOutsideNote: { VoiceNoteLauncher.shared.stopOutsideNote() }
        )
    }

    // MARK: Launch

    /// Follows the outcomes from now on, then works through the notes that waited. Call once, after
    /// the launch command, which wipes this phone's settings along with the books.
    func start() async {
        guard !started else { return }
        started = true
        if grantsConsentAtStart { model.setVoiceConsent(true) }
        let outcomes = notes.outcomes()
        tasks.append(Task { [weak self] in
            for await outcome in outcomes {
                await self?.react(to: outcome)
            }
        })
        if let foregrounds {
            tasks.append(Task { [weak self, notes] in
                for await _ in foregrounds {
                    guard self != nil else { return }
                    await notes.processWaiting()
                }
            })
        }
        let kept = keptOutcomes
        keptOutcomes.removeAll()
        for outcome in kept { await react(to: outcome) }
        beforeFirstQueueRun?()
        await notes.processWaiting()
    }

    /// A note recorded outside the app came to [outcome] before the app was ever on screen, so
    /// nothing followed the service yet: it is said once the mic starts, as a toast or the form,
    /// like any other. Once the mic follows the service, the outcome reaches it by itself.
    func keepUntilShown(_ outcome: VoiceOutcome) {
        guard !started else { return }
        keptOutcomes.append(outcome)
    }

    // MARK: The tap

    func tap() {
        switch state {
        case .idle:
            // A note from the Lock Screen still listening: this tap ends it, as a second tap would.
            if stopsOutsideNote() { return }
            begin()
        case .recording: finish()
        case .thinking: break
        }
    }

    func answerConsent(_ agreed: Bool) {
        let wanted = startAfterConsent
        startAfterConsent = false
        guard agreed else {
            consentDeclined = true
            return
        }
        consentDeclined = false
        model.setVoiceConsent(true)
        if wanted { begin() }
        // Notes kept while there was no consent can go now.
        Task { [notes] in await notes.processWaiting() }
    }

    private func begin() {
        guard model.hasVoiceConsent else {
            startAfterConsent = true
            request(.voiceConsent)
            return
        }
        switch recorder.permission {
        case .granted:
            startRecording()
        case .denied:
            show(.micDenied(locale: locale))
        case .undetermined:
            Task { [weak self] in
                guard let self else { return }
                if await self.recorder.requestPermission() {
                    self.startRecording()
                } else {
                    self.show(.micDenied(locale: self.locale))
                }
            }
        }
    }

    private func startRecording() {
        guard state == .idle, !isStarting, let profileId = model.activeProfileId else { return }
        guard let cues else {
            record(into: profileId)
            return
        }
        // The rising chime first, so the note does not carry it; taps meanwhile change nothing.
        isStarting = true
        Task { [weak self] in
            await cues.listen { self?.record(into: profileId) }
            self?.isStarting = false
        }
    }

    private func record(into profileId: UUID) {
        guard state == .idle else { return }
        do {
            let file = try notes.newNote(profileId: profileId, recordedAt: model.environment.clock())
            try recorder.start(into: file)
        } catch {
            show(.micBusy(locale: locale))
            return
        }
        state = .recording
        let interval = levelInterval
        meter = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self, self.state == .recording else { return }
                self.sampleLevel()
            }
        }
    }

    /// One look at the level for the waveform. A recorder that stopped by itself (the minute ran
    /// out, a call came in) ends the note as a tap would.
    func sampleLevel() {
        guard state == .recording else { return }
        guard recorder.isRecording else {
            finish()
            return
        }
        level = recorder.level()
    }

    private func finish() {
        meter?.cancel()
        meter = nil
        level = 0
        // The falling chime after the recorder stops, so the note does not carry it either.
        let stopped: URL? = if let cues { cues.stop { recorder.stop() } } else { recorder.stop() }
        guard let file = stopped else {
            // A stray tap or silence: nothing to send.
            state = .idle
            return
        }
        state = .thinking
        Task { [weak self, notes] in
            await notes.understand(note: file)
            self?.state = .idle
        }
    }

    // MARK: Outcomes

    /// What the person hears of [outcome]: Android's collector of `repo.voice`.
    func react(to outcome: VoiceOutcome) async {
        switch outcome {
        case .done(let done):
            if let consider = done.considering.first {
                // The purchase is weighed up in the profile the note was recorded in.
                if done.profileId != model.activeProfileId { model.switchProfile(to: done.profileId) }
                request(.entry(EntryRequest(consider: consider)))
            }
            if !done.recorded.isEmpty {
                confirm()
                let books = await model.voiceBooks(profileId: done.profileId)
                show(.recorded(done, books: books, locale: locale))
            } else if let notice = VoiceNotice.of(outcome, books: nil, locale: locale) {
                show(notice)
            }
        case .needsConsent:
            if !consentDeclined { request(.voiceConsent) }
        case .waiting, .failed:
            if let notice = VoiceNotice.of(outcome, books: nil, locale: locale) { show(notice) }
        }
    }

    private func show(_ notice: VoiceNotice) {
        toast = UndoToast(notice.message, actionTitle: notice.actionTitle(in: locale), length: notice.length) { [weak self] in
            self?.perform(notice.action)
        }
    }

    private func perform(_ action: VoiceNotice.Action) {
        switch action {
        case .undo(let done): Task { [model] in await model.undoVoiceNote(done) }
        case .openSettings: request(.settings)
        case .addByHand: request(.entry(EntryRequest()))
        case .openSystemSettings: openSystemSettings()
        case .dismiss: break
        }
    }

    /// The shell presents it as soon as nothing else is open (`MicPlacement`).
    private func request(_ route: AppRoute) {
        self.route = route
    }

    // MARK: The system

    /// The language the app's strings resolved to, so the toasts match the rest of the screen.
    static var interfaceLocale: Locale {
        Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
    }

    /// The system's settings page of the app, where the microphone is allowed.
    static func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Ticks each time the app comes back from the background; the launch itself does not tick.
    static func foregroundSignals() -> AsyncStream<Void> {
        AsyncStream { continuation in
            // The observer lives as long as the stream; the token is only handed back to the center.
            nonisolated(unsafe) let observer = NotificationCenter.default.addObserver(
                forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil
            ) { _ in continuation.yield() }
            continuation.onTermination = { _ in NotificationCenter.default.removeObserver(observer) }
        }
    }
}
