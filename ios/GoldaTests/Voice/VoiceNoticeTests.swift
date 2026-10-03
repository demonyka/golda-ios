import Foundation
import GoldaCore
import GoldaData
import Testing

@testable import Golda

/// The sentences of the voice toasts in both languages, Android's `describe`, `Wishes.impact` and
/// the texts of `Repo.understand`. Amounts stay Russian-style in English too (D13).
@Suite struct VoiceNoticeTests {
    private let ru = Locale(identifier: "ru")
    private let en = Locale(identifier: "en")
    private let lari = UUID()
    private let dollars = UUID()
    private let profile = UUID()

    private var books: VoiceBooks {
        VoiceBooks(
            currencies: [lari: "GEL", dollars: "USD"],
            base: Base(Rates(["GEL": 30, "USD": 90], markup: 0), "RUB"),
            profileName: nil
        )
    }

    private func expense(_ minor: Int64, note: String = "", category: String? = "eating_out", account: UUID? = nil, purchase: (Int64, String)? = nil) -> Draft {
        Draft(
            type: .expense, timestamp: 0, accountId: account ?? lari, amountMinor: minor, categoryKey: category, note: note,
            purchaseAmountMinor: purchase?.0, purchaseCurrency: purchase?.1, isEstimate: purchase != nil
        )
    }

    private func done(_ drafts: [Draft], late: Bool = false, impact: Impact? = nil) -> VoiceOutcome.Done {
        VoiceOutcome.Done(
            profileId: profile, transcript: "", recorded: drafts.map { VoiceOutcome.Recorded(operationId: UUID(), draft: $0) },
            considering: [], misunderstood: false, late: late, impact: impact
        )
    }

    // MARK: Booked

    @Test func oneExpenseWithTheHoursAndWhatIsLeftForToday() {
        let note = done([expense(1_500, note: "Шаурма")], impact: Impact(costRub: 45_000, hoursOfWork: 2.6, leftTodayRub: 50_300))
        #expect(VoiceNotice.recorded(note, books: books, locale: ru).message == "Шаурма 15 ₾\n≈ 2,6 ч работы · на сегодня осталось 503 ₽")
        #expect(VoiceNotice.recorded(note, books: books, locale: en).message == "Шаурма 15 ₾\n≈ 2,6 h of work · left for today 503 ₽")
        #expect(VoiceNotice.recorded(note, books: books, locale: ru).action == .undo(note))
        #expect(VoiceNotice.recorded(note, books: books, locale: ru).length == .long)
    }

    @Test func withoutAnIncomeThereAreNoHoursAndAnOverspendIsSaid() {
        let left = done([expense(1_500, note: "Шаурма")], impact: Impact(costRub: 45_000, hoursOfWork: nil, leftTodayRub: 50_300))
        #expect(VoiceNotice.recorded(left, books: books, locale: ru).message == "Шаурма 15 ₾\nна сегодня осталось 503 ₽")
        let over = done([expense(1_500, note: "Шаурма")], impact: Impact(costRub: 45_000, hoursOfWork: 3, leftTodayRub: -12_000))
        #expect(VoiceNotice.recorded(over, books: books, locale: ru).message == "Шаурма 15 ₾\n≈ 3 ч работы · перерасход 120 ₽")
        #expect(VoiceNotice.recorded(over, books: books, locale: en).message == "Шаурма 15 ₾\n≈ 3 h of work · over budget by 120 ₽")
    }

    @Test func theMainCurrencyWritesWhatIsLeft() {
        var lariBooks = books
        lariBooks.base = Base(Rates(["GEL": 30, "USD": 90], markup: 0), "GEL")
        let note = done([expense(1_500, note: "Шаурма")], impact: Impact(costRub: 45_000, hoursOfWork: nil, leftTodayRub: 150_000))
        #expect(VoiceNotice.recorded(note, books: lariBooks, locale: ru).message == "Шаурма 15 ₾\nна сегодня осталось 50 ₾")
    }

    @Test func severalItemsAreJoinedAndASavedNoteSaysSo() {
        let note = done([expense(1_500, note: "Шаурма"), expense(800, note: "Кофе")], late: true)
        #expect(VoiceNotice.recorded(note, books: books, locale: ru).message == "Из отложенного: Шаурма 15 ₾ · Кофе 8 ₾")
        #expect(VoiceNotice.recorded(note, books: books, locale: en).message == "From a saved note: Шаурма 15 ₾ · Кофе 8 ₾")
    }

    @Test func theTitleFallsBackToTheCategoryThenToSaved() {
        #expect(VoiceNotice.describe(expense(1_500), books: books, locale: ru) == "Кафе 15 ₾")
        #expect(VoiceNotice.describe(expense(1_500), books: books, locale: en) == "Eating out 15 ₾")
        #expect(VoiceNotice.describe(expense(1_500, category: nil), books: books, locale: ru) == "Записано 15 ₾")
        #expect(VoiceNotice.describe(expense(1_500, note: " ", category: nil), books: books, locale: en) == "Saved 15 ₾")
    }

    @Test func theAmountIsWhatWasPaidInItsOwnCurrency() {
        // Lari paid from the dollar card: the toast says the lari, as the person said it.
        let converted = expense(507, note: "Рынок", account: dollars, purchase: (4_850, "GEL"))
        #expect(VoiceNotice.describe(converted, books: books, locale: ru) == "Рынок 48,50 ₾")
        #expect(VoiceNotice.describe(expense(1_250, note: "Такси", account: dollars), books: books, locale: ru) == "Такси 12,50 $")
        // An account the books do not know is taken for rubles, as Android did.
        #expect(VoiceNotice.describe(expense(1_500, note: "Шаурма", account: UUID()), books: books, locale: ru) == "Шаурма 15 ₽")
        #expect(VoiceNotice.describe(expense(1_500, note: "Шаурма"), books: nil, locale: ru) == "Шаурма 15 ₽")
    }

    @Test func withSeveralProfilesTheToastNamesTheNotesOne() {
        var named = books
        named.profileName = "Семья"
        let note = done([expense(1_500, note: "Шаурма")], impact: Impact(costRub: 45_000, hoursOfWork: nil, leftTodayRub: 50_300))
        #expect(VoiceNotice.recorded(note, books: named, locale: ru).message == "Шаурма 15 ₾\nна сегодня осталось 503 ₽\nПрофиль: Семья")
        #expect(VoiceNotice.recorded(note, books: named, locale: en).message == "Шаурма 15 ₾\nleft for today 503 ₽\nProfile: Семья")
    }

    @Test func withoutTheBooksTheCommentIsLeftOut() {
        let note = done([expense(1_500, note: "Шаурма")], impact: Impact(costRub: 45_000, hoursOfWork: 1, leftTodayRub: 50_300))
        #expect(VoiceNotice.recorded(note, books: nil, locale: ru).message == "Шаурма 15 ₽")
    }

    // MARK: Everything else

    @Test func whatIsNotUnderstoodIsQuoted() throws {
        let outcome = VoiceOutcome.done(VoiceOutcome.Done(
            profileId: profile, transcript: "ну это самое", recorded: [], considering: [], misunderstood: true, late: false, impact: nil
        ))
        let russian = try #require(VoiceNotice.of(outcome, books: nil, locale: ru))
        #expect(russian.message == "Не разобрать: «ну это самое». Можно записать через «+»")
        #expect(russian.action == .addByHand)
        #expect(russian.actionTitle(in: ru) == "Записать")
        #expect(VoiceNotice.of(outcome, books: nil, locale: en)?.message == "Couldn’t make out “ну это самое”. Add it with “+”")
        #expect(VoiceNotice.of(outcome, books: nil, locale: en)?.actionTitle(in: en) == "Add")
    }

    @Test func silenceAPurchaseToWeighUpAndConsentSayNothing() {
        let blank = VoiceOutcome.done(VoiceOutcome.Done(
            profileId: profile, transcript: " ", recorded: [], considering: [], misunderstood: true, late: false, impact: nil
        ))
        let consider = VoiceOutcome.done(VoiceOutcome.Done(
            profileId: profile, transcript: "Хочу наушники", recorded: [],
            considering: [Consider(title: "Наушники", amountMinor: 12_000, currency: "USD")], misunderstood: false, late: false, impact: nil
        ))
        #expect(VoiceNotice.of(blank, books: nil, locale: ru) == nil)
        #expect(VoiceNotice.of(consider, books: nil, locale: ru) == nil)
        #expect(VoiceNotice.of(.needsConsent, books: nil, locale: ru) == nil)
    }

    @Test func waitingNotesSayWhy() {
        let noKey = VoiceNotice.of(.waiting(.noKey), books: nil, locale: ru)
        #expect(noKey?.message == "Добавь ключ Gemini в настройках — запись сохранена")
        #expect(noKey?.action == .openSettings)
        #expect(VoiceNotice.of(.waiting(.noKey), books: nil, locale: en)?.message == "Add a Gemini key in settings; the note is kept")
        #expect(VoiceNotice.of(.waiting(.offline), books: nil, locale: ru)?.message == "Нет связи — запись разберётся позже")
        #expect(VoiceNotice.of(.waiting(.offline), books: nil, locale: en)?.message == "No connection; the note will be worked out later")
        #expect(VoiceNotice.of(.waiting(.offline), books: nil, locale: ru)?.actionTitle(in: ru) == "ОК")
    }

    @Test func failuresSayWhatWentWrong() {
        let cases: [(VoiceOutcome.Failure, String, String)] = [
            (.lost, "Запись потерялась", "The note got lost"),
            (.profileGone, "Профиль этой записи удалён, и запись вместе с ним", "The note’s profile was deleted, and the note with it"),
            (.rejected(message: "API key not valid"), "Gemini: API key not valid", "Gemini: API key not valid"),
            (.malformedAnswer, "Gemini ответил непонятно — запись сохранена", "Gemini’s answer made no sense; the note is kept"),
            (.storage, "Не получилось записать — запись подождёт следующей попытки", "Couldn’t save the note; it is kept for another try"),
        ]
        for (failure, russian, english) in cases {
            #expect(VoiceNotice.of(.failed(failure), books: nil, locale: ru)?.message == russian)
            #expect(VoiceNotice.of(.failed(failure), books: nil, locale: en)?.message == english)
            #expect(VoiceNotice.of(.failed(failure), books: nil, locale: ru)?.action == .dismiss)
        }
    }

    @Test func theMicrophoneInBothLanguages() {
        #expect(VoiceNotice.micBusy(locale: ru).message == "Микрофон занят или недоступен")
        #expect(VoiceNotice.micBusy(locale: en).message == "The microphone is busy or unavailable")
        #expect(VoiceNotice.micDenied(locale: ru).message == "Без доступа к микрофону голос не работает")
        #expect(VoiceNotice.micDenied(locale: en).message == "Voice needs microphone access")
        #expect(VoiceNotice.micDenied(locale: ru).actionTitle(in: ru) == "Настройки")
        #expect(VoiceNotice.micDenied(locale: en).action == .openSystemSettings)
    }

    @Test func undoIsTheComponentsUndo() {
        let note = done([expense(1_500, note: "Шаурма")])
        #expect(VoiceNotice.recorded(note, books: books, locale: ru).actionTitle(in: ru) == "Отменить")
        #expect(VoiceNotice.recorded(note, books: books, locale: en).actionTitle(in: en) == "Undo")
    }
}
