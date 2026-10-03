import Foundation
import GoldaData

/// What the mic needs from the voice service: a file for the next note, understanding it, the
/// waiting notes, and every outcome. `VoiceService` is the real one; tests answer with a fake.
protocol VoiceNotes: Sendable {
    /// Where a note recorded now, in [profileId], goes.
    func newNote(profileId: UUID, recordedAt: Int64) throws -> URL
    /// Understands and books a note just recorded; the outcome arrives through `outcomes()`.
    func understand(note: URL) async
    /// The notes that wait (no network, no key, no consent), oldest first.
    func processWaiting() async
    /// Every outcome from now on, those of the queue included.
    func outcomes() -> AsyncStream<VoiceOutcome>
}

extension VoiceService: VoiceNotes {
    nonisolated func newNote(profileId: UUID, recordedAt: Int64) throws -> URL {
        try queue.newFile(profileId: profileId, recordedAt: recordedAt, fileExtension: "wav")
    }

    func understand(note: URL) async {
        await understand(file: note, late: false)
    }

    func processWaiting() async {
        await processQueue()
    }
}
