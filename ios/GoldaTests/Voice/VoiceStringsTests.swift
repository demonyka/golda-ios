import Foundation
import Testing
import UIKit

@testable import Golda

/// Every line of the voice exists in Russian and in English (CLAUDE.md: both, in one change), and
/// the microphone's permission prompt is translated.
@MainActor @Suite struct VoiceStringsTests {
    private func table(_ name: String, _ language: String) -> [String: String]? {
        guard let path = Bundle.main.path(forResource: name, ofType: "strings", inDirectory: nil, forLocalization: language) else { return nil }
        return NSDictionary(contentsOfFile: path) as? [String: String]
    }

    /// Lines whose Russian is the English on purpose: Gemini's own words follow its name.
    private let sameInBothLanguages: Set<String> = ["Gemini: %@"]

    @Test func bothLanguagesCarryTheSameKeys() throws {
        let english = try #require(table("Voice", "en"))
        let russian = try #require(table("Voice", "ru"))
        #expect(!english.isEmpty)
        #expect(Set(english.keys) == Set(russian.keys))
    }

    @Test func noValueIsEmptyAndRussianIsReallyRussian() throws {
        let russian = try #require(table("Voice", "ru"))
        for (key, value) in russian where !sameInBothLanguages.contains(key) {
            #expect(value.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }, "ru value of “\(key)” has no Cyrillic: \(value)")
        }
        for (key, value) in try #require(table("Voice", "en")) {
            #expect(!value.isEmpty, "en: \(key)")
        }
    }

    /// Each line the voice asks for is in the table: a missing key would come back as itself in both
    /// languages.
    @Test func everyLineTheVoiceUsesResolves() {
        let ru = Locale(identifier: "ru"), en = Locale(identifier: "en")
        typealias S = VoiceNotice.Strings
        let lines: [LocalizedStringResource] = [
            S.settings, S.add, S.ok, S.saved, S.noKey, S.offline, S.lost, S.profileGone, S.malformedAnswer, S.storage,
            S.micBusy, S.micDenied, S.misunderstood("x"), S.late("x"), S.profile("x"), S.hoursOfWork("1"), S.leftToday("1 ₽"),
            S.overBudget("1 ₽"),
            VoiceConsentScreen.title, VoiceConsentScreen.headline, VoiceConsentScreen.intro, VoiceConsentScreen.agreeTitle,
            VoiceConsentScreen.notNowTitle,
            LocalizedStringResource("Purchase", table: "Voice"),
        ] + VoiceConsentScreen.points.flatMap { [$0.title, $0.text] }
        for line in lines {
            #expect(line.text(in: ru) != line.text(in: en), "“\(line.key)” is not translated")
        }
    }

    @Test func theConsentScreenNamesTheProviderAndItsButtons() {
        let ru = Locale(identifier: "ru")
        #expect(VoiceConsentScreen.headline.text(in: ru) == "Голос уходит в Google Gemini")
        #expect(VoiceConsentScreen.agreeTitle.text(in: ru) == "Согласен")
        #expect(VoiceConsentScreen.notNowTitle.text(in: ru) == "Не сейчас")
        #expect(VoiceConsentScreen.agreeTitle.text(in: Locale(identifier: "en")) == "Agree")
        #expect(VoiceConsentScreen.points.count == 4)
    }

    @Test func theConsentScreenSymbolsExist() {
        for symbol in VoiceConsentScreen.points.map(\.symbol) + [VoiceConsentScreen.headerSymbol] {
            #expect(UIImage(systemName: symbol) != nil, "no SF Symbol \(symbol)")
        }
    }

    @Test func theMicrophonePromptIsInBothLanguages() throws {
        let russian = try #require(table("InfoPlist", "ru")?["NSMicrophoneUsageDescription"])
        #expect(russian.contains("Google Gemini"))
        #expect(russian.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) })
        let english = try #require(table("InfoPlist", "en")?["NSMicrophoneUsageDescription"])
        #expect(english.contains("Google Gemini"))
    }
}
