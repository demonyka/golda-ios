import AVFoundation
import Foundation
import UIKit

/// The sounds around a voice note, as a voice assistant makes them: a rising chime when the
/// microphone starts listening, a falling one when it stops. Both the mic in the app and a note
/// recorded from the Lock Screen (`BackgroundVoiceNote`) play them, so the person knows the phone
/// listens without looking at it.
///
/// The recorder runs inside these calls, so the order is fixed in one place: the rising chime ends
/// before the recording begins, and the falling one starts after it has ended, so neither is in
/// the note sent to the model. Tests play a fake that logs the order.
@MainActor
protocol VoiceCues: AnyObject {
    /// Plays the rising chime, with a tap of the haptic, and runs [start] once it has died away.
    func listen(then start: () throws -> Void) async rethrows
    /// Runs [stop], then plays the falling chime. Returns what [stop] returned.
    func stop(_ stop: () -> URL?) -> URL?
}

/// One audio session for the chimes and the recorder: each holds it while it plays or records, and
/// it is let go when the last one is done. Handing it from the chime to the recorder without letting
/// go avoids a gap in which music paused for the note would start again for a moment.
@MainActor
final class VoiceAudioSession {
    static let shared = VoiceAudioSession()

    private var holds = 0

    /// Play and record: the category recording needs, and one that also plays the chimes. It is
    /// the category of a call or a voice assistant, so the chimes sound with the ring switch on
    /// silent, as the system's own listening sounds do: a note started from the Lock Screen has no
    /// other sign that the phone listens to someone not looking at it. Out of the
    /// speaker, not the earpiece, and through Bluetooth headphones when they are on; the voice
    /// itself is always taken from the phone's microphone.
    func hold() throws {
        if holds == 0 {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try session.setActive(true)
        }
        holds += 1
    }

    /// Gives the audio back once nobody holds it, so music paused for the note plays on.
    func release() {
        guard holds > 0 else { return }
        holds -= 1
        if holds == 0 {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}

/// The chimes in `Resources/Sounds`, made by `tools/voice_chimes.py`, and the haptic of the start.
@MainActor
final class LiveVoiceCues: VoiceCues {
    static let shared = LiveVoiceCues()

    private let session = VoiceAudioSession.shared
    /// The player of the chime that sounds now: AVAudioPlayer stops when it is let go.
    private var player: AVAudioPlayer?

    func listen(then start: () throws -> Void) async rethrows {
        // The haptic is felt at once, the chime takes a third of a second; the app has had none at
        // the start of a note until now. In the background the system ignores it.
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let held = (try? session.hold()) != nil
        defer { if held { session.release() } }
        if held, let player = play("voice-start") {
            // The recorder must not hear it; the file's own length says when it is over.
            try? await Task.sleep(for: .seconds(player.duration))
        }
        try start()
    }

    func stop(_ stop: () -> URL?) -> URL? {
        // Held across the stop, so the falling chime plays in the session the note used.
        let held = (try? session.hold()) != nil
        let file = stop()
        guard held else { return file }
        guard let player = play("voice-stop") else {
            session.release()
            return file
        }
        Task { [session] in
            try? await Task.sleep(for: .seconds(player.duration))
            session.release()
        }
        return file
    }

    /// Starts the chime [name] and returns its player, or nil when it cannot sound: the note goes
    /// on without it.
    private func play(_ name: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
              let player = try? AVAudioPlayer(contentsOf: url)
        else { return nil }
        player.prepareToPlay()
        guard player.play() else { return nil }
        self.player = player
        return player
    }
}
