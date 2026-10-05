import Foundation
import GoldaCore
import GoldaData
import Testing

@testable import Golda

/// What the settings screen shows and what its choices change, without a screen: the currency
/// lists with `toggleDisplayCurrency`'s fallbacks, the rate rows, and the lines built from values.
@Suite struct SettingsContentTests {
    private let ru = Locale(identifier: "ru"), en = Locale(identifier: "en")

    private func device(shown: [String], local: String = "RUB", main: String = "RUB") -> DeviceSettings {
        DeviceSettings(displayCurrencies: shown, localCurrency: local, baseCurrency: main)
    }

    // MARK: Where I am

    @Test func currenciesAreWrittenBySymbolAndCode() {
        #expect(SettingsCurrencies.label("GEL") == "₾ GEL")
        #expect(SettingsCurrencies.label("RUB") == "₽ RUB")
        // No symbol of its own: the code alone, as Android's `currencyLabel`.
        #expect(SettingsCurrencies.label("AED") == "AED")
        #expect(SettingsCurrencies.symbols(["RUB", "USD", "GEL", "AED"]) == "₽ $ ₾ AED")
    }

    @Test func theLocalAndMainCurrencyArePickedOutOfTheShownOnes() {
        let samples = device(shown: ["RUB", "USD", "GEL"], local: "GEL")
        #expect(SettingsCurrencies.pickOptions(samples, selected: "GEL") == ["RUB", "USD", "GEL"])
        // One that is not shown (an old file can say so) still gets its row, last.
        #expect(SettingsCurrencies.pickOptions(device(shown: ["RUB", "USD"]), selected: "THB") == ["RUB", "USD", "THB"])
        #expect(SettingsCurrencies.pickOptions(device(shown: ["RUB", "USD", "USD"]), selected: "USD") == ["RUB", "USD"])
    }

    @Test func everyCurrencyHasASwitchInOneFixedOrderAndTheRubleIsLocked() {
        let samples = device(shown: ["RUB", "GEL", "USD"])
        let sections = SettingsCurrencies.shownSections(samples, matching: "", in: ru)
        #expect(sections.popular == Currencies.popular)
        #expect(sections.others == CurrencySections(matching: "", in: ru).others)
        let options = (sections.popular + sections.others).map { SettingsCurrencies.option($0, samples) }
        #expect(options.filter(\.isOn).map(\.code) == ["RUB", "USD", "GEL"])
        #expect(options.filter(\.isLocked).map(\.code) == ["RUB"])

        // A shown currency outside the catalogue comes last, so it can be turned off.
        let odd = device(shown: ["RUB", "BGN"])
        let last = SettingsCurrencies.shownSections(odd, matching: "", in: ru).others.last
        #expect(last.map { SettingsCurrencies.option($0, odd) } == SettingsCurrencies.ShownOption(code: "BGN", isOn: true, isLocked: false))
    }

    @Test func theSwitchesAreFoundByNameOrCode() {
        let samples = device(shown: ["RUB", "USD"])
        let pesos = SettingsCurrencies.shownSections(samples, matching: "ARS", in: en)
        #expect(pesos.popular.isEmpty)
        #expect(pesos.others == ["ARS"])
        #expect(SettingsCurrencies.shownSections(samples, matching: "доллар", in: ru).popular == ["USD"])
    }

    @Test func onboardingSwitchesThePopularOnesAndWhateverElseIsShown() {
        #expect(SettingsCurrencies.inlineOptions(device(shown: ["RUB", "USD"])).map(\.code) == Currencies.popular)
        let pesos = SettingsCurrencies.inlineOptions(device(shown: ["RUB", "USD", "MXN", "ARS"]))
        #expect(pesos.map(\.code) == Currencies.popular + ["ARS", "MXN"])
        #expect(pesos.suffix(2).map(\.isOn) == [true, true])
    }

    @Test func showingACurrencyPutsItInTheCatalogueOrder() {
        let shown = SettingsCurrencies.toggling("EUR", in: device(shown: ["RUB", "GEL", "USD"], local: "GEL", main: "USD"))
        #expect(shown.displayCurrencies == ["RUB", "USD", "EUR", "GEL"])
        #expect(shown.localCurrency == "GEL")
        #expect(shown.baseCurrency == "USD")
        let pesos = SettingsCurrencies.toggling("ARS", in: shown)
        #expect(pesos.displayCurrencies == ["RUB", "USD", "EUR", "GEL", "ARS"])
    }

    @Test func theMainCurrencyCanBeARareOne() {
        // Picked out of the shown ones, so a peso turned on can be the main currency at once.
        let pesos = SettingsCurrencies.toggling("ARS", in: device(shown: ["RUB", "USD"]))
        #expect(SettingsCurrencies.pickOptions(pesos, selected: pesos.baseCurrency) == ["RUB", "USD", "ARS"])
    }

    @Test func hidingTheLocalOrMainCurrencyFallsBackToRubles() {
        let before = device(shown: ["RUB", "USD", "GEL"], local: "GEL", main: "GEL")
        let hidden = SettingsCurrencies.toggling("GEL", in: before)
        #expect(hidden.displayCurrencies == ["RUB", "USD"])
        #expect(hidden.localCurrency == "RUB")
        #expect(hidden.baseCurrency == "RUB")

        let mainOnly = SettingsCurrencies.toggling("USD", in: device(shown: ["RUB", "USD", "GEL"], local: "GEL", main: "USD"))
        #expect(mainOnly.localCurrency == "GEL")
        #expect(mainOnly.baseCurrency == "RUB")
    }

    @Test func theRubleCannotBeHiddenAndNothingElseOfTheDeviceMoves() {
        var before = device(shown: ["RUB", "USD"], local: "USD")
        before.geminiModel = "gemini-next"
        before.voiceConsent = true
        #expect(SettingsCurrencies.toggling("RUB", in: before) == before)
        let after = SettingsCurrencies.toggling("THB", in: before)
        #expect(after.geminiModel == "gemini-next")
        #expect(after.voiceConsent)
    }

    // MARK: Rates

    private let fallbackRates = Dictionary(uniqueKeysWithValues: CbrRatesSource.fallback.map { ($0.code, $0.rubPerUnit) })

    @Test func aRateRowForEveryShownCurrencyButTheRuble() {
        let settings = Settings(displayCurrencies: ["RUB", "USD", "GEL"], markup: 0.10)
        let rows = RateRow.rows(settings, Rates(fallbackRates, markup: 0.10))
        // 83,2454 × 1,1 = 91,56994 and 31,9597 × 1,1 = 35,15567, the rates every amount is shown at.
        #expect(rows == [
            RateRow(code: "USD", shown: "1 $ = 91,57 ₽", official: "83,25"),
            RateRow(code: "GEL", shown: "1 ₾ = 35,16 ₽", official: "31,96"),
        ])
    }

    @Test func aCurrencyWithoutARateHasNoRow() {
        let settings = Settings(displayCurrencies: ["RUB", "EUR", "THB", "THB"], markup: 0)
        let rows = RateRow.rows(settings, Rates(fallbackRates, markup: 0))
        #expect(rows.map(\.code) == ["THB"])
        #expect(rows.first?.shown == "1 ฿ = 2,47 ₽")
        #expect(RateRow.rows(Settings(displayCurrencies: ["RUB"]), Rates(fallbackRates, markup: 0)).isEmpty)
    }

    @Test func theRatesDayInBothLanguages() {
        #expect(RatesDay.text("2026-10-02", locale: ru) == "ЦБ на 2 октября")
        #expect(RatesDay.text("2026-10-02", locale: en) == "CBR of October 2")
        #expect(RatesDay.text(nil, locale: en) == nil)
        #expect(RatesDay.text("yesterday", locale: en) == "CBR of yesterday")
    }

    @Test func theOfficialRateAndTheMarkupNote() {
        #expect(SettingsText.official("83,25").text(in: ru) == "ЦБ 83,25")
        #expect(SettingsText.official("83,25").text(in: en) == "CBR 83,25")
        #expect(SettingsText.markupNote(Fmt.percent(0.10)).text(in: ru) == "По курсу ЦБ с наценкой профиля, 10 %.")
        #expect(SettingsText.markupNote(Fmt.percent(0.025)).text(in: en) == "At the CBR rate plus the profile's markup, 2,5 %.")
    }

    // MARK: Data

    @Test func theRestoreMessageCountsInRussianForms() {
        #expect(RestoreMessage(profiles: 1, accounts: 7, operations: 21).text(in: ru) == "Восстановлено: 7 счетов, 21 операция")
        #expect(RestoreMessage(profiles: 1, accounts: 1, operations: 2).text(in: ru) == "Восстановлено: 1 счёт, 2 операции")
        #expect(RestoreMessage(profiles: 1, accounts: 3, operations: 15).text(in: ru) == "Восстановлено: 3 счёта, 15 операций")
        #expect(RestoreMessage(profiles: 1, accounts: 0, operations: 0).text(in: ru) == "Восстановлено: 0 счетов, 0 операций")
        // More than one profile: they are counted too.
        #expect(RestoreMessage(profiles: 2, accounts: 22, operations: 104).text(in: ru) == "Восстановлено: 2 профиля, 22 счёта, 104 операции")
        #expect(RestoreMessage(profiles: 5, accounts: 11, operations: 1).text(in: ru) == "Восстановлено: 5 профилей, 11 счетов, 1 операция")
    }

    @Test func theRestoreMessageInEnglish() {
        #expect(RestoreMessage(profiles: 1, accounts: 1, operations: 1).text(in: en) == "Restored: 1 account, 1 operation")
        #expect(RestoreMessage(profiles: 1, accounts: 7, operations: 21).text(in: en) == "Restored: 7 accounts, 21 operations")
        #expect(RestoreMessage(profiles: 3, accounts: 2, operations: 0).text(in: en) == "Restored: 3 profiles, 2 accounts, 0 operations")
    }

    @Test func theBackupFileIsNamedByItsDay() {
        #expect(BackupFile.name(on: LocalDate(2026, 10, 3)) == "golda-2026-10-03.json")
        #expect(BackupFile.name(on: LocalDate(2027, 1, 9)) == "golda-2027-01-09.json")
    }

    // MARK: Voice

    @Test func theDefaultModelIsMarked() {
        #expect(GeminiModelText.defaultName == "gemini-3.5-flash-lite")
        #expect(GeminiModelText.row("gemini-3.5-flash-lite", in: ru) == "gemini-3.5-flash-lite · по умолчанию")
        #expect(GeminiModelText.row("gemini-3.5-flash-lite", in: en) == "gemini-3.5-flash-lite · default")
        #expect(GeminiModelText.row("gemini-4-pro", in: ru) == "gemini-4-pro")
        #expect(SettingsText.backTo("gemini-3.5-flash-lite").text(in: ru) == "Вернуть gemini-3.5-flash-lite")
    }

    @Test func aModelNameIsTrimmedAndABlankOneIsNotSaved() {
        #expect(GeminiModelText.saveable("  gemini-4-pro \n") == "gemini-4-pro")
        #expect(GeminiModelText.saveable("   ") == nil)
        #expect(GeminiModelText.saveable("") == nil)
    }

    @Test func theKeyStateInBothLanguages() {
        #expect(SettingsText.keySaved.text(in: ru) == "Сохранён")
        #expect(SettingsText.keyMissing.text(in: ru) == "Нет")
        #expect(SettingsText.keySaved.text(in: en) == "Saved")
        #expect(SettingsText.keyMissing.text(in: en) == "None")
    }

    // MARK: About and language

    @Test func theVersionWithItsBuild() {
        #expect(AppVersion.text(["CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1"]) == "0.1.0 (1)")
        #expect(AppVersion.text(["CFBundleShortVersionString": "1.0.0"]) == "1.0.0")
        #expect(AppVersion.text(nil) == "?")
        // The app’s own: the project sets 1.0.3, build 4.
        #expect(AppVersion.text(Bundle.main.infoDictionary) == "1.0.3 (4)")
    }

    @Test func theLanguageIsNamedInItself() {
        #expect(AppLanguageName.text(ru) == "Русский")
        #expect(AppLanguageName.text(en) == "English")
        #expect(AppLanguageName.text(Locale(identifier: "ru_GE")) == "Русский")
    }

    @Test func theLicencesNameTheOriginalAuthorAndGRDB() {
        let golda = Licence.all.first { $0.name == "Golda" }
        #expect(golda?.text.contains("Copyright (c) 2026 Shamil Aminov") == true)
        #expect(golda?.text.contains("Permission is hereby granted, free of charge") == true)
        let grdb = Licence.all.first { $0.name == "GRDB.swift" }
        #expect(grdb?.text.hasPrefix("Copyright (C) 2015-2025 Gwendal Roué") == true)
        // No links: the page says it all.
        #expect(Licence.all.allSatisfy { !$0.text.contains("http") })
        #expect(SettingsText.goldaCredit.text(in: ru).contains("Шамиля Аминова"))
    }
}
