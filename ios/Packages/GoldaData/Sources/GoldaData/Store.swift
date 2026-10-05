import Foundation
import GoldaCore
import GRDB

public enum StoreError: Error, Equatable, Sendable {
    /// A row with this id already belongs to another profile. Ids are UUIDs, so this is a bug in the
    /// caller rather than a collision, and the row is left as it was.
    case belongsToAnotherProfile(UUID)
}

/// Typed access to the tables inside one transaction, every row scoped by its profile. It is handed
/// out by `GoldaDatabase.read` and `write`, so a caller can read balances, value postings and write
/// them atomically. Writes inside `read` fail: that connection is read-only.
///
/// These are primitives: saving a draft, editing, deleting and restoring operations, reconciling and
/// the like are built on top of them.
public struct Store {
    let db: Database

    // MARK: Profiles

    /// By `sort`, then id.
    public func profiles() throws -> [Profile] {
        try ProfileRecord.order(Column("sort"), Column("id")).fetchAll(db).map(\.profile)
    }

    public func profile(_ id: UUID) throws -> Profile? {
        try ProfileRecord.fetchOne(db, id: id)?.profile
    }

    /// Inserts the profile or updates the one with its id.
    public func save(_ profile: Profile) throws {
        try ProfileRecord(profile).save(db)
    }

    /// Deletes the profile with everything it owns.
    @discardableResult
    public func deleteProfile(_ id: UUID) throws -> Bool {
        try ProfileRecord.deleteOne(db, id: id)
    }

    // MARK: Accounts

    public func accounts(profileId: UUID) throws -> [Account] {
        try AccountRecord.owned(by: profileId).order(Column("sort"), Column("id")).fetchAll(db).map(\.account)
    }

    public func account(_ id: UUID, profileId: UUID) throws -> Account? {
        try AccountRecord.owned(by: profileId).filter(id: id).fetchOne(db)?.account
    }

    public func save(_ account: Account, profileId: UUID) throws {
        try saveOwned(AccountRecord(account, profileId: profileId))
    }

    /// Deletes the account and its postings; the operations those postings belonged to stay, so call
    /// `deleteOperations(touching:profileId:)` first when they should go too.
    @discardableResult
    public func deleteAccount(_ id: UUID, profileId: UUID) throws -> Bool {
        try deleteOwned(AccountRecord.self, id, profileId)
    }

    // MARK: Operations

    /// Newest first, each with its postings.
    public func operations(profileId: UUID) throws -> [OperationFull] {
        let records = try OperationRecord.owned(by: profileId)
            // Equal timestamps (several expenses from one voice note) keep the order they were
            // written in, newest first, as Android's autoincrement ids did.
            .order(Column("timestamp").desc, Column("sequence").desc)
            .fetchAll(db)
        let postings = Dictionary(grouping: try postings(profileId: profileId), by: \.operationId)
        return records.map { OperationFull($0.operation, postings[$0.id] ?? []) }
    }

    public func operation(_ id: UUID, profileId: UUID) throws -> OperationFull? {
        guard let record = try OperationRecord.owned(by: profileId).filter(id: id).fetchOne(db) else { return nil }
        let postings = try PostingRecord.owned(by: profileId)
            .filter(Column("operationId") == id)
            .order(Column.rowID)
            .fetchAll(db)
        return OperationFull(record.operation, postings.map(\.posting))
    }

    /// Writes the operation row alone; its postings are saved separately. [updatedAt] is epoch
    /// milliseconds of this change. A new operation comes after every other one of the profile in
    /// the order of writing; an edit keeps its place.
    public func save(_ operation: GoldaCore.Operation, profileId: UUID, updatedAt: Int64) throws {
        try save(operation, profileId: profileId, updatedAt: updatedAt, sequence: nil)
    }

    /// As above, but at [sequence] in the order of writing when it is given (an undone delete).
    func save(_ operation: GoldaCore.Operation, profileId: UUID, updatedAt: Int64, sequence: Int64?) throws {
        var record = OperationRecord(operation, profileId: profileId, updatedAt: updatedAt, sequence: sequence)
        if record.sequence == nil {
            let stored = try Int64.fetchOne(db, OperationRecord.filter(id: operation.id).select(Column("sequence")))
            let last = try Int64.fetchOne(db, OperationRecord.owned(by: profileId).select(max(Column("sequence"))))
            record.sequence = stored ?? (last ?? 0) + 1
        }
        try saveOwned(record)
    }

    /// Deletes the operation and its postings.
    @discardableResult
    public func deleteOperation(_ id: UUID, profileId: UUID) throws -> Bool {
        try deleteOwned(OperationRecord.self, id, profileId)
    }

    /// Deletes every operation with a posting on [accountId], other sides of transfers included, so
    /// no half of a transfer is left behind when the account goes. Returns how many went.
    @discardableResult
    public func deleteOperations(touching accountId: UUID, profileId: UUID) throws -> Int {
        let touching = PostingRecord.owned(by: profileId)
            .filter(Column("accountId") == accountId)
            .select(Column("operationId"))
        return try OperationRecord.owned(by: profileId).filter(touching.contains(Column("id"))).deleteAll(db)
    }

    // MARK: Postings

    /// All postings of the profile in the order they were written, which keeps each operation's
    /// postings in the order the ledger produced them (a transfer's source, then its destination).
    /// [excludingOperation] leaves out the postings of an operation that is being replaced.
    public func postings(profileId: UUID, excludingOperation: UUID? = nil) throws -> [Posting] {
        var request = PostingRecord.owned(by: profileId)
        if let excludingOperation {
            request = request.filter(Column("operationId") != excludingOperation)
        }
        return try request.order(Column.rowID).fetchAll(db).map(\.posting)
    }

    /// The posting's operation and account must already exist in the same profile.
    public func save(_ posting: Posting, profileId: UUID) throws {
        try saveOwned(PostingRecord(posting, profileId: profileId))
    }

    @discardableResult
    public func deletePosting(_ id: UUID, profileId: UUID) throws -> Bool {
        try deleteOwned(PostingRecord.self, id, profileId)
    }

    // MARK: Obligations

    /// By day of the month, then the order they were created in, as Android listed them (O10).
    public func obligations(profileId: UUID) throws -> [Obligation] {
        try ObligationRecord.owned(by: profileId)
            .order(Column("dayOfMonth"), Column("createdAt"), Column("id"))
            .fetchAll(db)
            .map(\.obligation)
    }

    public func obligation(_ id: UUID, profileId: UUID) throws -> Obligation? {
        try ObligationRecord.owned(by: profileId).filter(id: id).fetchOne(db)?.obligation
    }

    /// [createdAt] is the payment's place in the creation order. Nil keeps the place of a payment
    /// that is already stored and puts a new one after every other payment of the profile; an import
    /// passes the original order.
    public func save(_ obligation: Obligation, profileId: UUID, createdAt: Int64? = nil) throws {
        try saveInCreationOrder(ObligationRecord(obligation, profileId: profileId, createdAt: createdAt))
    }

    @discardableResult
    public func deleteObligation(_ id: UUID, profileId: UUID) throws -> Bool {
        try deleteOwned(ObligationRecord.self, id, profileId)
    }

    // MARK: Goals

    /// The main goal first, then the oldest (D27).
    public func goals(profileId: UUID) throws -> [Goal] {
        try GoalRecord.owned(by: profileId)
            .order(Column("isMain").desc, Column("createdAt"), Column("id"))
            .fetchAll(db)
            .map(\.goal)
    }

    public func goal(_ id: UUID, profileId: UUID) throws -> Goal? {
        try GoalRecord.owned(by: profileId).filter(id: id).fetchOne(db)?.goal
    }

    /// [createdAt] is the goal's place in the creation order. Nil keeps the place of a goal that is
    /// already stored and puts a new one after every other goal of the profile; an import passes the
    /// original order.
    public func save(_ goal: Goal, profileId: UUID, createdAt: Int64? = nil) throws {
        try saveInCreationOrder(GoalRecord(goal, profileId: profileId, createdAt: createdAt))
    }

    @discardableResult
    public func deleteGoal(_ id: UUID, profileId: UUID) throws -> Bool {
        try deleteOwned(GoalRecord.self, id, profileId)
    }

    // MARK: Wishes

    public func wishes(profileId: UUID) throws -> [Wish] {
        try WishRecord.owned(by: profileId)
            .order(Column("status"), Column("decideAt").desc, Column("id"))
            .fetchAll(db)
            .map(\.wish)
    }

    public func wish(_ id: UUID, profileId: UUID) throws -> Wish? {
        try WishRecord.owned(by: profileId).filter(id: id).fetchOne(db)?.wish
    }

    public func save(_ wish: Wish, profileId: UUID) throws {
        try saveOwned(WishRecord(wish, profileId: profileId))
    }

    @discardableResult
    public func deleteWish(_ id: UUID, profileId: UUID) throws -> Bool {
        try deleteOwned(WishRecord.self, id, profileId)
    }

    // MARK: Categories

    /// The profile's own categories in the order they were made (D68).
    public func categories(profileId: UUID) throws -> [CustomCategory] {
        try CategoryRecord.owned(by: profileId)
            .order(Column("createdAt"), Column("id"))
            .fetchAll(db)
            .map(\.category)
    }

    /// [createdAt] as for goals: nil keeps a stored category's place or puts a new one last.
    public func save(_ category: CustomCategory, profileId: UUID, createdAt: Int64? = nil) throws {
        try saveInCreationOrder(CategoryRecord(category, profileId: profileId, createdAt: createdAt))
    }

    @discardableResult
    public func deleteCategory(_ id: UUID, profileId: UUID) throws -> Bool {
        try deleteOwned(CategoryRecord.self, id, profileId)
    }

    // MARK: Rates

    public func rates() throws -> [RateRecord] {
        try RateRecord.order(Column("code")).fetchAll(db)
    }

    /// Inserts new codes and replaces the rate and date of known ones.
    public func save(_ rates: [RateRecord]) throws {
        for rate in rates {
            try rate.upsert(db)
        }
    }

    // MARK: Snapshot

    /// Everything the profile owns, or nil when there is no such profile.
    public func snapshot(profileId: UUID) throws -> ProfileSnapshot? {
        guard let profile = try profile(profileId) else { return nil }
        return ProfileSnapshot(
            profile: profile,
            accounts: try accounts(profileId: profileId),
            operations: try operations(profileId: profileId),
            obligations: try obligations(profileId: profileId),
            goals: try goals(profileId: profileId),
            wishes: try wishes(profileId: profileId),
            categories: try categories(profileId: profileId)
        )
    }

    // MARK: Scoping

    /// Inserts a new row or updates the profile's own one. A plain upsert would quietly move a row
    /// that another profile owns, so the owner is checked first.
    private func saveOwned<Record: ProfileOwnedRecord>(_ record: Record) throws {
        let owner = try UUID.fetchOne(db, Record.filter(id: record.id).select(Column("profileId")))
        switch owner {
        case nil: try record.insert(db)
        case record.profileId: try record.update(db)
        default: throw StoreError.belongsToAnotherProfile(record.id)
        }
    }

    /// `saveOwned` for a row with a place in the creation order: a nil place keeps the stored row's
    /// one, or comes after every other row of the profile for a new row.
    private func saveInCreationOrder<Record: CreationOrderedRecord>(_ record: Record) throws {
        var record = record
        if record.createdAt == nil {
            let stored = try Int64.fetchOne(db, Record.filter(id: record.id).select(Column("createdAt")))
            let last = try Int64.fetchOne(db, Record.owned(by: record.profileId).select(max(Column("createdAt"))))
            record.createdAt = stored ?? (last ?? 0) + 1
        }
        try saveOwned(record)
    }

    private func deleteOwned<Record: ProfileOwnedRecord>(_ type: Record.Type, _ id: UUID, _ profileId: UUID) throws -> Bool {
        try Record.owned(by: profileId).filter(id: id).deleteAll(db) > 0
    }
}

extension ProfileOwnedRecord {
    static func owned(by profileId: UUID) -> QueryInterfaceRequest<Self> {
        filter(Column("profileId") == profileId)
    }
}
