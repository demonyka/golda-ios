import Foundation
import GoldaCore
import GoldaData

/// What a toast about a note booked into a profile needs from that profile: its accounts'
/// currencies, its main currency, and its name when the phone has more than one profile
/// (ARCHITECTURE, "Голос": the confirmation names the profile then).
struct VoiceBooks: Sendable {
    var currencies: [UUID: String]
    var base: Base
    var profileName: String?
}

/// What the voice tells the person, as data: the sentence and what its button does. The texts are
/// Android's (`rememberVoice`, `describe`, `Wishes.impact`), from the "Voice" table of the String
/// Catalog; amounts are written by `Fmt`, the Russian way in both languages (D13).
struct VoiceNotice: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        /// "Отменить": deletes what the note booked, in the profile it was booked into.
        case undo(VoiceOutcome.Done)
        /// "Настройки": the app's settings, where the Gemini key goes.
        case openSettings
        /// "Записать": the operation form, to add by hand what was not made out.
        case addByHand
        /// "Настройки": the system's page for the app, where the microphone is allowed.
        case openSystemSettings
        /// "ОК": only closes the toast.
        case dismiss
    }

    var message: String
    var action: Action
    var length: UndoToast.Length

    func actionTitle(in locale: Locale) -> String {
        switch action {
        case .undo: Strings.undo.text(in: locale)
        case .openSettings, .openSystemSettings: Strings.settings.text(in: locale)
        case .addByHand: Strings.add.text(in: locale)
        case .dismiss: Strings.ok.text(in: locale)
        }
    }

    // MARK: Outcomes

    /// The toast for [outcome], or nil when there is nothing to say: a note that only asked to weigh
    /// a purchase up (the form says it), a stray tap with a blank transcript, or a note waiting for
    /// consent (the consent screen says it).
    static func of(_ outcome: VoiceOutcome, books: VoiceBooks?, locale: Locale) -> VoiceNotice? {
        switch outcome {
        case .done(let done):
            if !done.recorded.isEmpty { return recorded(done, books: books, locale: locale) }
            // A blank transcript is a stray tap: nothing to say about it.
            guard done.misunderstood, !done.transcript.allSatisfy(\.isWhitespace) else { return nil }
            return VoiceNotice(message: Strings.misunderstood(done.transcript).text(in: locale), action: .addByHand, length: .long)
        case .waiting(.noKey):
            return VoiceNotice(message: Strings.noKey.text(in: locale), action: .openSettings, length: .long)
        case .waiting(.offline):
            return VoiceNotice(message: Strings.offline.text(in: locale), action: .dismiss, length: .long)
        case .needsConsent:
            return nil
        case .failed(let failure):
            return VoiceNotice(message: failed(failure).text(in: locale), action: .dismiss, length: .long)
        }
    }

    /// "Шаурма 15 ₾ · Кофе 8 ₾" with what the last expense cost in work and what is left for today
    /// on the next line, "Из отложенного: " in front when the note waited; "Отменить" deletes it all.
    static func recorded(_ done: VoiceOutcome.Done, books: VoiceBooks?, locale: Locale) -> VoiceNotice {
        var items = done.recorded.map { describe($0.draft, books: books, locale: locale) }.joined(separator: " · ")
        if done.late { items = Strings.late(items).text(in: locale) }
        var lines = [items]
        if let impact = done.impact, let books { lines.append(comment(impact, base: books.base, locale: locale)) }
        if let name = books?.profileName { lines.append(Strings.profile(name).text(in: locale)) }
        return VoiceNotice(message: lines.joined(separator: "\n"), action: .undo(done), length: .long)
    }

    /// "Шаурма 15 ₾": the note, or the category, or "Записано", and the amount in the currency it
    /// was paid in (Android's `describe`).
    static func describe(_ draft: Draft, books: VoiceBooks?, locale: Locale) -> String {
        let code = draft.purchaseCurrency ?? books?.currencies[draft.accountId] ?? "RUB"
        let title: String = if !draft.note.allSatisfy(\.isWhitespace) {
            draft.note
        } else if let key = draft.categoryKey {
            CategoryName.resource(key).text(in: locale)
        } else {
            Strings.saved.text(in: locale)
        }
        return title + " " + Fmt.amount(draft.purchaseAmountMinor ?? draft.amountMinor, code)
    }

    /// "≈ 2,6 ч работы · на сегодня осталось 503 ₽" (Android's `Wishes.impact`).
    static func comment(_ impact: Impact, base: Base, locale: Locale) -> String {
        var parts: [String] = []
        if let hours = impact.hoursOfWork { parts.append(Strings.hoursOfWork(Fmt.number(hours, decimals: 1)).text(in: locale)) }
        let left = impact.leftTodayRub
        parts.append((left >= 0 ? Strings.leftToday(base.approx(left)) : Strings.overBudget(base.approx(-left))).text(in: locale))
        return parts.joined(separator: " · ")
    }

    static func failed(_ failure: VoiceOutcome.Failure) -> LocalizedStringResource {
        switch failure {
        case .lost: Strings.lost
        case .profileGone: Strings.profileGone
        case .rejected(let message): Strings.rejected(message)
        case .malformedAnswer: Strings.malformedAnswer
        case .storage: Strings.storage
        }
    }

    // MARK: The microphone

    /// Android: "Микрофон занят или недоступен".
    static func micBusy(locale: Locale) -> VoiceNotice {
        VoiceNotice(message: Strings.micBusy.text(in: locale), action: .dismiss, length: .short)
    }

    /// Android: "Без доступа к микрофону голос не работает"; the button leads to where it is allowed.
    static func micDenied(locale: Locale) -> VoiceNotice {
        VoiceNotice(message: Strings.micDenied.text(in: locale), action: .openSystemSettings, length: .long)
    }

    // MARK: Strings

    enum Strings {
        static let undo = LocalizedStringResource("Undo", table: "Components", comment: "The default action of an undo toast.")
        static let settings = LocalizedStringResource("Settings", table: "Voice", comment: "Voice toast button: opens the settings.")
        static let add = LocalizedStringResource("Add", table: "Voice", comment: "Voice toast button: opens the form to add an operation by hand.")
        static let ok = LocalizedStringResource("OK", table: "Voice", comment: "Voice toast button: only closes the toast.")
        static let saved = LocalizedStringResource("Saved", table: "Voice", comment: "Voice toast: title of a booked operation with neither a note nor a category.")
        static let noKey = LocalizedStringResource("Add a Gemini key in settings; the note is kept", table: "Voice", comment: "Voice toast: a note waits because no Gemini API key is set.")
        static let offline = LocalizedStringResource("No connection; the note will be worked out later", table: "Voice", comment: "Voice toast: a note waits for the network.")
        static let lost = LocalizedStringResource("The note got lost", table: "Voice", comment: "Voice toast: the recording file is missing.")
        static let profileGone = LocalizedStringResource("The note’s profile was deleted, and the note with it", table: "Voice", comment: "Voice toast: the profile a note was recorded in is gone.")
        static let malformedAnswer = LocalizedStringResource("Gemini’s answer made no sense; the note is kept", table: "Voice", comment: "Voice toast: the provider answered with something unreadable.")
        static let storage = LocalizedStringResource("Couldn’t save the note; it is kept for another try", table: "Voice", comment: "Voice toast: the books could not be written.")
        static let micBusy = LocalizedStringResource("The microphone is busy or unavailable", table: "Voice", comment: "Voice toast: recording could not start.")
        static let micDenied = LocalizedStringResource("Voice needs microphone access", table: "Voice", comment: "Voice toast: the microphone is not allowed.")

        static func misunderstood(_ transcript: String) -> LocalizedStringResource {
            LocalizedStringResource("Couldn’t make out “\(transcript)”. Add it with “+”", table: "Voice", comment: "Voice toast: nothing was understood; the argument is what was heard.")
        }

        static func late(_ items: String) -> LocalizedStringResource {
            LocalizedStringResource("From a saved note: \(items)", table: "Voice", comment: "Voice toast: a note recorded earlier was booked now; the argument lists what it booked.")
        }

        static func profile(_ name: String) -> LocalizedStringResource {
            LocalizedStringResource("Profile: \(name)", table: "Voice", comment: "Voice toast: the profile a note was booked into, when there are several.")
        }

        static func hoursOfWork(_ hours: String) -> LocalizedStringResource {
            LocalizedStringResource("≈ \(hours) h of work", table: "Voice", comment: "Voice toast: what an expense cost in hours of work, “≈ 2,6 h of work”.")
        }

        static func leftToday(_ amount: String) -> LocalizedStringResource {
            LocalizedStringResource("left for today \(amount)", table: "Voice", comment: "Voice toast: what is left to spend today after the expense.")
        }

        static func overBudget(_ amount: String) -> LocalizedStringResource {
            LocalizedStringResource("over budget by \(amount)", table: "Voice", comment: "Voice toast: how far today's budget is overspent after the expense.")
        }

        static func rejected(_ message: String) -> LocalizedStringResource {
            LocalizedStringResource("Gemini: \(message)", table: "Voice", comment: "Voice toast: Gemini refused the note; the argument is its own explanation.")
        }
    }
}
