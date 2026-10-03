import Foundation
import GoldaCore
import GoldaData

/// What "Отменить" needs after a payment was deleted: the payment itself, with its id, its place in
/// the creation order, and the profile it came from, so the undo lands there even when another
/// profile is open by then.
struct ObligationUndoToken: Equatable, Sendable {
    let profileId: UUID
    let obligation: Obligation
    /// Nil when the payment was gone already: it then comes back after the others.
    let createdAt: Int64?
}

/// The intents of the profiles screens. Unlike the books on screen, these name their profile: the
/// profiles screen edits any profile, not only the active one (income, payday, markup and payments
/// belong to the profile, D21).
extension AppModel {
    // MARK: Profiles

    /// A new profile after the others. Unlike `createProfile`, which the profile menu uses to open
    /// it at once, the active profile stays: the profiles screen is for setting one up, and
    /// switching is a separate, visible step there.
    @discardableResult
    func addProfile(name: String) async throws -> Profile {
        try await environment.repository.createProfile(name: name)
    }

    /// Income, payday and markup of [profileId], for everyone in it. The active profile's snapshot
    /// carries them, so Home's "Можно сегодня" and the hours of work follow at once.
    func saveProfileSettings(_ settings: ProfileSettings, profileId: UUID) async throws {
        try await environment.repository.saveProfileSettings(settings, profileId: profileId)
    }

    /// One profile's books, again after each change, until the profile is deleted: the profile's
    /// screen follows any profile this way, the active one or not. Throws when the database fails.
    func profileSnapshots(_ profileId: UUID) -> AsyncThrowingStream<ProfileSnapshot, any Error> {
        environment.database.snapshots(profileId: profileId)
    }

    /// What deleting [profileId] would take along; nil when there is no such profile.
    func profileContents(_ profileId: UUID) async throws -> ProfileContents? {
        try await environment.database.read { store in
            try store.snapshot(profileId: profileId).map(ProfileContents.init)
        }
    }

    // MARK: Payments

    /// Adds [obligation] to [profileId], or replaces the one with its id.
    func saveObligation(_ obligation: Obligation, profileId: UUID) async throws {
        try await environment.repository.saveObligation(obligation, profileId: profileId)
    }

    /// Deletes the payment; the token brings it back through `restoreObligation`.
    func deleteObligation(_ obligation: Obligation, profileId: UUID) async throws -> ObligationUndoToken {
        let deleted = try await environment.repository.deleteObligation(obligation.id, profileId: profileId)
        return ObligationUndoToken(
            profileId: profileId, obligation: deleted?.obligation ?? obligation, createdAt: deleted?.createdAt
        )
    }

    /// Undo of `deleteObligation`: the same payment with the same id, back at its place among the
    /// payments of its day (they are listed in creation order).
    func restoreObligation(_ token: ObligationUndoToken) async throws {
        try await environment.repository.saveObligation(token.obligation, profileId: token.profileId, createdAt: token.createdAt)
    }
}
