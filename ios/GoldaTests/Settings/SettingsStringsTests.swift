import Foundation
import Testing
import UIKit

@testable import Golda

/// The settings' table carries every line in Russian and in English (CLAUDE.md: both, in one
/// change), plural lines included, as the build compiles them; and every line the code asks for is
/// in it.
@Suite struct SettingsStringsTests {
    private func table(_ language: String) -> (plain: [String: String], plural: Set<String>) {
        let bundle = Bundle.main
        let strings = bundle.path(forResource: "Settings", ofType: "strings", inDirectory: nil, forLocalization: language)
            .flatMap { NSDictionary(contentsOfFile: $0) as? [String: String] } ?? [:]
        let plurals = bundle.path(forResource: "Settings", ofType: "stringsdict", inDirectory: nil, forLocalization: language)
            .flatMap { NSDictionary(contentsOfFile: $0) as? [String: Any] } ?? [:]
        return (strings, Set(plurals.keys))
    }

    @Test func bothLanguagesCarryTheSameKeys() {
        let english = table("en"), russian = table("ru")
        #expect(english.plain.count > 60)
        #expect(Set(english.plain.keys) == Set(russian.plain.keys))
        #expect(english.plural == russian.plural)
        #expect(english.plural == ["%lld profiles", "%lld accounts", "%lld operations"])
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

    /// A line missing from the table would show its English key in Russian too.
    @Test func everyLineTheScreenAsksForIsTranslated() {
        let ru = Locale(identifier: "ru"), en = Locale(identifier: "en")
        #expect(SettingsText.all.count == table("en").plain.count - 6, "a plain line is not in `SettingsText.all`")
        for line in SettingsText.all {
            let english = line.text(in: en), russian = line.text(in: ru)
            #expect(english != russian, "“\(english)” is not translated")
        }
        #expect(SettingsText.title.text(in: ru) == "Настройки")
        #expect(SettingsText.whereIAm.text(in: ru) == "Где я")
        #expect(SettingsText.ratesUpdated.text(in: ru) == "Курсы обновлены")
        #expect(SettingsText.ratesFailed.text(in: ru) == "Не получилось, нет сети?")
        #expect(SettingsText.eraseEverything.text(in: ru) == "Стереть всё")
        #expect(SettingsText.restoreWarning.text(in: ru) == "Всё, что сейчас в Golda, заменится содержимым файла. Ключ Gemini останется.")
    }

    /// With sync, erasing deletes the profiles' zones and restoring overwrites them, so other
    /// devices and the people a profile is shared with lose or see it change too: the warning says
    /// so, in both languages.
    @Test func eraseAndRestoreWarnThatICloudAndSharedProfilesChangeToo() {
        let ru = Locale(identifier: "ru"), en = Locale(identifier: "en")
        for (warning, sync) in [(SettingsText.eraseWarning, SettingsText.eraseSyncWarning), (SettingsText.restoreWarning, SettingsText.restoreSyncWarning)] {
            #expect(SettingsText.message(warning, sync: sync, syncs: false, in: ru) == warning.text(in: ru))
            let synced = SettingsText.message(warning, sync: sync, syncs: true, in: ru)
            #expect(synced.hasPrefix(warning.text(in: ru)))
            #expect(synced.contains("iCloud"))
            #expect(synced.contains("поделились"))
            #expect(SettingsText.message(warning, sync: sync, syncs: true, in: en).contains("shared them with"))
        }
    }

    @Test func everySymbolExists() {
        for name in SettingsSymbols.all {
            #expect(UIImage(systemName: name) != nil, "no SF Symbol “\(name)”")
        }
    }
}
