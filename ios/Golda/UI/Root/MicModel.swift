import Observation

/// What the shell needs from the voice: the mic's state, loudness and tap, and what the voice has
/// to say back. The shell talks only to this, so `VoiceMicModel` (the app) and `StubMicModel`
/// (previews and snapshots) swap without touching a view.
@MainActor
protocol MicModel: AnyObject, Observable {
    var state: MicState { get }
    /// Raw loudness, 0...1, while recording.
    var level: Double { get }
    /// The one gesture: start, stop, and nothing while a note is worked out.
    func tap()
    /// What a note booked, with "Отменить", or why a note waits. The tab on screen shows it above
    /// the mic and clears it when it goes.
    var toast: UndoToast? { get set }
    /// A screen the voice asks for: the consent before the first note, the operation form for "хочу
    /// купить". The shell presents it as soon as nothing else is open, and clears it.
    var route: AppRoute? { get set }
    /// The answer on the consent screen: agreeing starts the recording a tap asked for.
    func answerConsent(_ agreed: Bool)
}

/// Stage 2a's stand-in, kept for previews and snapshots: no audio, no network. Each tap moves the
/// mic on, idle → recording → thinking → idle, so the mic can be tried in every state.
@MainActor @Observable
final class StubMicModel: MicModel {
    private(set) var state = MicState.idle
    private(set) var level = 0.0
    var toast: UndoToast?
    var route: AppRoute?

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

    func answerConsent(_ agreed: Bool) {}
}
