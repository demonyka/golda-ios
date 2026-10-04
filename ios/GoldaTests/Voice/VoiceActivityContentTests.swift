import Foundation
import GoldaCore
import GoldaData
import Testing

@testable import Golda

/// What the Live Activity of a note recorded outside the app says at each step, and what is left
/// behind: the toasts' sentences, «Отменить» for what was booked, the app for what needs it.
@Suite struct VoiceActivityContentTests {
    private let ru = Locale(identifier: "ru")
    private let en = Locale(identifier: "en")
    private let lari = UUID()
    private let profile = UUID()
    private let startedAt = Date(timeIntervalSince1970: 1_000)

    private var books: VoiceBooks {
        VoiceBooks(currencies: [lari: "GEL"], base: Base(Rates(["GEL": 30], markup: 0), "RUB"), profileName: nil)
    }

    private func shawarma(_ id: UUID = UUID()) -> VoiceOutcome.Recorded {
        VoiceOutcome.Recorded(
            operationId: id,
            draft: Draft(type: .expense, timestamp: 0, accountId: lari, amountMinor: 1_500, categoryKey: "eating_out", note: "Шаурма")
        )
    }

    private func done(recorded: [VoiceOutcome.Recorded] = [], considering: [Consider] = [], transcript: String = "", misunderstood: Bool = false) -> VoiceOutcome {
        .done(VoiceOutcome.Done(
            profileId: profile, transcript: transcript, recorded: recorded, considering: considering,
            misunderstood: misunderstood, late: false, impact: nil
        ))
    }

    @Test func listeningAndThinkingCarryOnlyTheStart() {
        let listening = VoiceActivityContent.listening(since: startedAt)
        #expect(listening.phase == .listening)
        #expect(listening.startedAt == startedAt)
        #expect(listening.headline.isEmpty && listening.detail == nil && listening.undo == nil)
        let thinking = VoiceActivityContent.thinking(since: startedAt)
        #expect(thinking.phase == .thinking)
        #expect(thinking.startedAt == startedAt)
    }

    /// A run that dies mid-note cannot end its activity: «Слушаю…» goes stale soon after the
    /// recorder's minute, «Разбираю…» after the model's longest wait, so the Lock Screen stops
    /// claiming the microphone is on. A final state ends the activity and needs no stale date.
    @Test func listeningAndThinkingGoStaleWhenNothingFollows() {
        let now = startedAt.addingTimeInterval(20)
        #expect(VoiceActivityContent.staleDate(of: VoiceActivityContent.listening(since: startedAt), at: now) == startedAt.addingTimeInterval(75))
        #expect(VoiceActivityContent.staleDate(of: VoiceActivityContent.thinking(since: startedAt), at: now) == now.addingTimeInterval(90))
        let ended = VoiceActivityContent.State(phase: .needsApp, startedAt: startedAt, headline: "…")
        #expect(VoiceActivityContent.staleDate(of: ended, at: now) == nil)
    }

    /// Out of background time while the note is worked out: the note waits in the app.
    @Test func runningOutOfTimeLeadsToTheApp() {
        let ending = VoiceActivityContent.expired(since: startedAt, locale: ru)
        #expect(ending.state?.phase == .needsApp)
        #expect(ending.state?.headline == "Открой Golda, чтобы закончить запись")
        #expect(ending.alert == "Открой Golda, чтобы закончить запись")
        #expect(VoiceActivityContent.expired(since: startedAt, locale: en).alert == "Open Golda to finish the note")
    }

    /// «Шаурма 15 ₾» as the toast says it, with «Отменить» for exactly what was booked; nothing to
    /// open the app for.
    @Test func aBookedNoteSaysWhatItBookedWithUndo() throws {
        let first = shawarma(), second = shawarma()
        let ending = VoiceActivityContent.ending(of: done(recorded: [first, second]), books: books, since: startedAt, locale: ru)
        let state = try #require(ending.state)
        #expect(state.phase == .recorded)
        #expect(state.headline == "Шаурма 15 ₾ · Шаурма 15 ₾")
        #expect(state.detail == nil)
        #expect(state.startedAt == startedAt)
        #expect(state.undo == VoiceUndoTicket(profileId: profile, operationIds: [first.operationId, second.operationId]))
        #expect(ending.alert == nil)
    }

    /// The toast's further lines (the profile, what the expense cost) are the second line.
    @Test func theToastsFurtherLinesAreTheDetail() {
        var named = books
        named.profileName = "Семья"
        let state = VoiceActivityContent.ending(of: done(recorded: [shawarma()]), books: named, since: startedAt, locale: ru).state
        #expect(state?.headline == "Шаурма 15 ₾")
        #expect(state?.detail == "Профиль: Семья")
    }

    /// A purchase to weigh up is decided in the app's form: the activity and a notification lead there.
    @Test func aPurchaseToWeighUpLeadsToTheApp() {
        let headphones = Consider(title: "Наушники", amountMinor: 12_000, currency: "USD")
        let ending = VoiceActivityContent.ending(of: done(considering: [headphones]), books: books, since: startedAt, locale: ru)
        #expect(ending.state?.phase == .needsApp)
        #expect(ending.state?.headline == "Сомневаюсь: Наушники 120 $. Реши в Golda")
        #expect(ending.state?.undo == nil)
        #expect(ending.alert == ending.state?.headline)
        let english = VoiceActivityContent.ending(of: done(considering: [headphones]), books: books, since: startedAt, locale: en)
        #expect(english.alert == "Not sure: Наушники 120 $. Decide in Golda")
    }

    /// An expense booked and a purchase to weigh up in one note: the expense can be undone here,
    /// and the purchase still waits in the app.
    @Test func anExpenseWithAPurchaseIsBookedAndThePurchaseLeadsToTheApp() {
        let headphones = Consider(title: "Наушники", amountMinor: 12_000, currency: "USD")
        let ending = VoiceActivityContent.ending(of: done(recorded: [shawarma()], considering: [headphones]), books: books, since: startedAt, locale: ru)
        #expect(ending.state?.phase == .recorded)
        #expect(ending.state?.undo != nil)
        #expect(ending.alert == "Сомневаюсь: Наушники 120 $. Реши в Golda")
    }

    @Test func wordsNotUnderstoodLeadToTheApp() {
        let ending = VoiceActivityContent.ending(of: done(transcript: "Ну это", misunderstood: true), books: books, since: startedAt, locale: ru)
        #expect(ending.state?.phase == .needsApp)
        #expect(ending.state?.headline == "Не разобрать: «Ну это». Можно записать через «+»")
        #expect(ending.alert == ending.state?.headline)
    }

    /// A stray press with a blank transcript says nothing, as the toast does not.
    @Test func aBlankNoteEndsWithNothing() {
        let ending = VoiceActivityContent.ending(of: done(transcript: " ", misunderstood: true), books: books, since: startedAt, locale: ru)
        #expect(ending == VoiceActivityContent.Ending(state: nil, alert: nil))
    }

    @Test func aWaitingOrFailedNoteSaysWhyAsTheToastDoes() {
        let offline = VoiceActivityContent.ending(of: .waiting(.offline), books: nil, since: startedAt, locale: ru)
        #expect(offline.state?.phase == .needsApp)
        #expect(offline.state?.headline == "Нет связи — запись разберётся позже")
        #expect(offline.alert == offline.state?.headline)
        let failed = VoiceActivityContent.ending(of: .failed(.malformedAnswer), books: nil, since: startedAt, locale: en)
        #expect(failed.state?.headline == "Gemini’s answer made no sense; the note is kept")
        let consent = VoiceActivityContent.ending(of: .needsConsent, books: nil, since: startedAt, locale: ru)
        #expect(consent.state?.headline == "Открой Golda, чтобы закончить запись")
    }

    @Test func undoneKeepsTheWordsAndDropsTheButton() throws {
        let state = VoiceActivityContent.ending(of: done(recorded: [shawarma()]), books: books, since: startedAt, locale: ru).state
        let undone = VoiceActivityContent.undone(try #require(state))
        #expect(undone.phase == .undone)
        #expect(undone.headline == "Шаурма 15 ₾")
        #expect(undone.undo == nil)
    }
}
