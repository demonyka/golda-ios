import Foundation
import GoldaCore
import GoldaData

/// What the Live Activity of a note recorded outside the app shows at each step, and what is left
/// behind when it ends. Plain values, so a test can check every outcome without ActivityKit.
///
/// The sentences are the toasts' (`VoiceNotice`), so the Lock Screen says what the app would have
/// said; only a purchase to weigh up gets words of its own, since the app says that with a form.
enum VoiceActivityContent {
    typealias State = VoiceActivityAttributes.ContentState

    /// How long the final state stays on the Lock Screen and in the Dynamic Island: long enough to
    /// read it and reach «Отменить», short enough not to sit there for the system's four hours.
    static let lingering: Duration = .seconds(60)
    /// «Отменено» needs only a glance.
    static let undoneLingering: Duration = .seconds(4)

    static func listening(since startedAt: Date) -> State {
        State(phase: .listening, startedAt: startedAt)
    }

    static func thinking(since startedAt: Date) -> State {
        State(phase: .thinking, startedAt: startedAt)
    }

    /// When a state stops being true unless the app says more, for ActivityKit's `staleDate`. A
    /// run that dies mid-note cannot end its activity, and «Слушаю…» must not outlive the
    /// microphone: listening goes stale a little after the recorder's minute (the chimes and a
    /// slow start), thinking after the model's longest wait (45 s) with a note or two ahead of it
    /// in the queue. The widget then leads to the app (`VoiceActivityWidget`). A final state ends
    /// the activity and needs none.
    static func staleDate(of state: State, at now: Date) -> Date? {
        switch state.phase {
        case .listening: state.startedAt.addingTimeInterval(75)
        case .thinking: now.addingTimeInterval(90)
        case .recorded, .undone, .needsApp: nil
        }
    }

    /// iOS took the background time away while the note was at the model: it waits in the queue,
    /// and the app is where it ends.
    static func expired(since startedAt: Date, locale: Locale) -> Ending {
        needsApp(Strings.openToFinish.text(in: locale), since: startedAt)
    }

    /// After «Отменить»: the same note, with nothing left to undo.
    static func undone(_ state: State) -> State {
        State(phase: .undone, startedAt: state.startedAt, headline: state.headline)
    }

    /// How the activity ends for one outcome.
    struct Ending: Equatable, Sendable {
        /// The last state; nil ends the activity at once, with nothing to show (a stray tap).
        var state: State?
        /// A notification left behind when the note needs the app: the activity goes after a
        /// minute, the notification stays until it is tapped.
        var alert: String?
    }

    /// The end of a note understood as [outcome]. [books] are the note's profile's, as the toast
    /// reads them (`AppModel.voiceBooks`); [locale] is the app's language.
    static func ending(of outcome: VoiceOutcome, books: VoiceBooks?, since startedAt: Date, locale: Locale) -> Ending {
        switch outcome {
        case .done(let done):
            let toWeighUp = done.considering.first.map { weighUp($0, locale: locale) }
            if !done.recorded.isEmpty {
                let lines = VoiceNotice.recorded(done, books: books, locale: locale).message.split(separator: "\n").map(String.init)
                let ticket = VoiceUndoTicket(profileId: done.profileId, operationIds: done.recorded.map(\.operationId))
                return Ending(
                    state: State(
                        phase: .recorded, startedAt: startedAt, headline: lines.first ?? "",
                        detail: lines.count > 1 ? lines.dropFirst().joined(separator: "\n") : nil, undo: ticket
                    ),
                    // The expense is booked; the purchase in the same note still waits for a decision.
                    alert: toWeighUp
                )
            }
            if let toWeighUp { return needsApp(toWeighUp, since: startedAt) }
            // Nothing to say about a stray tap with a blank transcript.
            guard let notice = VoiceNotice.of(outcome, books: books, locale: locale) else { return Ending(state: nil, alert: nil) }
            return needsApp(notice.message, since: startedAt)
        case .needsConsent:
            // Consent is checked before a note starts outside the app; withdrawn in the meantime,
            // the consent screen waits in the app.
            return needsApp(Strings.openToFinish.text(in: locale), since: startedAt)
        case .waiting, .failed:
            let message = VoiceNotice.of(outcome, books: books, locale: locale)?.message ?? Strings.openToFinish.text(in: locale)
            return needsApp(message, since: startedAt)
        }
    }

    private static func needsApp(_ message: String, since startedAt: Date) -> Ending {
        Ending(state: State(phase: .needsApp, startedAt: startedAt, headline: message), alert: message)
    }

    /// «Сомневаюсь: наушники 120 $ — реши в Golda»: the app opens the purchase in «Сомневаюсь».
    static func weighUp(_ consider: Consider, locale: Locale) -> String {
        let item = [consider.title, Fmt.amount(consider.amountMinor, consider.currency)]
            .filter { !$0.allSatisfy(\.isWhitespace) }
            .joined(separator: " ")
        return Strings.weighUp(item).text(in: locale)
    }

    enum Strings {
        static let openToFinish = LocalizedStringResource(
            "Open Golda to finish the note", table: "VoiceActivity",
            comment: "Live Activity and notification: a note recorded from the Lock Screen needs the app."
        )

        static func weighUp(_ item: String) -> LocalizedStringResource {
            LocalizedStringResource(
                "Not sure: \(item). Decide in Golda", table: "VoiceActivity",
                comment: "Live Activity and notification: a voice note asked to weigh a purchase up; the argument is the purchase and its price."
            )
        }
    }
}
