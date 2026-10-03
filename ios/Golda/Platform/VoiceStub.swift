#if DEBUG
import Foundation
import GoldaCore
import GoldaData

/// `-golda.voiceStub=<script>`: the whole voice flow without a microphone or a network, for UI tests
/// and screenshots. The recorder writes a short silent WAV, the provider answers with the script's
/// fixed `VoiceResult` after a pause (so "Разбираю…" can be seen), the service gets a key of its
/// own, and consent is granted at launch unless `-golda.voiceStub.noConsent` is given too. Debug
/// builds only: a release build has neither the arguments nor this file.
struct VoiceStubOptions: Equatable, Sendable {
    var script: VoiceStubScript
    var grantsConsent: Bool

    static var current: VoiceStubOptions? {
        VoiceStubOptions(arguments: ProcessInfo.processInfo.arguments)
    }

    static let prefix = "-golda.voiceStub="
    static let noConsentFlag = "-golda.voiceStub.noConsent"

    /// Nil without the argument or with a script it does not know.
    init?(arguments: [String]) {
        guard let argument = arguments.first(where: { $0.hasPrefix(Self.prefix) }),
              let script = VoiceStubScript(rawValue: String(argument.dropFirst(Self.prefix.count)))
        else { return nil }
        self.script = script
        grantsConsent = !arguments.contains(Self.noConsentFlag)
    }

    var provider: any VoiceProvider { CannedVoiceProvider(script: script) }

    /// The service's own key store, holding a made-up key: the real one is never written to.
    var secrets: any SecretStore { InMemorySecretStore([SecretKey.gemini: "stub-key"]) }
}

/// What the stub provider says, by the name after `-golda.voiceStub=`.
enum VoiceStubScript: String, CaseIterable, Sendable {
    /// "Шаурма 15 лари": one expense of 15 GEL.
    case shawarma
    /// "Шаурма 15 лари и кофе 8": two expenses.
    case two
    /// "Хочу купить наушники за 120 долларов": a purchase to weigh up.
    case consider
    /// Words that are not about money.
    case unclear
    /// No connection: the note waits.
    case offline
    /// The provider finds no key: the note waits for one.
    case noKey = "nokey"
    /// As `shawarma`, and a note recorded a minute before launch waits in the queue, so the first
    /// run of the queue books it "from a saved note".
    case late

    /// What the model "heard".
    var result: VoiceResult {
        switch self {
        case .shawarma, .late, .offline, .noKey:
            VoiceResult(transcript: "Шаурма 15 лари", items: [
                VoiceItem(intent: "expense", amount: "15", currency: "GEL", note: "шаурма", category: "eating_out"),
            ])
        case .two:
            VoiceResult(transcript: "Шаурма 15 лари и кофе 8", items: [
                VoiceItem(intent: "expense", amount: "15", currency: "GEL", note: "шаурма", category: "eating_out"),
                VoiceItem(intent: "expense", amount: "8", currency: "GEL", note: "кофе", category: "eating_out"),
            ])
        case .consider:
            VoiceResult(transcript: "Хочу купить наушники за 120 долларов", items: [
                VoiceItem(intent: "consider", amount: "120", currency: "USD", note: "наушники"),
            ])
        case .unclear:
            VoiceResult(transcript: "Ну это самое, как его", items: [VoiceItem(intent: "unknown")])
        }
    }
}

/// Answers every note with the script's result, after [delay]: long enough for a UI test or a
/// screenshot to catch "Разбираю…" between two taps.
struct CannedVoiceProvider: VoiceProvider {
    var script: VoiceStubScript
    var delay: Duration = .seconds(3)

    func parse(audio: URL, system: String, model: String) async throws -> VoiceResult {
        try? await Task.sleep(for: delay)
        switch script {
        case .offline: throw VoiceProviderError.offline(message: "the stub is offline")
        case .noKey: throw VoiceProviderError.noKey
        default: return script.result
        }
    }
}

/// Records nothing: the microphone is always allowed, the level murmurs, and a stopped note is a
/// short silent WAV. The file is written only at the stop, so the queue never sees a note that is
/// still being "recorded".
@MainActor
final class StubVoiceRecorder: VoiceRecording {
    private var file: URL?
    private var startedAt = Date.distantPast

    var permission: MicPermission { .granted }

    func requestPermission() async -> Bool { true }

    func start(into file: URL) throws {
        self.file = file
        startedAt = Date()
    }

    var isRecording: Bool { file != nil }

    func level() -> Double {
        guard file != nil else { return 0 }
        // Speech-like: rises and falls a few times a second.
        let time = Date().timeIntervalSince(startedAt)
        return 0.06 + 0.1 * abs(sin(time * 5.3)) + 0.04 * abs(sin(time * 13.1))
    }

    func stop() -> URL? {
        guard let file else { return nil }
        self.file = nil
        do {
            try StubWAV.data().write(to: file)
            return file
        } catch {
            return nil
        }
    }
}

/// A valid WAV of quiet tone in the recorder's format (16 kHz, mono, 16-bit PCM).
enum StubWAV {
    static let sampleRate = 16_000

    static func data(seconds: Double = 0.25) -> Data {
        let count = Int(Double(sampleRate) * seconds)
        var samples = Data(capacity: count * 2)
        for index in 0..<count {
            let value = Int16(1_000 * sin(2 * .pi * 220 * Double(index) / Double(sampleRate)))
            withUnsafeBytes(of: value.littleEndian) { samples.append(contentsOf: $0) }
        }
        var wav = Data()
        func append(_ text: String) { wav.append(contentsOf: Array(text.utf8)) }
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) } }
        append("RIFF")
        append(UInt32(36 + samples.count))
        append("WAVE")
        append("fmt ")
        append(UInt32(16))
        append(UInt16(1)) // PCM
        append(UInt16(1)) // mono
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2)) // bytes a second
        append(UInt16(2)) // bytes a frame
        append(UInt16(16)) // bits a sample
        append("data")
        append(UInt32(samples.count))
        wav.append(samples)
        return wav
    }

    /// Leaves a note in [queue] as if recorded [ago] milliseconds before [now] in [profileId], old
    /// enough for the queue to take it.
    static func leaveNote(in queue: VoiceQueue, profileId: UUID, now: Int64, ago: Int64 = 60_000) throws {
        let recordedAt = now - ago
        let file = try queue.newFile(profileId: profileId, recordedAt: recordedAt)
        try data().write(to: file)
        let date = Date(timeIntervalSince1970: Double(recordedAt) / 1000)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path(percentEncoded: false))
    }
}
#endif
