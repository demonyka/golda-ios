import Foundation
import Testing

@testable import Golda

/// The Goals table carries every line in Russian and in English (CLAUDE.md: both, in one change),
/// plural lines included, as the build compiles them into the two languages' tables.
@Suite struct GoalsStringsTests {
    typealias F = HomeFixture

    private func table(_ language: String) -> (plain: [String: String], plural: Set<String>) {
        let bundle = Bundle.main
        let strings = bundle.path(forResource: "Goals", ofType: "strings", inDirectory: nil, forLocalization: language)
            .flatMap { NSDictionary(contentsOfFile: $0) as? [String: String] } ?? [:]
        let plurals = bundle.path(forResource: "Goals", ofType: "stringsdict", inDirectory: nil, forLocalization: language)
            .flatMap { NSDictionary(contentsOfFile: $0) as? [String: Any] } ?? [:]
        return (strings, Set(plurals.keys))
    }

    @Test func bothLanguagesCarryTheSameKeys() {
        let english = table("en"), russian = table("ru")
        #expect(english.plain.count > 40)
        #expect(Set(english.plain.keys) == Set(russian.plain.keys))
        #expect(english.plural == russian.plural)
        #expect(english.plural == ["in %lld hours", "in %lld days"])
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

    /// A percent sign in a catalog value would be read as the start of a format; percents come in
    /// as arguments, built by `GoalPercent`.
    @Test func noLineHasAStrayPercentSign() {
        for language in ["en", "ru"] {
            for (key, value) in table(language).plain {
                let stripped = value.replacingOccurrences(of: "%@", with: "").replacingOccurrences(of: "%lld", with: "")
                #expect(!stripped.contains("%"), "\(language): \(key)")
            }
        }
    }

    @Test func theScreensLinesAreTranslated() {
        let lines: [(LocalizedStringResource, String, String)] = [
            (GoalsHero.caption, "Копилка", "Savings"),
            (GoalsContent.goalsTitle, "Цели", "Goals"),
            (GoalsContent.otherGoalsTitle, "Другие цели", "Other goals"),
            (GoalsContent.waitingTitle, "Ждут решения", "Waiting for a decision"),
            (GoalsContent.addTitle, "Цель", "Goal"),
            (GoalsContent.addLabel, "Добавить цель", "Add goal"),
            (GoalsContent.removeTitle, "Убрать", "Remove"),
            (GoalsContent.heroHint, "Открывает цель", "Opens the goal"),
            (GoalsContent.newGoalHint, "Открывает новую цель", "Opens a new goal"),
            (GoalsContent.wishHint, "Открывает покупку, чтобы решить", "Opens the purchase to decide on it"),
            (GoalsContent.decidedHint, "Показывает или прячет решённое", "Shows or hides what was decided"),
            (GoalPurchasePlan.buyTitle, "Купить", "Buy"),
        ]
        for (resource, russian, english) in lines {
            #expect(resource.text(in: F.ru) == russian)
            #expect(resource.text(in: F.en) == english)
        }
    }
}
