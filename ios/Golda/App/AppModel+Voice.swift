import Foundation
import GoldaCore
import GoldaData
import OSLog

private let log = Logger(subsystem: "com.f4studio.golda", category: "Voice")

/// The voice's intents. The work is the environment's `VoiceService`; the model says which profile
/// and keeps the answer on the consent screen.
extension AppModel {
    /// Works through the voice notes that wait, oldest first: those recorded offline, before a key or
    /// before consent. Their outcomes reach the mic's toasts like any other. The settings screen calls
    /// this after a Gemini key is saved; launch, the return to the foreground and consent call it too.
    @discardableResult
    func processVoiceQueue() -> Task<Void, Never> {
        let voice = environment.voice
        return Task { await voice.processQueue() }
    }

    /// Read from the store, not from `device`, which trails a change by one observation.
    var hasVoiceConsent: Bool {
        environment.deviceSettings.current.voiceConsent
    }

    /// "Отменить" on a voice toast: what the note booked goes, from the profile it was booked into,
    /// whichever profile is open now (Android deleted each operation of the note).
    func undoVoiceNote(_ done: VoiceOutcome.Done) async {
        await undoVoiceNote(profileId: done.profileId, operationIds: done.recorded.map(\.operationId))
    }

    /// The same for «Отменить» on the Live Activity of a note recorded outside the app, which
    /// carries only the ids. An operation already gone (undone in the app too) is skipped.
    func undoVoiceNote(profileId: UUID, operationIds: [UUID]) async {
        for id in operationIds.reversed() {
            do {
                _ = try await environment.repository.deleteOperation(id, profileId: profileId)
            } catch {
                log.error("Undoing a voice note failed: \(String(describing: error))")
            }
        }
    }

    /// What a toast about a note booked into [profileId] needs, read fresh: the note may belong to a
    /// profile other than the open one. Nil when the profile is gone or cannot be read.
    func voiceBooks(profileId: UUID) async -> VoiceBooks? {
        let device = environment.deviceSettings.current
        let named = profiles.count > 1
        do {
            return try await environment.database.read { store -> VoiceBooks? in
                guard let profile = try store.profile(profileId) else { return nil }
                let accounts = try store.accounts(profileId: profileId)
                let rates = Rates(
                    Dictionary(try store.rates().map { ($0.code, $0.rubPerUnit) }, uniquingKeysWith: { _, last in last }),
                    markup: profile.settings.markup
                )
                let settings = Settings(profile: profile.settings, device: device, profileId: profileId)
                return VoiceBooks(
                    currencies: Dictionary(accounts.map { ($0.id, $0.currency) }, uniquingKeysWith: { _, last in last }),
                    base: Base.of(settings, rates),
                    profileName: named ? profile.name : nil
                )
            }
        } catch {
            log.error("Reading the books of a voice note failed: \(String(describing: error))")
            return nil
        }
    }
}
