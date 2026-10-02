import Foundation
import GoldaCore
import GRDB

// Primitives only the repository needs. They live apart from `Store.swift` so the store's public
// surface stays what the screens and the backup see.
extension Store {
    /// Operations from [since] on, oldest first, each with its postings: today's spending without
    /// reading the whole history (Android's `operationsSince`).
    func operations(profileId: UUID, since: Int64) throws -> [OperationFull] {
        let recent = OperationRecord.owned(by: profileId).filter(Column("timestamp") >= since)
        let records = try recent.order(Column("timestamp"), Column.rowID).fetchAll(db)
        let postings = try PostingRecord.owned(by: profileId)
            .filter(recent.select(Column("id")).contains(Column("operationId")))
            .order(Column.rowID)
            .fetchAll(db)
        let byOperation = Dictionary(grouping: postings.map(\.posting), by: \.operationId)
        return records.map { OperationFull($0.operation, byOperation[$0.id] ?? []) }
    }

    /// Postings that moved money but are worth 0 ₽: written while their currency had no rate.
    func unvaluedPostings(profileId: UUID) throws -> [Posting] {
        try PostingRecord.owned(by: profileId)
            .filter(Column("rubMinor") == 0 && Column("amountMinor") != 0)
            .order(Column.rowID)
            .fetchAll(db)
            .map(\.posting)
    }

    /// Every profile with everything it owns.
    func deleteAllProfiles() throws {
        try ProfileRecord.deleteAll(db)
    }

    func deleteAllRates() throws {
        try RateRecord.deleteAll(db)
    }
}
