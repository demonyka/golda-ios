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
        let records = try recent.order(Column("timestamp"), Column("sequence")).fetchAll(db)
        let postings = try PostingRecord.owned(by: profileId)
            .filter(recent.select(Column("id")).contains(Column("operationId")))
            .order(Column.rowID)
            .fetchAll(db)
        let byOperation = Dictionary(grouping: postings.map(\.posting), by: \.operationId)
        return records.map { OperationFull($0.operation, byOperation[$0.id] ?? []) }
    }

    /// The operation's place in the profile's order of writing.
    func sequence(ofOperation id: UUID, profileId: UUID) throws -> Int64? {
        try Int64.fetchOne(db, OperationRecord.owned(by: profileId).filter(id: id).select(Column("sequence")))
    }

    /// Puts a deleted operation back with its postings at [sequence], its old place among
    /// operations with the same timestamp. When the deleted one was the last written, an operation
    /// written since has taken its number; that one and any later move up by one, so every
    /// operation keeps the order it was written in, as with Android's autoincrement ids.
    func restore(_ full: OperationFull, sequence: Int64, profileId: UUID, updatedAt: Int64) throws {
        let others = OperationRecord.owned(by: profileId).filter(Column("id") != full.op.id)
        if try others.filter(Column("sequence") == sequence).fetchCount(db) > 0 {
            try others.filter(Column("sequence") >= sequence).updateAll(db, Column("sequence") += 1)
        }
        try save(full.op, profileId: profileId, updatedAt: updatedAt, sequence: sequence)
        for posting in full.postings { try save(posting, profileId: profileId) }
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
