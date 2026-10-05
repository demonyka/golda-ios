import Foundation
import GoldaCore
import GoldaData
import Testing

@testable import Golda

/// The operation form's words and what it reports afterwards, in both languages: the port of the
/// Kotlin `tr(...)` lines of `EntrySheet` and `Main.kt`, put together from the values the
/// repository returns (D18).
@Suite struct EntryTextTests {
    typealias E = EntryFixture
    static let ru = Locale(identifier: "ru")
    static let en = Locale(identifier: "en")

    // MARK: The catalog

    private func table(_ language: String) -> (plain: [String: String], plural: Set<String>) {
        let bundle = Bundle.main
        let strings = bundle.path(forResource: "Entry", ofType: "strings", inDirectory: nil, forLocalization: language)
            .flatMap { NSDictionary(contentsOfFile: $0) as? [String: String] } ?? [:]
        let plurals = bundle.path(forResource: "Entry", ofType: "stringsdict", inDirectory: nil, forLocalization: language)
            .flatMap { NSDictionary(contentsOfFile: $0) as? [String: Any] } ?? [:]
        return (strings, Set(plurals.keys))
    }

    @Test func bothLanguagesCarryTheSameKeys() {
        let english = table("en"), russian = table("ru")
        #expect(english.plain.count > 40)
        #expect(Set(english.plain.keys) == Set(russian.plain.keys))
        #expect(english.plural == russian.plural)
        #expect(english.plural == ["%lld days", "%lld hours", "%lld days of budget"])
    }

    @Test func russianIsReallyRussianAndNothingIsEmpty() {
        for (key, value) in table("en").plain {
            #expect(!value.isEmpty, "en: \(key)")
        }
        for (key, value) in table("ru").plain {
            #expect(!value.isEmpty, "ru: \(key)")
            #expect(value.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }, "ru value of “\(key)” has no Cyrillic: \(value)")
        }
    }

    @Test func theFormSpeaksBothLanguages() {
        #expect(EntryText.typeTitle(.expense).text(in: Self.ru) == "Расход")
        #expect(EntryText.typeTitle(.income).text(in: Self.ru) == "Доход")
        #expect(EntryText.typeTitle(.transfer).text(in: Self.en) == "Transfer")
        #expect(EntryText.record.text(in: Self.ru) == "Записать")
        #expect(EntryText.record.text(in: Self.en) == "Save")
        #expect(EntryText.save.text(in: Self.ru) == "Сохранить")
        #expect(EntryText.notSure.text(in: Self.ru) == "Сомневаюсь")
        #expect([EntryText.skip, EntryText.think, EntryText.buy].map { $0.text(in: Self.ru) } == ["Не беру", "Подумаю", "Беру"])
        #expect([EntryText.skip, EntryText.think, EntryText.buy].map { $0.text(in: Self.en) } == ["Skip", "Think", "Buy"])
        #expect(EntryAnnouncement.undo.text(in: Self.ru) == "Отменить")
        #expect(EntryAnnouncement.restore.text(in: Self.ru) == "Вернуть")
        #expect(EntryAnnouncement.restore.text(in: Self.en) == "Undo")
    }

    @Test func theNotesPlaceholderSaysWhatTheLineIsFor() {
        func placeholder(_ type: OpType, _ key: String? = nil, deciding: Bool = false) -> String {
            EntryText.notePlaceholder(type: type, categoryKey: key, deciding: deciding).text(in: Self.ru)
        }
        #expect(placeholder(.expense) == "Покупка")
        #expect(placeholder(.income) == "Откуда")
        #expect(placeholder(.transfer) == "Комментарий")
        #expect(placeholder(.expense, deciding: true) == "Что это")
        #expect(placeholder(.expense, "eating_out") == CategoryName.resource("eating_out").text(in: Self.ru))
    }

    @Test func theLinesUnderTheNumber() {
        #expect(EntryText.safeToday("1\u{202F}250 ₽", in: Self.ru) == "Можно сегодня 1\u{202F}250 ₽")
        #expect(EntryText.safeToday("1\u{202F}250 ₽", in: Self.en) == "Safe today 1\u{202F}250 ₽")
        #expect(EntryText.charged("5,87 $", isEstimate: true, in: Self.ru) == "≈ 5,87 $ со счёта")
        #expect(EntryText.charged("5,87 $", isEstimate: false, in: Self.en) == "5,87 $ from the account")
        #expect(EntryText.charged(nil, isEstimate: true, in: Self.en) == "≈ — from the account")
        #expect(EntryText.received("109,21 $", isEstimate: true, in: Self.ru) == "→ ≈ 109,21 $")
        #expect(EntryText.received("109,21 $", isEstimate: false, in: Self.ru) == "→ 109,21 $")
        // VoiceOver hears the amounts in words.
        #expect(EntryText.charged("5,87 $", isEstimate: true, in: Self.en, spoken: true).hasPrefix("about 5.87 US dollars"))
        #expect(EntryText.received("109 $", isEstimate: true, in: Self.en, spoken: true) == "Receives about 109 US dollars")
    }

    @Test func theFactsLabels() {
        func label(_ kind: EntryFormModel.Fact.Kind, _ value: String, _ locale: Locale) -> String {
            EntryText.factLabel(EntryFormModel.Fact(kind: kind, value: value), in: locale)
        }
        #expect(label(.hoursOfWork, "2,6", Self.ru) == "ч работы")
        #expect(label(.goalShare, "12 %", Self.ru) == "от цели")
        // A fraction takes "дня"; a whole number its own form, as on Android.
        #expect(["3,6", "1", "2", "5", "11", "21", "22", "1000"].map { label(.daysOfBudget, $0, Self.ru) } == [
            "дня бюджета", "день бюджета", "дня бюджета", "дней бюджета", "дней бюджета", "день бюджета", "дня бюджета",
            "дней бюджета",
        ])
        #expect(["3,6", "1", "5", "—"].map { label(.daysOfBudget, $0, Self.en) } == [
            "days of budget", "day of budget", "days of budget", "days of budget",
        ])
        #expect(EntryText.spokenFact(.init(kind: .hoursOfWork, value: "2,6"), in: Self.en) == "2,6 h of work")
    }

    @Test func theWaitOfThinkingItOver() {
        #expect([24, 72, 168].map { EntryText.wait($0, in: Self.ru) } == ["24 часа", "3 дня", "7 дней"])
        #expect([1, 24, 48, 168].map { EntryText.wait($0, in: Self.en) } == ["1 hour", "24 hours", "2 days", "7 days"])
    }

    // MARK: Toasts

    @Test func whatWasSavedWithTheWorkItCostAndWhatIsLeft() {
        let books = E()
        let data = books.data
        let draft = Draft(type: .expense, timestamp: E.now, accountId: books.cash.id, amountMinor: 1_500, categoryKey: "eating_out", note: "Шаурма")
        let impact = Impact(costRub: 49_500, hoursOfWork: 0.55, leftTodayRub: 50_300)
        #expect(EntryAnnouncement.saved(draft, impact: impact, data: data, in: Self.ru) == "Шаурма · 15 ₾\n≈ 0,6 ч работы · на сегодня осталось 503 ₽")
        #expect(EntryAnnouncement.saved(draft, impact: impact, data: data, in: Self.en) == "Шаурма · 15 ₾\n≈ 0,6 h of work · left for today 503 ₽")

        // Over budget, and no income set: no hours.
        let over = Impact(costRub: 49_500, hoursOfWork: nil, leftTodayRub: -12_000)
        #expect(EntryAnnouncement.saved(draft, impact: over, data: data, in: Self.ru) == "Шаурма · 15 ₾\nперерасход 120 ₽")
        #expect(EntryAnnouncement.saved(draft, impact: over, data: data, in: Self.en) == "Шаурма · 15 ₾\nover budget by 120 ₽")

        // Without a note the category names it, without either "Записано"; a foreign price shows as paid.
        var unnamed = draft
        unnamed.note = ""
        #expect(EntryAnnouncement.saved(unnamed, impact: nil, data: data, in: Self.ru) == CategoryName.resource("eating_out").text(in: Self.ru) + " · 15 ₾")
        unnamed.categoryKey = nil
        unnamed.accountId = books.usd.id
        unnamed.amountMinor = 574
        unnamed.purchaseAmountMinor = 1_500
        unnamed.purchaseCurrency = "GEL"
        #expect(EntryAnnouncement.saved(unnamed, impact: nil, data: data, in: Self.ru) == "Записано · 15 ₾")
        #expect(EntryAnnouncement.saved(unnamed, impact: nil, data: data, in: Self.en) == "Saved · 15 ₾")
        let income = Draft(type: .income, timestamp: E.now, accountId: books.rub.id, amountMinor: 5_000_000, categoryKey: "salary")
        #expect(EntryAnnouncement.saved(income, impact: nil, data: data, in: Self.en) == CategoryName.resource("salary").text(in: Self.en) + " · 50\u{202F}000 ₽")
    }

    @Test func whatWasDeleted() {
        let books = E()
        let coffee = E.operation(.expense, note: "Кофе", [(books.cash, -800, -26_400)])
        #expect(EntryAnnouncement.deleted(coffee, in: Self.ru) == "«Кофе» удалено")
        #expect(EntryAnnouncement.deleted(coffee, in: Self.en) == "“Кофе” deleted")
        let adjustment = E.operation(.adjustment, [(books.rub, -500, -500)])
        #expect(EntryAnnouncement.deleted(adjustment, in: Self.ru) == "«Запись» удалено")
        #expect(EntryAnnouncement.deleted(adjustment, in: Self.en) == "“Entry” deleted")
    }

    @Test func whatSkippingDid() {
        let wish = Wish(title: "Кроссовки", amountMinor: 25_000, currency: "GEL", createdAt: E.now, decideAt: E.now, status: .skipped)
        // What was not spent, with or without a main goal: nothing goes into it (D63).
        #expect(EntryAnnouncement.skipped(wish, in: Self.ru) == "Сэкономлено 250 ₾")
        #expect(EntryAnnouncement.skipped(wish, in: Self.en) == "Saved 250 ₾")
    }

    @Test func whenToDecide() {
        let wish = Wish(title: "Наушники", amountMinor: 12_000, currency: "USD", createdAt: E.now, decideAt: E.now + 72 * 3_600_000)
        #expect(EntryAnnouncement.thinking(wish, in: Self.ru) == "«Наушники» — решить через 3 дня")
        #expect(EntryAnnouncement.thinking(wish, in: Self.en) == "“Наушники”: decide in 3 days")
        var soon = wish
        soon.decideAt = E.now + 24 * 3_600_000
        #expect(EntryAnnouncement.thinking(soon, in: Self.ru) == "«Наушники» — решить через 24 часа")
    }
}
