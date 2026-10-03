import AVFoundation
import Foundation

/// Whether the app may listen, as the system answers it.
enum MicPermission: Equatable, Sendable {
    /// Never asked: the first tap on the mic asks.
    case undetermined
    case denied
    case granted
}

enum VoiceRecorderError: Error, Equatable, Sendable {
    /// The recorder refused to start: another app holds the microphone, or there is none.
    case unavailable
}

/// Records one voice note at a time. `VoiceMicModel` talks only to this, so tests drive the mic
/// with a fake and the debug stub records without a microphone.
@MainActor
protocol VoiceRecording: AnyObject {
    var permission: MicPermission { get }
    /// Asks for the microphone; true when it is granted.
    func requestPermission() async -> Bool
    /// Starts a note in [file], for at most `RecordingJudge.longest`. Throws when the microphone is
    /// busy or unavailable; nothing is left behind then.
    func start(into file: URL) throws
    /// Still recording. False once the time limit or an interruption (a call) ended the note by itself.
    var isRecording: Bool { get }
    /// How loud it is now, 0...1. Each call is also a sample for the silence check, as Android's
    /// `level()` was: silence is judged only when someone was watching the level.
    func level() -> Double
    /// Ends the note: its file, or nil when nothing worth sending was recorded (a stray tap, silence,
    /// an empty file), and that file is deleted.
    func stop() -> URL?
}

/// The rules for keeping a note, the port of the checks in Android's `VoiceRecorder.stop`. Plain
/// values, so a test can check them without a microphone.
struct RecordingJudge: Equatable, Sendable {
    /// A tap shorter than this is a stray one.
    static let shortest: TimeInterval = 0.8
    /// The hard stop.
    static let longest: TimeInterval = 60
    /// A note whose loudest moment stays under this is silence (Android: 3 % of full scale).
    static let silentPeak = 0.03
    /// Silence is judged only from this many samples on: fewer means nobody watched the level.
    static let fewestSamples = 3

    private(set) var samples = 0
    private(set) var peak = 0.0

    /// One look at the level.
    mutating func hear(_ level: Double) {
        samples += 1
        peak = max(peak, level)
    }

    /// Whether a note [duration] seconds long, with the levels heard, should go unsent.
    func isAccidental(duration: TimeInterval) -> Bool {
        duration < Self.shortest || (samples >= Self.fewestSamples && peak < Self.silentPeak)
    }

    /// AVAudioRecorder meters in decibels of full scale, -160 for silence; Android's level was the
    /// linear amplitude (`maxAmplitude / 32767`), which the thresholds above are in.
    static func linear(decibels: Float) -> Double {
        guard decibels.isFinite else { return 0 }
        return min(1, max(0, pow(10, Double(decibels) / 20)))
    }
}

/// The microphone through AVAudioRecorder: linear PCM, 16 kHz, mono, 16 bit, in a WAV file, the
/// format Gemini takes as `audio/wav` (about 32 KB a second, under 2 MB for the full minute).
@MainActor
final class LiveVoiceRecorder: VoiceRecording {
    private var recorder: AVAudioRecorder?
    private var file: URL?
    private var startedAt = Date.distantPast
    private var judge = RecordingJudge()

    /// What AVAudioRecorder is asked for; the `.wav` extension of the file picks the container.
    nonisolated static let settings: [String: Int] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: 16_000,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: 0,
        AVLinearPCMIsBigEndianKey: 0,
    ]

    /// A WAV file with only its header holds no sound.
    nonisolated static let headerBytes = 44

    var permission: MicPermission {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .granted
        case .denied: .denied
        default: .undetermined
        }
    }

    func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func start(into file: URL) throws {
        if recorder != nil { _ = stop() }
        let session = AVAudioSession.sharedInstance()
        do {
            // Record only: other audio pauses while the note is taken and comes back afterwards.
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
            let recorder = try AVAudioRecorder(url: file, settings: Self.settings)
            recorder.isMeteringEnabled = true
            guard recorder.record(forDuration: RecordingJudge.longest) else { throw VoiceRecorderError.unavailable }
            self.recorder = recorder
        } catch {
            release(session)
            try? FileManager.default.removeItem(at: file)
            throw error
        }
        self.file = file
        startedAt = Date()
        judge = RecordingJudge()
    }

    var isRecording: Bool { recorder?.isRecording ?? false }

    func level() -> Double {
        guard let recorder, recorder.isRecording else { return 0 }
        recorder.updateMeters()
        // The peak, as Android's `maxAmplitude`: the average would call quiet speech silence.
        let level = RecordingJudge.linear(decibels: recorder.peakPower(forChannel: 0))
        judge.hear(level)
        return level
    }

    func stop() -> URL? {
        guard let recorder, let file else { return nil }
        let duration = Date().timeIntervalSince(startedAt)
        recorder.stop()
        self.recorder = nil
        self.file = nil
        release(AVAudioSession.sharedInstance())
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false))[.size] as? Int) ?? 0
        guard !judge.isAccidental(duration: duration), size > Self.headerBytes else {
            try? FileManager.default.removeItem(at: file)
            return nil
        }
        return file
    }

    /// Gives the audio back, so music paused for the note plays on.
    private func release(_ session: AVAudioSession) {
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }
}
