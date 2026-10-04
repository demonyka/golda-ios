import Foundation
import GoldaCore

/// What became of one voice note, Android's `VoiceOutcome`. Data and reasons only: the screens
/// write the sentences ("Записано", "Нет связи — запись разберётся позже") from the String Catalog.
public enum VoiceOutcome: Equatable, Sendable {
    /// Understood and booked; the note's file is gone.
    case done(Done)
    /// Kept for later; the queue stops here and tries again on the next run.
    case waiting(WaitReason)
    /// The person has not agreed to send voice to the provider yet (App Review 5.1.2(i)). Nothing
    /// left the phone and the note is kept.
    case needsConsent
    /// Not understood this time. The note is kept, except when it has nowhere to go
    /// (`profileGone`) or is gone already (`lost`).
    case failed(Failure)

    public enum WaitReason: Equatable, Sendable {
        /// No API key yet: "add a key in the settings, the note is kept".
        case noKey
        /// No connection, or the service failed on its side.
        case offline
        /// The provider does not work in this country (D45): the note waits to be understood from
        /// somewhere it does.
        case unsupportedLocation
    }

    public enum Failure: Equatable, Sendable {
        /// The note's file is missing (Android: "запись потерялась").
        case lost
        /// The profile the note was recorded in was deleted since; the note went with it.
        case profileGone
        /// The provider refused the note; its own words, or "HTTP <code>". Android showed
        /// "Gemini: <message>".
        case rejected(message: String)
        /// The provider answered with something other than the schema.
        case malformedAnswer
        /// The books could not be read or written; nothing of the note was booked.
        case storage
    }

    /// One operation the note became.
    public struct Recorded: Equatable, Sendable {
        public var operationId: UUID
        /// What was booked, as `VoiceMapper` drafted it.
        public var draft: Draft

        public init(operationId: UUID, draft: Draft) {
            self.operationId = operationId
            self.draft = draft
        }
    }

    public struct Done: Equatable, Sendable {
        /// The profile the note was booked into: the one active when it was recorded. Undo and
        /// "хочу купить" act in it, and the confirmation names it when there are several.
        public var profileId: UUID
        public var transcript: String
        /// Each saved operation with what was saved, in the order spoken.
        public var recorded: [Recorded]
        /// "Хочу купить": not spent, waiting for a decision. An empty title means no name was
        /// said, unless the service was given a word for it.
        public var considering: [Consider]
        /// Something in the note was not understood.
        public var misunderstood: Bool
        /// Understood from the queue, after the moment it was recorded.
        public var late: Bool
        /// What the last expense cost in work and what is left for today; nil without an expense.
        public var impact: Impact?

        public init(
            profileId: UUID, transcript: String, recorded: [Recorded], considering: [Consider], misunderstood: Bool,
            late: Bool, impact: Impact?
        ) {
            self.profileId = profileId
            self.transcript = transcript
            self.recorded = recorded
            self.considering = considering
            self.misunderstood = misunderstood
            self.late = late
            self.impact = impact
        }
    }
}
