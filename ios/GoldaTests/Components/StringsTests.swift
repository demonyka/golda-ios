import Foundation
import Testing

@testable import Golda

/// Every line of the components exists in Russian and in English (CLAUDE.md: both, in one change).
@Suite struct ComponentStringsTests {
    private func table(_ language: String) -> [String: String]? {
        guard let path = Bundle.main.path(forResource: "Components", ofType: "strings", inDirectory: nil, forLocalization: language) else { return nil }
        return NSDictionary(contentsOfFile: path) as? [String: String]
    }

    @Test func bothLanguagesCarryTheSameKeys() throws {
        let english = try #require(table("en"))
        let russian = try #require(table("ru"))
        #expect(!english.isEmpty)
        #expect(Set(english.keys) == Set(russian.keys))
    }

    @Test func noValueIsEmptyAndRussianIsReallyRussian() throws {
        let english = try #require(table("en"))
        let russian = try #require(table("ru"))
        for (key, value) in english {
            #expect(!value.isEmpty, "en: \(key)")
        }
        for (key, value) in russian {
            #expect(!value.isEmpty, "ru: \(key)")
            #expect(value.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }, "ru value of “\(key)” has no Cyrillic: \(value)")
        }
    }

    @Test func theKeysTheCodeAsksForAreInTheTable() throws {
        let english = try #require(table("en"))
        let used = ["Say it", "Working it out…", "Listening. Tap when done", "Starts recording a note", "Undo"]
        for key in used {
            #expect(english[key] != nil, "missing “\(key)”")
        }
        #expect(Set(used) == Set(english.keys), "a key in the table that no component uses")
    }

    @Test func theMicSaysItInBothLanguages() throws {
        let russian = try #require(table("ru"))
        #expect(russian["Say it"] == "Сказать")
        #expect(russian["Listening. Tap when done"] == "Слушаю. Нажми, когда закончишь")
        #expect(russian["Working it out…"] == "Разбираю…")
        #expect(russian["Undo"] == "Отменить")
    }
}
