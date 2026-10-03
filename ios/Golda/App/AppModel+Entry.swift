import Foundation
import GoldaCore
import GoldaData

/// What the operation form recorded, and where: "Отменить" takes it back from that profile even
/// when another one has been opened since.
struct EntrySaved: Equatable, Sendable {
    let profileId: UUID
    let operationId: UUID
    /// What a new expense cost in work and what is left for today; nil for anything else.
    let impact: Impact?
}

/// The operation form's intents: the port of Android's `save`, `announce` and the "Сомневаюсь"
/// callbacks in `Main.kt`. Like the rest of `AppModel` they only say which profile; the repository
/// decides, and the form turns the values it returns into words.
extension AppModel {
    /// Records [draft] (or replaces the operation with its id) in the profile on screen and marks
    /// [wishId], a waiting wish bought through the form, as bought. A new expense comes back with
    /// its impact, for the toast.
    func saveEntry(_ draft: Draft, wishId: UUID? = nil) async throws -> EntrySaved {
        let profileId = try entryProfileId()
        let repository = environment.repository
        let id = try await repository.save(draft, profileId: profileId)
        if let wishId { try await repository.bought(wishId: wishId, profileId: profileId) }
        let impact = draft.id == nil ? try await repository.impact(operationId: id, profileId: profileId) : nil
        return EntrySaved(profileId: profileId, operationId: id, impact: impact)
    }

    /// "Отменить" after recording: the operation goes again, from the profile it went into.
    func undoEntry(_ saved: EntrySaved) async throws {
        try await environment.repository.deleteOperation(saved.operationId, profileId: saved.profileId)
    }

    /// What the price means in the profile on screen: hours of work, days of budget, the share of
    /// the main goal, and how long "Подумаю" would wait.
    func purchaseFacts(_ consider: Consider) async throws -> Facts {
        try await environment.repository.consider(consider, profileId: try entryProfileId())
    }

    /// "Не беру": the refusal is remembered and the money goes towards the main goal.
    func skipPurchase(_ consider: Consider, wishId: UUID? = nil) async throws -> SkipOutcome {
        try await environment.repository.skip(consider, wishId: wishId, profileId: try entryProfileId())
    }

    /// "Подумаю": the purchase waits on the wishlist; the wish says until when.
    func thinkAbout(_ consider: Consider) async throws -> Wish {
        try await environment.repository.think(consider, profileId: try entryProfileId())
    }

    /// The profile on screen; `AppModel`'s own lookup is private to it.
    private func entryProfileId() throws -> UUID {
        guard let id = data?.profile.id else { throw AppModelError.noProfileOpen }
        return id
    }
}
