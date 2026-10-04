import Foundation

/// The intents of sharing a profile (stage 5c). Inviting goes through the system share sheet with
/// `AppSync.invitation`; the rest is here.
extension AppModel {
    /// A participant leaves a profile shared with them: it goes from this phone with everything in
    /// it, its reminders with it, and another profile opens (ARCHITECTURE, «Выход участника»). The
    /// server hears of it through the queue, now or once the phone is online. When it was the only
    /// profile, a fresh «Личный» takes its place, as the app always has one.
    func leaveProfile(_ id: UUID) async throws {
        if profiles.count <= 1 {
            let fresh = try await environment.repository.createProfile(name: Self.firstProfileName)
            environment.deviceSettings.update { $0.activeProfileId = fresh.id }
        }
        try await deleteProfile(id)
    }

    /// The owner stops sharing: everyone invited loses the profile, the owner keeps it.
    func stopSharing(_ id: UUID) async throws {
        try await sync.stopSharing(id)
    }

    /// A profile that arrived through an accepted invitation: it opens everywhere. Not during
    /// onboarding, whose steps set up the person's own first profile and must not write their
    /// income into someone else's; the shared profile waits in the menu.
    func joined(_ profileId: UUID) {
        guard device.onboarded else { return }
        Task {
            await reloadProfiles()
            switchProfile(to: profileId)
        }
    }
}
