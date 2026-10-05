import Foundation
import GoldaCore
import GRDB

/// Categories of the profile's own (D68). The built-in ones are not stored and not edited.
extension Repository {
    /// Makes or changes the category; a new one comes after the others.
    public func saveCategory(_ category: CustomCategory, profileId: UUID) async throws {
        try await write { store in try store.save(category, profileId: profileId) }
    }

    /// Deletes the category; its operations go to "Прочее" of its kind, in the same transaction, so
    /// the other phones get them moved along with the deletion.
    public func deleteCategory(_ category: CustomCategory, profileId: UUID) async throws {
        let now = clock()
        try await write { store in
            try store.db.execute(
                sql: "UPDATE operation SET categoryKey = ?, updatedAt = ? WHERE profileId = ? AND categoryKey = ?",
                arguments: [GoldaCore.Category.other(category.kind), now, profileId, category.key]
            )
            try store.deleteCategory(category.id, profileId: profileId)
        }
    }

    /// How many operations of the profile are in the category: what its deletion moves to "Прочее".
    public func operationCount(categoryKey: String, profileId: UUID) async throws -> Int {
        try await database.read { store in
            try Int.fetchOne(
                store.db, sql: "SELECT COUNT(*) FROM operation WHERE profileId = ? AND categoryKey = ?",
                arguments: [profileId, categoryKey]
            ) ?? 0
        }
    }

    /// What the voice model files by: every category of the profile, and the latest filing of each
    /// note it has (`CategoryExample`).
    public func voiceCategories(profileId: UUID) async throws -> VoiceCategories {
        try await database.read { try Self.voiceCategories($0, profileId: profileId) }
    }

    static func voiceCategories(_ store: Store, profileId: UUID) throws -> VoiceCategories {
        let categories = GoldaCore.Category.all(custom: try store.categories(profileId: profileId))
        let operations = try store.operations(profileId: profileId).map(\.op)
        return VoiceCategories(
            categories: categories,
            examples: CategoryExample.latest(operations, categories: categories, limit: VoiceCategories.exampleLimit)
        )
    }
}

/// The categories a voice note is filed into, and how the person filed notes before.
public struct VoiceCategories: Equatable, Sendable {
    /// Enough to show the habits, few enough to keep the prompt short.
    public static let exampleLimit = 60

    public var categories: [GoldaCore.Category]
    public var examples: [CategoryExample]

    public init(categories: [GoldaCore.Category], examples: [CategoryExample]) {
        self.categories = categories
        self.examples = examples
    }
}
