import Foundation
import Testing

@testable import Golda

/// The Insights table carries every line in Russian and in English (CLAUDE.md: both, in one change),
/// as the build compiles them into the two languages' tables.
@Suite struct InsightsStringsTests {
    typealias F = HomeFixture

    private func table(_ language: String) -> [String: String] {
        Bundle.main.path(forResource: "Insights", ofType: "strings", inDirectory: nil, forLocalization: language)
            .flatMap { NSDictionary(contentsOfFile: $0) as? [String: String] } ?? [:]
    }

    @Test func bothLanguagesCarryTheSameKeys() {
        let english = table("en"), russian = table("ru")
        #expect(english.count > 15)
        #expect(Set(english.keys) == Set(russian.keys))
    }

    @Test func russianIsReallyRussianAndNothingIsEmpty() {
        for (key, value) in table("en") {
            #expect(!value.isEmpty, "en: \(key)")
        }
        for (key, value) in table("ru") {
            #expect(!value.isEmpty, "ru: \(key)")
            #expect(value.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }, "ru value of “\(key)” has no Cyrillic: \(value)")
        }
    }

    /// A percent sign in a catalog value would be read as the start of a format; percents come in
    /// as arguments, written by `GoalPercent`.
    @Test func noLineHasAStrayPercentSign() {
        for language in ["en", "ru"] {
            for (key, value) in table(language) {
                let stripped = value.replacingOccurrences(of: "%@", with: "").replacingOccurrences(of: "%lld", with: "")
                #expect(!stripped.contains("%"), "\(language): \(key)")
            }
        }
    }

    @Test func theScreensLinesAreTranslated() {
        let lines: [(LocalizedStringResource, String, String)] = [
            (InsightsContent.customTitle, "Свой период", "Custom range"),
            (InsightsContent.emptyText, "За эти дни трат нет.", "No spending in these days."),
            (InsightsContent.incomeTitle, "Доходы", "Income"),
            (InsightsContent.exchangeTitle, "Потери на обмене", "Lost on exchange"),
            (InsightsContent.budgetLabel, "Бюджет на день", "Daily budget"),
            (InsightsContent.daysLabel, "Траты по дням", "Spending by day"),
            (InsightsContent.rowHint, "Показывает категорию в кольце", "Shows this category in the ring"),
            (InsightsContent.rangeHint, "Меняет даты", "Changes the dates"),
        ]
        for (resource, russian, english) in lines {
            #expect(resource.text(in: F.ru) == russian)
            #expect(resource.text(in: F.en) == english)
        }
    }
}
