import Foundation
import Testing
import UIKit

@testable import Golda

/// The profile screens' table carries every line in Russian and in English (CLAUDE.md: both, in one
/// change), plural lines included, as the build compiles them; and their glyphs exist.
@MainActor @Suite struct ProfilesStringsTests {
    private func table(_ language: String) -> (plain: [String: String], plural: Set<String>) {
        let bundle = Bundle.main
        let strings = bundle.path(forResource: "Profiles", ofType: "strings", inDirectory: nil, forLocalization: language)
            .flatMap { NSDictionary(contentsOfFile: $0) as? [String: String] } ?? [:]
        let plurals = bundle.path(forResource: "Profiles", ofType: "stringsdict", inDirectory: nil, forLocalization: language)
            .flatMap { NSDictionary(contentsOfFile: $0) as? [String: Any] } ?? [:]
        return (strings, Set(plurals.keys))
    }

    @Test func bothLanguagesCarryTheSameKeys() {
        let english = table("en"), russian = table("ru")
        #expect(english.plain.count > 50)
        #expect(Set(english.plain.keys) == Set(russian.plain.keys))
        #expect(english.plural == russian.plural)
        #expect(english.plural == ["%lld accounts", "%lld operations", "%lld goals", "%lld wishlist items", "%lld payments"])
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

    @Test func theScreensAreNamedInBothLanguages() {
        let ru = Locale(identifier: "ru"), en = Locale(identifier: "en")
        #expect(ProfilesList.title.text(in: ru) == "Профили")
        #expect(ProfilesList.title.text(in: en) == "Profiles")
        #expect(ProfileScreen.makeActiveTitle.text(in: ru) == "Сделать активным")
        #expect(ProfileScreen.sharingTitle.text(in: ru) == "Общий доступ")
        #expect(ProfileScreen.soonTitle.text(in: ru) == "скоро")
        #expect(ProfileScreen.soonTitle.text(in: en) == "soon")
        #expect(ProfileScreen.paymentsTitle.text(in: ru) == "Платежи")
        #expect(ProfileIncome.hourNetTitle.text(in: ru) == "Час на руки")
        #expect(MarkupForm.title.text(in: ru) == "Наценка к ЦБ")
        #expect(ProfileNameRequest.create.title.text(in: ru) == "Новый профиль")
        #expect(ProfileNameRequest.rename(current: "Семья").confirmTitle.text(in: ru) == "Сохранить")
    }

    @Test func everyGlyphExists() {
        for name in ProfileSymbols.allNames {
            #expect(UIImage(systemName: name) != nil, "\(name)")
        }
    }
}
