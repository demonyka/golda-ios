import Foundation
import GoldaCore

extension Repository {
    /// Books what one voice note said, in the order said, in one transaction, and returns the
    /// operation ids. `save` one by one would leave half a note booked when a later draft fails,
    /// and the note, kept for another try, would book that half again.
    func save(_ drafts: [Draft], profileId: UUID) async throws -> [UUID] {
        guard !drafts.isEmpty else { return [] }
        let now = clock()
        let ids = try await write { store in
            try drafts.map { try Self.book($0, profileId: profileId, in: store, at: now) }
        }
        // What `save` does for each expense; the last one is what stays.
        if let expense = drafts.last(where: { $0.type == .expense }) {
            deviceSettings.update { $0.lastAccountId[profileId] = expense.accountId }
        }
        return ids
    }
}
