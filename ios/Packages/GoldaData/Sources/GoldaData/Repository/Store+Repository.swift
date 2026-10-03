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
    /// operations with the same timestamp.
    func restore(_ full: OperationFull, sequence: Int64, profileId: UUID, updatedAt: Int64) throws {
        try makeRoom(OperationRecord.self, "sequence", at: sequence, for: full.op.id, profileId: profileId)
        try save(full.op, profileId: profileId, updatedAt: updatedAt, sequence: sequence)
        for posting in full.postings { try save(posting, profileId: profileId) }
    }

    /// The goal's place in the profile's creation order.
    func createdAt(ofGoal id: UUID, profileId: UUID) throws -> Int64? {
        try createdAt(GoalRecord.self, id, profileId)
    }

    /// Saves the goal at [createdAt] in the profile's creation order: a deleted goal back at its
    /// old place, so "the oldest becomes main" still means the one created first.
    func restore(_ goal: Goal, createdAt: Int64, profileId: UUID) throws {
        try makeRoom(GoalRecord.self, "createdAt", at: createdAt, for: goal.id, profileId: profileId)
        try save(goal, profileId: profileId, createdAt: createdAt)
    }

    /// The payment's place in the profile's creation order.
    func createdAt(ofObligation id: UUID, profileId: UUID) throws -> Int64? {
        try createdAt(ObligationRecord.self, id, profileId)
    }

    /// Saves the payment at [createdAt] in the profile's creation order: a deleted payment back at
    /// its old place among the payments of its day.
    func restore(_ obligation: Obligation, createdAt: Int64, profileId: UUID) throws {
        try makeRoom(ObligationRecord.self, "createdAt", at: createdAt, for: obligation.id, profileId: profileId)
        try save(obligation, profileId: profileId, createdAt: createdAt)
    }

    private func createdAt<Record: CreationOrderedRecord>(_ type: Record.Type, _ id: UUID, _ profileId: UUID) throws -> Int64? {
        try Int64.fetchOne(db, Record.owned(by: profileId).filter(id: id).select(Column("createdAt")))
    }

    /// Frees [place] in the profile's order held in [column] for row [id] coming back to it. When the
    /// row was the last one, a row added since has taken its number; that one and every later one
    /// move up by one, so all keep the order they were added in, as with Android's autoincrement ids.
    private func makeRoom<Record: ProfileOwnedRecord>(
        _ type: Record.Type, _ column: String, at place: Int64, for id: UUID, profileId: UUID
    ) throws {
        let others = Record.owned(by: profileId).filter(Column("id") != id)
        if try others.filter(Column(column) == place).fetchCount(db) > 0 {
            try others.filter(Column(column) >= place).updateAll(db, Column(column) += 1)
        }
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
