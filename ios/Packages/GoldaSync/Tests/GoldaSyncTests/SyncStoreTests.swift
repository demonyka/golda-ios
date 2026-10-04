import Foundation
import Testing

@testable import GoldaSync

@Suite struct OutgoingQueueTests {
    private let ref = Fixtures.profile().ref

    @Test func aSaveIsDueAtOnceADeleteAfterTheUndoWindow() {
        let save = OutgoingQueue.merge(nil, kind: .save, ref: ref, now: 1000)
        #expect(save.isDue(at: 1000))
        let delete = OutgoingQueue.merge(nil, kind: .delete, ref: ref, now: 1000)
        #expect(!delete.isDue(at: 1000 + OutgoingQueue.undoWindow - 1))
        #expect(delete.isDue(at: 1000 + OutgoingQueue.undoWindow))
    }

    @Test func theLatestWishWinsAndTheRevisionGrows() {
        let save = OutgoingQueue.merge(nil, kind: .save, ref: ref, now: 0)
        let delete = OutgoingQueue.merge(save, kind: .delete, ref: ref, now: 5)
        #expect(delete.kind == .delete)
        #expect(delete.revision == 2)
        let undone = OutgoingQueue.merge(delete, kind: .save, ref: ref, now: 6)
        #expect(undone.kind == .save)
        #expect(undone.notBefore == 6)
        #expect(undone.revision == 3)
    }

    @Test func aHandedEntryIsNotDueAgainUntilItChanges() {
        var save = OutgoingQueue.merge(nil, kind: .save, ref: ref, now: 0)
        save.handedRevision = save.revision
        #expect(!save.isDue(at: 10))
        #expect(OutgoingQueue.isSettled(save, by: .save))
        #expect(!OutgoingQueue.isSettled(save, by: .delete))
        let edited = OutgoingQueue.merge(save, kind: .save, ref: ref, now: 10)
        #expect(edited.isDue(at: 10))
        #expect(!OutgoingQueue.isSettled(edited, by: .save))
    }
}

@Suite struct SyncStoreTests {
    private let clock = TestClock()

    @Test func engineStateOutlivesTheProcess() async throws {
        let url = Fixtures.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        do {
            let store = try SyncStore.open(at: url)
            try await store.setEngineState(Data("private-1".utf8), for: .private)
            try await store.setEngineState(Data("shared-1".utf8), for: .shared)
            try await store.setEngineState(Data("private-2".utf8), for: .private)
            try await store.save(Fixtures.profile(), now: clock.now)
        }
        let reopened = try SyncStore.open(at: url)
        #expect(try await reopened.engineState(.private) == Data("private-2".utf8))
        #expect(try await reopened.engineState(.shared) == Data("shared-1".utf8))
        #expect(try await reopened.outgoing().map(\.kind) == [.save])
        #expect(try await reopened.record(Fixtures.profile().ref) == Fixtures.profile())
    }

    @Test func aSaveWritesTheRecordAndQueuesIt() async throws {
        let store = try SyncStore.inMemory()
        let profile = Fixtures.profile()
        try await store.save(profile, now: clock.now)
        #expect(try await store.profiles() == [profile])
        let due = try await store.takeDue(at: clock.now)
        #expect(due.map(\.ref) == [profile.ref])
        #expect(try await store.takeDue(at: clock.now).isEmpty, "handed over once")
        try await store.confirm(.save, of: profile.ref)
        #expect(try await store.outgoing().isEmpty)
    }

    @Test func anEditWhileTheSaveIsInFlightStaysQueued() async throws {
        let store = try SyncStore.inMemory()
        try await store.save(Fixtures.profile("Первое"), now: clock.now)
        _ = try await store.takeDue(at: clock.now)
        try await store.save(Fixtures.profile("Второе", at: 2), now: clock.now)
        try await store.confirm(.save, of: Fixtures.profile().ref)
        let left = try await store.takeDue(at: clock.now)
        #expect(left.count == 1)
    }

    @Test func aDeleteWaitsForTheUndoWindowAndAnUndoCancelsIt() async throws {
        let store = try SyncStore.inMemory()
        let zone = SyncZone.own(Fixtures.profileId)
        let (operation, _) = Fixtures.expense("Кофе", 300, in: zone)
        try await store.save(operation, now: clock.now)
        _ = try await store.takeDue(at: clock.now)
        try await store.confirm(.save, of: operation.ref)

        try await store.delete(operation.ref, now: clock.now)
        #expect(try await store.record(operation.ref) == nil, "gone here at once")
        #expect(try await store.takeDue(at: clock.now).isEmpty)
        #expect(try await store.nextDue(after: clock.now) == clock.now + OutgoingQueue.undoWindow)

        // "Отменить": the save replaces the delete before it left.
        try await store.save(operation, now: clock.now + 1)
        let due = try await store.takeDue(at: clock.now + 1)
        #expect(due.map(\.kind) == [.save])
        #expect(try await store.record(operation.ref) == operation)
    }

    @Test func incomingRecordsFollowTheLastWriter() async throws {
        let store = try SyncStore.inMemory()
        let mine = Fixtures.profile("Моё", at: 200, by: "A")
        try await store.save(mine, now: clock.now)

        // Older than the local edit still waiting: this phone's version stays and goes again.
        let older = Fixtures.profile("Старое", at: 100, by: "B")
        #expect(try await store.apply([older]) == [mine.ref])
        #expect(try await store.record(mine.ref) == mine)

        // Newer: it replaces the local edit, which no longer needs sending.
        let newer = Fixtures.profile("Новое", at: 300, by: "B")
        #expect(try await store.apply([newer]).isEmpty)
        #expect(try await store.record(mine.ref) == newer)
        #expect(try await store.outgoing().isEmpty)
    }

    @Test func aLocalDeleteStandsAndARemoteDeleteRemoves() async throws {
        let store = try SyncStore.inMemory()
        let zone = SyncZone.own(Fixtures.profileId)
        let (coffee, _) = Fixtures.expense("Кофе", 300, in: zone)
        let (tea, _) = Fixtures.expense("Чай", 200, in: zone)
        try await store.apply([coffee, tea])
        try await store.delete(coffee.ref, now: clock.now)

        #expect(try await store.apply([coffee], deletions: [tea.ref]) == [coffee.ref])
        #expect(try await store.record(coffee.ref) == nil)
        #expect(try await store.record(tea.ref) == nil)
        #expect(try await store.outgoing().map(\.kind) == [.delete])
    }

    @Test func removingAZoneKeepsTheOthers() async throws {
        let store = try SyncStore.inMemory()
        let mine = SyncZone.own(Fixtures.profileId)
        // The shared zone of the same name differs only by its owner and scope.
        let theirs = SyncZone(profileId: Fixtures.profileId, ownerName: "_owner", scope: .shared)
        let other = SyncZone.own(UUID())
        let (a, _) = Fixtures.expense("A", 1, in: mine)
        let (b, _) = Fixtures.expense("B", 1, in: theirs)
        let (c, _) = Fixtures.expense("C", 1, in: other)
        for record in [a, b, c] { try await store.save(record, now: clock.now) }
        try await store.setSystemFields(Data([1]), for: a.ref)

        try await store.removeZone(mine)
        #expect(try await store.records(in: mine).isEmpty)
        #expect(try await store.records(in: theirs) == [b])
        #expect(try await store.records(in: other) == [c])
        #expect(try await store.systemFields(a.ref) == nil)
        #expect(Set(try await store.outgoing().map(\.ref)) == [b.ref, c.ref])
    }

    @Test func rehandingHandsTheEntriesOverAgain() async throws {
        let store = try SyncStore.inMemory()
        try await store.save(Fixtures.profile(), now: clock.now)
        _ = try await store.takeDue(at: clock.now)
        try await store.rehand()
        #expect(try await store.takeDue(at: clock.now).count == 1)
    }

    @Test func wipingForgetsEverything() async throws {
        let store = try SyncStore.inMemory()
        try await store.save(Fixtures.profile(), now: clock.now)
        try await store.setEngineState(Data([1]), for: .shared)
        try await store.wipe()
        #expect(try await store.profiles().isEmpty)
        #expect(try await store.outgoing().isEmpty)
        #expect(try await store.engineState(.shared) == nil)
    }
}
