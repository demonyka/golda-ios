import Foundation
import Testing

@testable import Golda

/// The app's own catalog carries every line in Russian and in English (CLAUDE.md: both, in one
/// change), plural lines included, as the build compiles them into the two languages' tables.
@Suite struct LocalizableStringsTests {
    /// The compiled table of [language]: plain lines from `.strings`, plural ones from `.stringsdict`.
    private func keys(_ language: String) throws -> (plain: [String: String], plural: Set<String>) {
        let bundle = Bundle.main
        let strings = bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: language)
            .flatMap { NSDictionary(contentsOfFile: $0) as? [String: String] } ?? [:]
        let plurals = bundle.path(forResource: "Localizable", ofType: "stringsdict", inDirectory: nil, forLocalization: language)
            .flatMap { NSDictionary(contentsOfFile: $0) as? [String: Any] } ?? [:]
        return (strings, Set(plurals.keys))
    }

    @Test func bothLanguagesCarryTheSameKeys() throws {
        let english = try keys("en"), russian = try keys("ru")
        #expect(!english.plain.isEmpty)
        #expect(Set(english.plain.keys) == Set(russian.plain.keys))
        #expect(english.plural == russian.plural)
        #expect(english.plural.isSuperset(of: ["%lld days to payday", "%lld days"]))
    }

    @Test func russianIsReallyRussian() throws {
        // Keys whose Russian is the same as the English on purpose: none so far.
        for (key, value) in try keys("ru").plain {
            #expect(!value.isEmpty, "ru: \(key)")
            #expect(value.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }, "ru value of “\(key)” has no Cyrillic: \(value)")
        }
    }

    @Test func homeLinesResolveInBothLanguages() {
        let ru = Locale(identifier: "ru"), en = Locale(identifier: "en")
        #expect(HomeHero.caption.text(in: ru) == "Можно сегодня")
        #expect(HomeHero.caption.text(in: en) == "Safe to spend today")
        for key in Symbols.categoryKeys {
            let russian = CategoryName.resource(key).text(in: ru), english = CategoryName.resource(key).text(in: en)
            #expect(russian != english, "category \(key) is not translated")
        }
    }
}
