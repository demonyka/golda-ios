import Foundation
import GoldaCore
import GoldaData
import Synchronization
import Testing

@testable import Golda

/// A microphone the test plays: what the system answers about permission, whether starting fails,
/// the levels heard, and whether the stopped note is kept (a stray tap or silence is not).
@MainActor
final class FakeRecorder: VoiceRecording {
    var permission = MicPermission.granted
    /// What the permission prompt answers.
    var grants = true
    var startError: (any Error)?
    var levels: [Double] = []
    /// False plays a note the recorder judged a stray tap or silence.
    var keepsNote = true
    var isRecording = false
    /// Where the order of starts and stops is written, beside the chimes' (`FakeCues`).
    var events: EventLog?

    private(set) var started: [URL] = []
    private(set) var stops = 0
    private(set) var permissionRequests = 0

    func requestPermission() async -> Bool {
        permissionRequests += 1
        permission = grants ? .granted : .denied
        return grants
    }

    func start(into file: URL) throws {
        if let startError { throw startError }
        started.append(file)
        isRecording = true
        events?.add("record")
    }

    func level() -> Double {
        levels.isEmpty ? 0 : levels.removeFirst()
    }

    func stop() -> URL? {
        stops += 1
        isRecording = false
        events?.add("stop")
        return keepsNote ? started.last : nil
    }
}

/// A voice service the test plays: it names files like the queue, remembers what it was asked,
/// answers each note with `answer` (after `gate`, when set) and sends outcomes to its followers.
final class FakeVoiceNotes: VoiceNotes {
    private struct State {
        var understood: [URL] = []
        var queueRuns = 0
        var answer: VoiceOutcome = .waiting(.offline)
        var gate: Gate?
        var followers: [AsyncStream<VoiceOutcome>.Continuation] = []
    }

    private let state = Mutex(State())
    let folder = FileManager.default.temporaryDirectory.appending(path: "golda-fake-voice-\(UUID().uuidString)")

    var understood: [URL] { state.withLock { $0.understood } }
    var queueRuns: Int { state.withLock { $0.queueRuns } }

    /// What the next notes come to.
    func answer(_ outcome: VoiceOutcome) { state.withLock { $0.answer = outcome } }

    /// Holds every note until the gate opens, so "thinking" can be seen.
    func hold(_ gate: Gate) { state.withLock { $0.gate = gate } }

    func newNote(profileId: UUID, recordedAt: Int64) throws -> URL {
        folder.appending(path: "\(recordedAt).\(profileId.uuidString).wav")
    }

    func understand(note: URL) async -> VoiceOutcome {
        let (outcome, gate) = state.withLock { state in
            state.understood.append(note)
            return (state.answer, state.gate)
        }
        await gate?.wait()
        send(outcome)
        return outcome
    }

    func processWaiting() async {
        state.withLock { $0.queueRuns += 1 }
    }

    func outcomes() -> AsyncStream<VoiceOutcome> {
        AsyncStream { continuation in
            state.withLock { $0.followers.append(continuation) }
        }
    }

    /// An outcome, as if a note (the user's or the queue's) came to it.
    func send(_ outcome: VoiceOutcome) {
        let followers = state.withLock { $0.followers }
        for follower in followers { follower.yield(outcome) }
    }

    var hasFollowers: Bool { state.withLock { !$0.followers.isEmpty } }
}

/// Opens once; everyone waiting goes on then.
actor Gate {
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func open() {
        isOpen = true
        waiting.forEach { $0.resume() }
        waiting.removeAll()
    }
}

/// An app with one profile open, "Личный", with a lari card and a ruble card, a fake microphone
/// and a fake voice service, on the `AppHarness` clock and zone. The mic reads the level only when
/// a test asks (`sampleLevel`), and toasts are in [locale].
@MainActor
final class MicHarness {
    let app: AppHarness
    let recorder = FakeRecorder()
    let notes = FakeVoiceNotes()
    let foregrounds: AsyncStream<Void>
    let foreground: AsyncStream<Void>.Continuation
    let mic: VoiceMicModel
    let calls = Calls()
    private(set) var profileId = UUID()

    /// What the mic asked of UIKit.
    @MainActor final class Calls {
        var systemSettings = 0
        var confirmations = 0
    }

    static let lari = Account.card("Карта ₾", currency: "GEL", sort: 0)
    static let rubles = Account.card("Карта ₽", currency: "RUB", sort: 1)

    init(locale: Locale = Locale(identifier: "ru")) throws {
        app = try AppHarness()
        (foregrounds, foreground) = AsyncStream<Void>.makeStream()
        mic = VoiceMicModel(
            model: app.model, recorder: recorder, notes: notes, locale: locale, levelInterval: .seconds(3_600),
            foregrounds: foregrounds,
            openSystemSettings: { [calls] in calls.systemSettings += 1 },
            confirm: { [calls] in calls.confirmations += 1 }
        )
    }

    /// The profile made and opened; [consent] given or not.
    func open(consent: Bool = true) async throws {
        profileId = try await app.profile("Личный", accounts: [Self.lari, Self.rubles])
        app.onboard(active: profileId)
        await app.model.start()
        _ = try await app.data()
        app.device.update { $0.voiceConsent = consent }
    }
}

extension Account {
    /// The harness's account of this name in [profileId].
    static func named(_ name: String, in profileId: UUID, _ app: AppHarness) async throws -> Account {
        let accounts = try await app.environment.database.read { try $0.accounts(profileId: profileId) }
        return try #require(accounts.first { $0.name == name })
    }
}

/// The order things happened in, as the fakes write it.
@MainActor
final class EventLog {
    private(set) var events: [String] = []

    func add(_ event: String) {
        events.append(event)
    }
}

/// Chimes that sound nowhere: they write when they play into [events], and the rising one holds
/// the start until [gate] opens, when one is set, so a test can tap in the middle of it.
@MainActor
final class FakeCues: VoiceCues {
    let events: EventLog
    var gate: Gate?

    init(events: EventLog) {
        self.events = events
    }

    func listen(then start: () throws -> Void) async rethrows {
        events.add("rising chime")
        await gate?.wait()
        await Task.yield()
        events.add("rising chime over")
        try start()
    }

    func stop(_ stop: () -> URL?) -> URL? {
        let file = stop()
        events.add("falling chime")
        return file
    }
}

/// Live Activities kept as the states they were given.
@MainActor
final class FakeActivities: VoiceActivities {
    typealias State = VoiceActivityAttributes.ContentState

    final class Handle: VoiceActivityHandle {
        private(set) var states: [State]
        /// The last state and how long it stays, once ended; `.some(nil)` ended at once.
        private(set) var ending: (state: State?, lingering: Duration)?
        let events: EventLog?

        init(_ state: State, events: EventLog?) {
            states = [state]
            self.events = events
        }

        func update(_ state: State) async {
            states.append(state)
        }

        func end(_ state: State?, lingering: Duration) async {
            ending = (state, lingering)
            events?.add("activity ended")
        }
    }

    var areAllowed = true
    var refuses = false
    var events: EventLog?
    private(set) var started: [Handle] = []
    private(set) var undone: [VoiceUndoTicket] = []

    func begin(_ state: State) throws -> any VoiceActivityHandle {
        if refuses { throw VoiceRecorderError.unavailable }
        events?.add("activity")
        let handle = Handle(state, events: events)
        started.append(handle)
        return handle
    }

    func showUndone(_ ticket: VoiceUndoTicket) async {
        undone.append(ticket)
    }
}

/// Notifications kept as their words.
@MainActor
final class FakeAlerts: VoiceAlerts {
    private(set) var posted: [String] = []

    func post(_ message: String) async {
        posted.append(message)
    }
}
