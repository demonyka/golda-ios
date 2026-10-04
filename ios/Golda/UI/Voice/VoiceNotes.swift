import Foundation
import GoldaData

/// What the mic needs from the voice service: a file for the next note, understanding it, the
/// waiting notes, and every outcome. `VoiceService` is the real one; tests answer with a fake.
protocol VoiceNotes: Sendable {
    /// Where a note recorded now, in [profileId], goes.
    func newNote(profileId: UUID, recordedAt: Int64) throws -> URL
    /// Understands and books a note just recorded. The outcome arrives through `outcomes()` too;
    /// a note recorded outside the app also shows it on its Live Activity.
    @discardableResult
    func understand(note: URL) async -> VoiceOutcome
    /// The notes that wait (no network, no key, no consent), oldest first.
    func processWaiting() async
    /// Every outcome from now on, those of the queue included.
    func outcomes() -> AsyncStream<VoiceOutcome>
}

// `newNote` is the service's own: it holds the note back from the queue until it is understood.
extension VoiceService: VoiceNotes {
    func understand(note: URL) async -> VoiceOutcome {
        await understand(file: note, late: false)
    }

    func processWaiting() async {
        await processQueue()
    }
}
