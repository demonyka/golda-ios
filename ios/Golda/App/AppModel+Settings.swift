import Foundation
import GoldaCore
import GoldaData
import ObjectiveC

/// What the settings screen changes: this phone's settings (D16), the Gemini key, the backup file and
/// "Стереть всё". Like the other intents they only pass the change on; the store, the Keychain,
/// `Backups` and the repository decide.
extension AppModel {
    // MARK: Where I am

    func setLocalCurrency(_ code: String) {
        changeDevice { $0.localCurrency = code }
    }

    func setMainCurrency(_ code: String) {
        changeDevice { $0.baseCurrency = code }
    }

    /// Shows or hides [code] among the shown currencies, with `toggleDisplayCurrency`'s fallbacks.
    func toggleShownCurrency(_ code: String) {
        changeDevice { $0 = SettingsCurrencies.toggling(code, in: $0) }
    }

    func setReconcileReminder(_ on: Bool) {
        changeDevice { $0.reconcileReminder = on }
    }

    // MARK: Voice

    /// Settings keep only whether a key is there; the key itself stays in the Keychain.
    var hasGeminiKey: Bool {
        environment.secrets.read(SecretKey.gemini) != nil
    }

    /// Keeps [key] (trimmed) in the Keychain; a blank one removes it. A stored key runs
    /// `onGeminiKeyChanged`, since notes recorded without one are waiting for it.
    func saveGeminiKey(_ key: String) throws {
        try environment.secrets.write(key, for: SecretKey.gemini)
        if hasGeminiKey { onGeminiKeyChanged?() }
    }

    func removeGeminiKey() throws {
        try environment.secrets.delete(SecretKey.gemini)
    }

    /// The model voice notes go to; a blank name changes nothing.
    func setGeminiModel(_ name: String) {
        guard let name = GeminiModelText.saveable(name) else { return }
        changeDevice { $0.geminiModel = name }
    }

    /// The consent of D9: without it no recording leaves the phone.
    func setVoiceConsent(_ on: Bool) {
        changeDevice { $0.voiceConsent = on }
    }

    /// Runs on the main actor after a Gemini key is stored. The voice stage sets it to work through
    /// the notes that waited for a key.
    var onGeminiKeyChanged: (() -> Void)? {
        get { settingsHooks.onGeminiKeyChanged }
        set { settingsHooks.onGeminiKeyChanged = newValue }
    }

    // MARK: Backup

    /// Every profile, the rates and the settings worth carrying, as one file; never the key.
    func exportBackup() async throws -> Data {
        try await backups.export()
    }

    /// Replaces everything with the file. A file that does not fit throws before anything changes.
    /// The key and the voice consent stay.
    func restoreBackup(_ file: Data) async throws -> BackupSummary {
        let summary = try await backups.import(file, personalProfileName: AppModel.firstProfileName)
        // The rates came with the file, and the database does not observe them.
        await reloadRates()
        return summary
    }

    // MARK: Erase

    /// Everything goes: profiles with their books, this phone's settings and the API keys (D28). The
    /// app is back at the welcome screen once the observers see it.
    func eraseEverything() async throws {
        do {
            try await environment.repository.resetAll()
        } catch {
            // The books and settings may be gone even when the Keychain refused; show what is left.
            await reloadRates()
            applyDeviceSettings()
            throw error
        }
        // Only the built-in rates are left, and the database does not observe rates.
        await reloadRates()
        applyDeviceSettings()
    }

    // MARK: Plumbing

    /// Writes [change] and applies it at once, as a profile switch does, so a switch on screen does
    /// not flick back while the store's stream catches up.
    private func changeDevice(_ change: (inout DeviceSettings) -> Void) {
        environment.deviceSettings.update(change)
        applyDeviceSettings()
    }

    /// Built on demand: it holds nothing but what the environment already has.
    private var backups: Backups {
        Backups(database: environment.database, deviceSettings: environment.deviceSettings)
    }

    /// An extension cannot add stored properties, so the hooks live in an object tied to this model.
    private var settingsHooks: SettingsHooks {
        let key = SettingsHooks.associationKey
        if let hooks = objc_getAssociatedObject(self, key) as? SettingsHooks { return hooks }
        let hooks = SettingsHooks()
        objc_setAssociatedObject(self, key, hooks, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return hooks
    }
}

/// The settings' hooks of one `AppModel`, kept with it as an associated object.
@MainActor
private final class SettingsHooks {
    var onGeminiKeyChanged: (() -> Void)?

    /// The association's key: the address of an object that lives as long as the app.
    nonisolated static var associationKey: UnsafeRawPointer {
        UnsafeRawPointer(Unmanaged.passUnretained(keyObject).toOpaque())
    }

    private final class KeyObject: Sendable {}
    private nonisolated static let keyObject = KeyObject()
}
