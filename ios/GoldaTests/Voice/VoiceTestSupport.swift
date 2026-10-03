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
    }

    func level() -> Double {
        levels.isEmpty ? 0 : levels.removeFirst()
    }

    func stop() -> URL? {
        stops += 1
        isRecording = false
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

    func understand(note: URL) async {
        let (outcome, gate) = state.withLock { state in
            state.understood.append(note)
            return (state.answer, state.gate)
        }
        await gate?.wait()
        send(outcome)
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
