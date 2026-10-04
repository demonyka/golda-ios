import ActivityKit
import Foundation

/// The Live Activity of a voice note recorded without opening the app (`BackgroundVoiceNote`): the
/// Lock Screen and the Dynamic Island say it listens, then that it works the note out, then what
/// the note booked. iOS records in the background only while such an activity runs
/// (`AudioRecordingIntent`), and the person must always see that the microphone is on.
///
/// Compiled into the widgets as well, which draw it (`VoiceActivityWidget`). The app writes the
/// sentences, in its own language, with the same words as its toasts; the widgets add only their
/// fixed labels («Слушаю…», «Стоп»).
struct VoiceActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var phase: Phase
        /// When listening began: the Lock Screen counts the seconds from it, as a recorder does.
        var startedAt: Date
        /// What the note became, «Шаурма 15 ₾», or why it needs the app; empty while listening and
        /// while the note is worked out.
        var headline: String = ""
        /// The second line: what the expense cost in work and what is left for today, the profile.
        var detail: String?
        /// What «Отменить» deletes, while the note's operations can still be undone.
        var undo: VoiceUndoTicket?
    }

    enum Phase: String, Codable, Hashable, Sendable {
        /// The microphone is on; «Стоп» ends the note.
        case listening
        /// The note goes to the model, «Разбираю…».
        case thinking
        /// Booked: what it became, with «Отменить».
        case recorded
        /// «Отменить» was pressed: nothing of the note is left.
        case undone
        /// The note needs the app: a purchase to weigh up, words not understood, a missing key, a
        /// failure. A tap on the activity opens Golda, where the toast or the form waits.
        case needsApp
    }
}

/// What «Отменить» on the Live Activity deletes: the operations one note booked, in the profile it
/// booked them into. Plain strings, so it travels as the undo intent's parameters.
struct VoiceUndoTicket: Codable, Hashable, Sendable {
    var profileId: UUID
    var operationIds: [UUID]
}
