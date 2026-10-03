import Observation

/// What the microphone's views need from whatever records: the state, the loudness and the tap.
/// The shell talks only to this, so stage 3 swaps the stand-in below for the real recorder (and its
/// queue) without touching a view.
@MainActor
protocol MicModel: AnyObject, Observable {
    var state: MicState { get }
    /// Raw loudness, 0...1, while recording.
    var level: Double { get }
    /// The one gesture: start, stop, and nothing while a note is worked out.
    func tap()
}

/// Stage 2a's stand-in: no audio, no network. Each tap moves the mic on, idle → recording →
/// thinking → idle, so both layouts can be tried in every state.
@MainActor @Observable
final class StubMicModel: MicModel {
    private(set) var state = MicState.idle
    private(set) var level = 0.0

    /// A steady murmur, so the waveform has something to show while "recording".
    static let recordingLevel = 0.12

    func tap() {
        switch state {
        case .idle:
            state = .recording
            level = Self.recordingLevel
        case .recording:
            state = .thinking
            level = 0
        case .thinking:
            state = .idle
        }
    }
}
