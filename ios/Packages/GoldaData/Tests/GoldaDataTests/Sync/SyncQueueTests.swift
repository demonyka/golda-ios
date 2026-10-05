import Foundation
import GoldaCore
import GRDB
import Testing

@testable import GoldaData

/// Local changes reach the sync queue on their own, in the transaction that made them (D57): every
/// write of the books, through the repository or not, cascades included.
@Suite struct SyncQueueTests {
    private let harness: RepositoryHarness
    private let sync: SyncStore

    init() throws {
        harness = try RepositoryHarness()
        sync = SyncStore(database: harness.database)
    }

    private func queued() async throws -> [String: OutgoingKind] {
        Dictionary(uniqueKeysWithValues: try await sync.outgoing().map { ($0.ref.recordName, $0.kind) })
    }

    private func name(_ type: SyncRecordType, _ id: UUID) -> String {
        SyncRecordRef(zone: .own(id), type: type, id: id).recordName
    }

    @Test func aRepositoryWriteQueuesEveryRowItTouched() async throws {
        let card = Account.card("Карта")
        let profileId = try await harness.profile(accounts: [card])
        let id = try await harness.repository.save(Draft(type: .expense, timestamp: RepositoryHarness.start, accountId: card.id, amountMinor: 50_000, categoryKey: "food"), profileId: profileId)
        let full = try #require(try await harness.operation(id, profileId))

        let queue = try await queued()
        #expect(queue[name(.profile, profileId)] == .save)
        #expect(queue[name(.account, card.id)] == .save)
        #expect(queue[name(.operation, id)] == .save)
        // A posting travels inside its operation's record, never on its own.
        #expect(queue[name(.operation, full.postings[0].id)] == nil)
        #expect(queue.count == 3)
        let refs = try await sync.outgoing().map(\.ref)
        #expect(refs.allSatisfy { $0.zone == .own(profileId) })
    }

    @Test func aWriteThatFailsQueuesNothing() async throws {
        struct Refused: Error {}
        await #expect(throws: Refused.self) {
            try await harness.database.write { store in
                try store.save(Profile(name: "Черновик"))
                throw Refused()
            }
        }
        #expect(try await sync.outgoing().isEmpty)
        let journal = try await harness.database.writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM syncJournal") }
        #expect(journal == 0)
    }

    @Test func aChangeIsStampedWithTheWritersClockAndDevice() async throws {
        harness.clock.set(RepositoryHarness.start + 5_000)
        let profileId = try await harness.profile()
        let record = try #require(try await sync.record(SyncRecordRef(zone: .own(profileId), type: .profile, id: profileId)))
        #expect(record.updatedAt == RepositoryHarness.start + 5_000)
        #expect(record.authorDevice == (try await sync.deviceName()))
        #expect(record.authorDevice.count == 12)
    }

    @Test func aDeleteWaitsOutTheUndoWindowAndAnUndoReplacesIt() async throws {
        let card = Account.card("Карта")
        let profileId = try await harness.profile(accounts: [card])
        let id = try await harness.repository.save(Draft(type: .expense, timestamp: RepositoryHarness.start, accountId: card.id, amountMinor: 100), profileId: profileId)
        _ = try await sync.takeDue(at: harness.clock.now)

        let deleted = try #require(try await harness.repository.deleteOperation(id, profileId: profileId))
        let ref = SyncRecordRef(zone: .own(profileId), type: .operation, id: id)
        let entry = try #require(try await sync.outgoing().first { $0.ref == ref })
        #expect(entry.kind == .delete)
        #expect(entry.notBefore == harness.clock.now + OutgoingQueue.undoWindow)
        // Its posting went with it, inside the record.
        #expect(try await sync.outgoing().filter { $0.kind == .delete }.map(\.ref) == [ref])
        #expect(try await sync.takeDue(at: harness.clock.now + OutgoingQueue.undoWindow - 1).isEmpty)

        // "Отменить" in time: the rows come back and only saves are due; the delete never leaves.
        try await harness.repository.restoreOperation(deleted, profileId: profileId)
        let due = try await sync.takeDue(at: harness.clock.now)
        #expect(Set(due.map(\.kind)) == [.save])
        #expect(due.map(\.ref) == [ref])
    }

    @Test func deletingAnAccountQueuesTheOperationsItTookAlong() async throws {
        let card = Account.card("Карта"), cash = Account.card("Наличные")
        let profileId = try await harness.profile(accounts: [card, cash])
        let transfer = try await harness.repository.save(
            Draft(type: .transfer, timestamp: RepositoryHarness.start, accountId: card.id, amountMinor: 100, toAccountId: cash.id),
            profileId: profileId
        )
        try await harness.repository.deleteAccount(card.id, profileId: profileId)
        let queue = try await queued()
        #expect(queue[name(.account, card.id)] == .delete)
        #expect(queue[name(.operation, transfer)] == .delete)
        #expect(queue[name(.account, cash.id)] == .save)
    }

    @Test func aNewCreditLimitAloneSendsTheAccount() async throws {
        let card = Account(name: "Кредитка", currency: "RUB", type: .credit, includeInFree: false)
        let profileId = try await harness.profile(accounts: [card])
        try await harness.database.writer.write { db in try db.execute(sql: "DELETE FROM syncOutgoing") }
        var limited = card
        limited.creditLimitMinor = 15_000_000
        try await harness.repository.saveAccount(limited, profileId: profileId)
        #expect(try await queued() == [name(.account, card.id): .save])
    }

    /// D68: a category of one's own travels; deleting it sends the operations moved to "Прочее".
    @Test func aCategoryAndItsDeletionAreSent() async throws {
        let card = Account(name: "Карта", currency: "RUB", type: .card, includeInFree: true)
        let profileId = try await harness.profile(accounts: [card])
        let cat = CustomCategory(name: "Кот", kind: .expense)
        try await harness.repository.saveCategory(cat, profileId: profileId)
        let fed = try await harness.repository.save(
            Draft(type: .expense, timestamp: 1, accountId: card.id, amountMinor: 100, categoryKey: cat.key), profileId: profileId
        )
        #expect(try await queued()[name(.category, cat.id)] == .save)
        try await harness.database.writer.write { db in try db.execute(sql: "DELETE FROM syncOutgoing") }
        try await harness.repository.deleteCategory(cat, profileId: profileId)
        #expect(try await queued() == [name(.category, cat.id): .delete, name(.operation, fed): .save])
    }

    /// D67: the server's fields of a profile's operations, by operation, tell who wrote each.
    @Test func theServerFieldsOfAProfilesOperationsAreReadByOperation() async throws {
        let profileId = try await harness.profile()
        let other = try await harness.profile("Семья")
        let operation = UUID()
        let zone = SyncZone.own(profileId)
        try await sync.setSystemFields(Data([1]), for: SyncRecordRef(zone: zone, type: .operation, id: operation))
        try await sync.setSystemFields(Data([2]), for: SyncRecordRef(zone: zone, type: .account, id: UUID()))
        try await sync.setSystemFields(Data([3]), for: SyncRecordRef(zone: .own(other), type: .operation, id: UUID()))
        #expect(try await sync.operationSystemFields(profileId: profileId) == [operation: Data([1])])
    }

    @Test func whatOnlyThisPhoneSeesIsNotSent() async throws {
        let profileId = try await harness.profile()
        let other = try await harness.profile("Семья")
        try await harness.database.writer.write { db in try db.execute(sql: "DELETE FROM syncOutgoing") }
        // The order of profiles and of operations with one timestamp is each phone's own.
        try await harness.database.write { store in
            var profile = try #require(try store.profile(profileId))
            profile.sort = 7
            try store.save(profile)
        }
        // A save that changes nothing sends nothing.
        try await harness.repository.renameProfile(other, to: "Семья")
        #expect(try await sync.outgoing().isEmpty)
    }

    @Test func deletingAProfileRemovesItsZoneNotItsRows() async throws {
        let card = Account.card("Карта")
        let profileId = try await harness.profile(accounts: [card])
        let other = try await harness.profile("Семья")
        try await harness.repository.deleteProfile(profileId)

        #expect(try await sync.zonesToRemove() == [.own(profileId)])
        #expect(try await sync.outgoing().allSatisfy { $0.ref.zone.profileId == other })
        try await sync.zoneRemoved(.own(profileId))
        #expect(try await sync.zonesToRemove().isEmpty)
    }

    @Test func profilesMadeBeforeSyncAreGivenToItWithEverythingInThem() async throws {
        let card = Account.card("Карта")
        let profileId = try await harness.profile(accounts: [card])
        _ = try await harness.repository.save(Draft(type: .income, timestamp: RepositoryHarness.start, accountId: card.id, amountMinor: 900), profileId: profileId)
        try await harness.repository.saveGoal(Goal(name: "Отпуск", targetMinor: 1, currency: "RUB", isMain: true), profileId: profileId)
        // As if they were written before this version: nothing queued.
        try await harness.database.writer.write { db in try db.execute(sql: "DELETE FROM syncOutgoing") }

        #expect(try await sync.registerProfiles(now: harness.clock.now) == [.own(profileId)])
        let types = try await sync.outgoing().map(\.ref.type)
        #expect(Set(types) == [.profile, .account, .operation, .goal])
        #expect(try await sync.registerProfiles(now: harness.clock.now).isEmpty, "once")
    }

    @Test func anOperationRecordCarriesItsPostings() async throws {
        let card = Account.card("Карта"), cash = Account.card("Наличные")
        let profileId = try await harness.profile(accounts: [card, cash])
        let id = try await harness.repository.save(
            Draft(type: .transfer, timestamp: RepositoryHarness.start, accountId: card.id, amountMinor: 100, toAccountId: cash.id),
            profileId: profileId
        )
        let record = try #require(try await sync.record(SyncRecordRef(zone: .own(profileId), type: .operation, id: id)))
        guard case .operation(let operation, let postings) = record.payload else { Issue.record("not an operation"); return }
        #expect(operation.type == .transfer)
        #expect(postings == (try await harness.operation(id, profileId))?.postings)
        // Another profile's zone does not read this profile's rows.
        #expect(try await sync.record(SyncRecordRef(zone: .own(UUID()), type: .operation, id: id)) == nil)
    }

    /// The operation and its postings are one unit for conflicts, so a change of a posting alone
    /// (a new amount) is a new version of its operation, stamped now.
    @Test func aChangeOfAPostingAloneIsANewVersionOfItsOperation() async throws {
        let card = Account.card("Карта")
        let profileId = try await harness.profile(accounts: [card])
        let id = try await harness.repository.save(Draft(type: .expense, timestamp: RepositoryHarness.start, accountId: card.id, amountMinor: 100), profileId: profileId)
        try await harness.database.writer.write { db in try db.execute(sql: "DELETE FROM syncOutgoing") }

        harness.clock.set(RepositoryHarness.start + 7_000)
        try await harness.repository.save(Draft(type: .expense, timestamp: RepositoryHarness.start, accountId: card.id, amountMinor: 250, id: id), profileId: profileId)
        let ref = SyncRecordRef(zone: .own(profileId), type: .operation, id: id)
        #expect(try await sync.outgoing().map(\.ref) == [ref])
        #expect(try await sync.record(ref)?.updatedAt == RepositoryHarness.start + 7_000)
    }

    @Test func aPostponedChangeIsNotDueBeforeTheServerSaid() async throws {
        let profileId = try await harness.profile()
        let ref = SyncRecordRef(zone: .own(profileId), type: .profile, id: profileId)
        #expect(try await sync.takeDue(at: harness.clock.now).map(\.ref) == [ref])
        try await sync.postpone([ref], until: harness.clock.now + 330_000)
        #expect(try await sync.takeDue(at: harness.clock.now + 329_999).isEmpty)
        #expect(try await sync.nextDue(after: harness.clock.now) == harness.clock.now + 330_000)
        #expect(try await sync.takeDue(at: harness.clock.now + 330_000).map(\.ref) == [ref])
    }

    @Test func anEditWhileTheSaveIsInFlightStaysQueued() async throws {
        let profileId = try await harness.profile()
        let ref = SyncRecordRef(zone: .own(profileId), type: .profile, id: profileId)
        _ = try await sync.takeDue(at: harness.clock.now)
        try await harness.repository.renameProfile(profileId, to: "Второе")
        try await sync.confirm(.save, of: ref)
        #expect(try await sync.takeDue(at: harness.clock.now).map(\.ref) == [ref])
        try await sync.confirm(.save, of: ref)
        #expect(try await sync.outgoing().isEmpty)
    }
}
