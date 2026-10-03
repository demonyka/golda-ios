import Foundation
import GoldaCore
import Synchronization
import Testing

@testable import GoldaData

/// A folder of its own for each test, removed with the fixture.
final class TemporaryFolder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: "golda-voice-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    /// A file named [name] holding [bytes].
    func file(_ name: String, _ bytes: [UInt8] = [0x52, 0x49, 0x46, 0x46]) throws -> URL {
        let file = url.appending(path: name)
        try Data(bytes).write(to: file)
        return file
    }
}

/// Sets when a file was last written, epoch milliseconds.
func setModified(_ file: URL, _ epochMillis: Int64) throws {
    let date = Date(timeIntervalSince1970: Double(epochMillis) / 1000)
    try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path(percentEncoded: false))
}

/// A provider that answers from a closure the test can swap, and remembers what it was asked.
final class StubVoiceProvider: VoiceProvider {
    typealias Answer = @Sendable (URL) async throws -> VoiceResult

    struct Call: Equatable, Sendable {
        var audio: URL
        var system: String
        var model: String
    }

    private let state: Mutex<(answer: Answer, calls: [Call])>

    init(_ answer: @escaping Answer = { _ in VoiceResult(transcript: "", items: []) }) {
        state = Mutex((answer, []))
    }

    func answer(_ answer: @escaping Answer) {
        state.withLock { $0.answer = answer }
    }

    func answer(_ result: VoiceResult) {
        answer { _ in result }
    }

    func fail(_ error: any Error) {
        answer { _ in throw error }
    }

    var calls: [Call] { state.withLock { $0.calls } }

    func parse(audio: URL, system: String, model: String) async throws -> VoiceResult {
        let answer = state.withLock { state in
            state.calls.append(Call(audio: audio, system: system, model: model))
            return state.answer
        }
        return try await answer(audio)
    }
}

/// The voice service over a `RepositoryHarness` (in-memory database, UTC, the clock at
/// 2026-10-02 10:00), a queue in a temporary folder and a stub provider. Consent is given and a
/// key is stored unless a test says otherwise.
final class VoiceHarness {
    let base: RepositoryHarness
    let folder: TemporaryFolder
    let queue: VoiceQueue
    let provider = StubVoiceProvider()
    let service: VoiceService

    var repository: Repository { base.repository }
    var device: DeviceSettingsStore { base.device }
    var now: Int64 { base.clock.now }

    init(consent: Bool = true, key: String? = "AIza-test", unnamedPurchase: String = "") throws {
        base = try RepositoryHarness()
        folder = try TemporaryFolder()
        queue = VoiceQueue(directory: folder.url.appending(path: "voice", directoryHint: .isDirectory))
        base.device.update { $0.voiceConsent = consent }
        if let key { try base.secrets.write(key, for: SecretKey.gemini) }
        let clock = base.clock
        service = VoiceService(
            repository: base.repository, provider: provider, secrets: base.secrets, deviceSettings: base.device, queue: queue,
            unnamedPurchase: unnamedPurchase, clock: { clock.now }, zone: { RepositoryHarness.utc }
        )
    }

    /// A note recorded at [recordedAt] while [profileId] was active, last written at [writtenAt]
    /// (by default when it was recorded, long enough ago for the queue to take it).
    func note(_ profileId: UUID, recordedAt: Int64, writtenAt: Int64? = nil) throws -> URL {
        let file = try queue.newFile(profileId: profileId, recordedAt: recordedAt)
        try Data([0x52, 0x49, 0x46, 0x46]).write(to: file)
        try setModified(file, writtenAt ?? recordedAt)
        return file
    }

    func exists(_ file: URL) -> Bool {
        FileManager.default.fileExists(atPath: file.path(percentEncoded: false))
    }

    func operations(_ profileId: UUID) async throws -> [OperationFull] {
        try await base.database.read { try $0.operations(profileId: profileId) }
    }
}

/// How many calls are inside at once, and the most there ever were.
final class Gauge: Sendable {
    private let state = Mutex((inside: 0, peak: 0, events: [String]()))

    func enter(_ name: String) {
        state.withLock {
            $0.inside += 1
            $0.peak = max($0.peak, $0.inside)
            $0.events.append("start \(name)")
        }
    }

    func leave(_ name: String) {
        state.withLock {
            $0.inside -= 1
            $0.events.append("end \(name)")
        }
    }

    var peak: Int { state.withLock { $0.peak } }
    var events: [String] { state.withLock { $0.events } }
}

extension VoiceOutcome {
    /// The `.done` payload, or nil.
    var done: Done? {
        if case .done(let done) = self { done } else { nil }
    }
}
