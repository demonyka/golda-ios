import Foundation
import GoldaCore
import GoldaData

/// What "Отменить" needs after a goal was deleted: the goal as it was, its place in the creation
/// order, and the profile it came from, so the undo lands there even when another profile has been
/// opened since.
struct GoalUndoToken: Equatable, Sendable {
    let profileId: UUID
    let goal: Goal
    /// Nil when the goal was gone already: it then comes back after the others.
    let createdAt: Int64?
}

/// The same for a wish taken off the list.
struct WishUndoToken: Equatable, Sendable {
    let profileId: UUID
    let wish: Wish
}

/// What buying a goal did: the expense it recorded and what that expense means for today.
struct GoalPurchaseOutcome: Equatable, Sendable {
    let operationId: UUID
    let impact: Impact?
}

// Goals and the wishlist of the profile on screen. Thin, like the rest of the model's intents: the
// repository keeps one main goal and books the purchase; the model only says which profile.
extension AppModel {
    /// The goal whose reaching this phone has already celebrated in the open profile.
    var celebratedGoalId: UUID? {
        data.flatMap { device.celebratedGoalId[$0.profile.id] }
    }

    /// Adds [goal] or updates the goal with its id. A goal saved as main takes over from the one
    /// before it; with no main goal left, the oldest becomes main.
    func saveGoal(_ goal: Goal) async throws {
        try await environment.repository.saveGoal(goal, profileId: try profileOnScreen())
    }

    /// Deletes the goal; when it was the main one, the oldest left takes its place. The token brings
    /// it back through `restoreGoal`.
    func deleteGoal(_ goal: Goal) async throws -> GoalUndoToken {
        let profileId = try profileOnScreen()
        let deleted = try await environment.repository.deleteGoal(goal.id, profileId: profileId)
        return GoalUndoToken(profileId: profileId, goal: deleted?.goal ?? goal, createdAt: deleted?.createdAt)
    }

    /// Undo of `deleteGoal`: the goal comes back with its id, main again if it was, and to its
    /// place in the creation order, so the oldest goal is still the one created first.
    func restoreGoal(_ token: GoalUndoToken) async throws {
        try await environment.repository.saveGoal(token.goal, profileId: token.profileId, createdAt: token.createdAt)
    }

    /// "Купить" on a reached goal, as Android does it: the expense of the goal's amount from the
    /// account `VoiceMapper.buy` picks, then the goal closes. Nil, and the goal stays, when no
    /// account can pay.
    func buyGoal(_ goal: Goal) async throws -> GoalPurchaseOutcome? {
        let profileId = try profileOnScreen()
        let repository = environment.repository
        let consider = Consider(title: goal.name, amountMinor: goal.targetMinor, currency: goal.currency)
        guard let operationId = try await repository.buy(consider, profileId: profileId) else { return nil }
        try await repository.deleteGoal(goal.id, profileId: profileId)
        let impact = try await repository.impact(operationId: operationId, profileId: profileId)
        return GoalPurchaseOutcome(operationId: operationId, impact: impact)
    }

    /// Takes the wish off the list, waiting or decided; nil when there was no such wish.
    func deleteWish(_ id: UUID) async throws -> WishUndoToken? {
        let profileId = try profileOnScreen()
        let wish = try await environment.repository.deleteWish(id, profileId: profileId)
        return wish.map { WishUndoToken(profileId: profileId, wish: $0) }
    }

    func restoreWish(_ token: WishUndoToken) async throws {
        try await environment.repository.restoreWish(token.wish, profileId: token.profileId)
    }

    /// Remembers on this phone that reaching [goalId] was celebrated in the open profile, so the
    /// wave settles with a tap of haptics only the first time (D16: it is not synced).
    func markGoalCelebrated(_ goalId: UUID) {
        guard let profileId = data?.profile.id else { return }
        environment.deviceSettings.update { $0.celebratedGoalId[profileId] = goalId }
    }
}
