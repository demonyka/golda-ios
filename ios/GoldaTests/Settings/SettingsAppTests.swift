import Foundation
import GoldaCore
import GoldaData
import Testing

@testable import Golda

/// The settings' intents over the real app model, on the made-up person's books: currencies that
/// reach the big numbers at once, the key and its hook, the backup there and back, and the wipe.
@MainActor @Suite(.timeLimit(.minutes(1))) struct SettingsAppTests {
    let harness: AppHarness

    init() throws {
        harness = try AppHarness()
    }

    var model: AppModel { harness.model }

    private func samples() async throws -> AppData {
        await model.start(command: .samples, profileName: "Личный")
        return try await harness.data()
    }

    // MARK: Where I am

    @Test func theMainCurrencyMovesTheBigNumbersAtOnce() async throws {
        let before = try await samples()
        #expect(before.base.code == "RUB")

        model.setMainCurrency("GEL")

        // Applied directly, as a switch on screen needs, not after the store's stream.
        #expect(model.device.baseCurrency == "GEL")
        #expect(model.data?.base.code == "GEL")
        #expect(harness.device.current.baseCurrency == "GEL")
    }

    @Test func theLocalCurrencyIsThePhones() async throws {
        _ = try await samples()

        model.setLocalCurrency("USD")

        #expect(model.data?.settings.localCurrency == "USD")
        #expect(harness.device.current.localCurrency == "USD")
        // The profile is not touched: currencies are this phone's (D16).
        #expect(model.data?.settings.markup == model.activeProfile?.settings.markup)
    }

    @Test func hidingTheMainAndLocalCurrencyFallsBackToRubles() async throws {
        let data = try await samples()
        #expect(data.settings.displayCurrencies == ["RUB", "USD", "GEL"])
        #expect(data.settings.localCurrency == "GEL")
        model.setMainCurrency("GEL")

        model.toggleShownCurrency("GEL")

        #expect(model.device.displayCurrencies == ["RUB", "USD"])
        #expect(model.device.localCurrency == "RUB")
        #expect(model.data?.base.code == "RUB")

        model.toggleShownCurrency("THB")
        model.toggleShownCurrency("RUB")
        #expect(model.data?.settings.displayCurrencies == ["RUB", "USD", "THB"])
    }

    // MARK: Voice

    @Test func aSavedKeyIsKeptTrimmedAndWakesTheVoiceQueue() async throws {
        _ = try await samples()
        var wakeUps = 0
        model.onGeminiKeyChanged = { wakeUps += 1 }
        #expect(!model.hasGeminiKey)

        try model.saveGeminiKey("  AIza-test \n")

        #expect(model.hasGeminiKey)
        #expect(harness.environment.secrets.read(SecretKey.gemini) == "AIza-test")
        #expect(wakeUps == 1)

        try model.removeGeminiKey()
        #expect(!model.hasGeminiKey)
        // A blank key removes, as on Android, and nothing waits for no key.
        try model.saveGeminiKey("AIza-again")
        try model.saveGeminiKey("   ")
        #expect(!model.hasGeminiKey)
        #expect(wakeUps == 2)
    }

    @Test func theHookBelongsToItsModel() async throws {
        let other = try AppHarness()
        var calls: [String] = []
        model.onGeminiKeyChanged = { calls.append("this") }
        #expect(other.model.onGeminiKeyChanged == nil)

        try other.model.saveGeminiKey("AIza-other")
        try model.saveGeminiKey("AIza-this")

        #expect(calls == ["this"])
        model.onGeminiKeyChanged = nil
        try model.saveGeminiKey("AIza-this")
        #expect(calls == ["this"])
    }

    @Test func theModelTheConsentAndTheReminderAreKeptOnThePhone() async throws {
        _ = try await samples()
        #expect(model.device.geminiModel == GeminiModelText.defaultName)
        #expect(!model.device.voiceConsent)
        #expect(model.device.reconcileReminder)

        model.setGeminiModel("  gemini-4-pro ")
        model.setGeminiModel("   ")
        model.setVoiceConsent(true)
        model.setReconcileReminder(false)

        let stored = harness.device.current
        #expect(stored.geminiModel == "gemini-4-pro")
        #expect(stored.voiceConsent)
        #expect(!stored.reconcileReminder)
        #expect(model.device == stored)
    }

    // MARK: Backup

    @Test func aBackupComesBackWholeAndTheKeyAndConsentStay() async throws {
        let data = try await samples()
        try model.saveGeminiKey("AIza-kept")
        let file = try await model.exportBackup()
        let accounts = data.accounts.count, operations = data.operations.count

        // Changes after the backup: an account gone, the main currency moved, consent given.
        let cash = try #require(data.accounts.first { $0.type == .cash })
        try await model.deleteAccount(cash.id)
        await eventually { model.data?.accounts.count == accounts - 1 }
        model.setMainCurrency("USD")
        model.setVoiceConsent(true)

        let summary = try await model.restoreBackup(file)

        #expect(summary.profiles == 1)
        #expect(summary.accounts == accounts)
        #expect(summary.operations == operations)
        await eventually { model.data?.accounts.count == accounts && model.data?.operations.count == operations }
        await eventually { model.device.baseCurrency == "RUB" }
        #expect(model.data?.base.code == "RUB")
        #expect(model.hasGeminiKey)
        #expect(model.device.voiceConsent)
        #expect(RestoreMessage(summary).text(in: Locale(identifier: "ru")).hasPrefix("Восстановлено: \(accounts) сч"))
    }

    @Test func aFileThatDoesNotFitChangesNothing() async throws {
        let data = try await samples()
        let accounts = data.accounts.count
        model.setMainCurrency("GEL")

        for file in [Data("{ not json".utf8), Data(#"{"version": 99}"#.utf8), Data(#"{"version": 2, "profiles": []}"#.utf8)] {
            await #expect(throws: BackupError.self) { try await model.restoreBackup(file) }
        }

        #expect(model.data?.accounts.count == accounts)
        #expect(model.device.baseCurrency == "GEL")
        #expect(try await harness.environment.database.read { try $0.profiles() }.count == 1)
    }

    // MARK: Erase

    @Test func erasingEverythingGoesBackToOnboardingAndTakesTheKey() async throws {
        _ = try await samples()
        try model.saveGeminiKey("AIza-gone")
        model.setVoiceConsent(true)

        try await model.eraseEverything()

        #expect(model.phase.isOnboarding)
        #expect(!model.hasGeminiKey)
        #expect(model.device == DeviceSettings())
        await eventually { model.profiles.isEmpty }
        // Only the built-in rates are left.
        #expect(try await harness.environment.database.read { try $0.rates() }.map(\.code).sorted() == ["GEL", "RUB", "THB", "USD"])
    }
}
