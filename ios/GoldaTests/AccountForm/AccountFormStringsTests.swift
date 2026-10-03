import Foundation
import Testing

@testable import Golda

/// The account form's and the debt screens' table carries every line in Russian and in English
/// (CLAUDE.md: both, in one change), plural lines included, as the build compiles them.
@Suite struct AccountFormStringsTests {
    private func table(_ language: String) -> (plain: [String: String], plural: Set<String>) {
        let bundle = Bundle.main
        let strings = bundle.path(forResource: "AccountForm", ofType: "strings", inDirectory: nil, forLocalization: language)
            .flatMap { NSDictionary(contentsOfFile: $0) as? [String: String] } ?? [:]
        let plurals = bundle.path(forResource: "AccountForm", ofType: "stringsdict", inDirectory: nil, forLocalization: language)
            .flatMap { NSDictionary(contentsOfFile: $0) as? [String: Any] } ?? [:]
        return (strings, Set(plurals.keys))
    }

    @Test func bothLanguagesCarryTheSameKeys() {
        let english = table("en"), russian = table("ru")
        #expect(english.plain.count > 50)
        #expect(Set(english.plain.keys) == Set(russian.plain.keys))
        #expect(english.plural == russian.plural)
        #expect(english.plural == ["%lld months", "%lld months sooner"])
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

    /// A percent sign in a catalog value would be read as the start of a format.
    @Test func noLineHasAStrayPercentSign() {
        for language in ["en", "ru"] {
            for (key, value) in table(language).plain {
                let stripped = value.replacingOccurrences(of: "%@", with: "").replacingOccurrences(of: "%lld", with: "")
                #expect(!stripped.contains("%"), "\(language): \(key)")
            }
        }
    }

    @Test func monthsTakeTheRussianForms() {
        let ru = Locale(identifier: "ru"), en = Locale(identifier: "en")
        #expect([1, 2, 5, 11, 21, 22, 48].map { DebtDetailsModel.months($0, in: ru) } == [
            "1 месяц", "2 месяца", "5 месяцев", "11 месяцев", "21 месяц", "22 месяца", "48 месяцев",
        ])
        #expect([1, 2, 48].map { DebtDetailsModel.months($0, in: en) } == ["1 month", "2 months", "48 months"])
    }
}
