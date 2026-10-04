import Foundation
import Testing

@testable import GoldaSync

/// The spike's script, run against the in-memory cloud: two people on two phones, one profile
/// shared between them.
@Suite struct TwoPhonesTests {
    private struct Phone {
        let store: SyncStore
        let transport: InMemorySyncTransport

        func sync() async throws {
            try await transport.sendNow()
            try await transport.fetchNow()
        }
    }

    private let clock = TestClock()
    private let cloud = InMemoryCloud()
    private let owner = Fixtures.profile("Семья", by: "A")
    private var ownZone: SyncZone { .own(Fixtures.profileId) }
    private var sharedZone: SyncZone { SyncZone(profileId: Fixtures.profileId, ownerName: "alice", scope: .shared) }

    private func phone(_ user: String, store: SyncStore? = nil) async throws -> Phone {
        let store = try store ?? SyncStore.inMemory()
        let transport = InMemorySyncTransport(cloud: cloud, user: user, store: store, now: clock.reader)
        try await transport.start()
        return Phone(store: store, transport: transport)
    }

    /// Alice creates the profile with one expense and shares it; Bob accepts.
    private func sharedPair() async throws -> (alice: Phone, bob: Phone) {
        let alice = try await phone("alice")
        let bob = try await phone("bob")
        try await alice.transport.createZone(ownZone)
        try await alice.store.save(owner, now: clock.now)
        let (op, posting) = Fixtures.expense("Хинкали", 2500, in: ownZone, by: "A")
        try await alice.store.save(op, now: clock.now)
        try await alice.store.save(posting, now: clock.now)
        try await alice.sync()
        await cloud.share(ownZone, of: "alice", with: "bob")
        try await bob.sync()
        return (alice, bob)
    }

    @Test func theParticipantReceivesTheWholeProfileInTheirSharedDatabase() async throws {
        let (_, bob) = try await sharedPair()
        let profiles = try await bob.store.profiles()
        #expect(profiles.map(\.zone) == [sharedZone])
        let records = try await bob.store.records(in: sharedZone)
        #expect(records.map(\.payload.type) == [.profile, .operation, .posting])
        #expect(records.first?.payload == owner.payload)
    }

    @Test func aRecordWrittenByEitherSideReachesTheOther() async throws {
        let (alice, bob) = try await sharedPair()
        clock.advance(1000)
        let (fromBob, _) = Fixtures.expense("Такси", 900, in: sharedZone, at: clock.now, by: "B")
        try await bob.store.save(fromBob, now: clock.now)
        try await bob.sync()
        try await alice.sync()
        let atAlice = try await alice.store.records(in: ownZone).compactMap(\.note)
        #expect(atAlice.sorted() == ["Такси", "Хинкали"])

        let (fromAlice, _) = Fixtures.expense("Кофе", 300, in: ownZone, at: clock.now, by: "A")
        try await alice.store.save(fromAlice, now: clock.now)
        try await alice.sync()
        try await bob.sync()
        #expect(try await bob.store.records(in: sharedZone).compactMap(\.note).sorted() == ["Кофе", "Такси", "Хинкали"])
    }

    @Test func aDeleteLeavesAfterTheUndoWindowAndAnUndoNeverLeaves() async throws {
        let (alice, bob) = try await sharedPair()
        let target = try #require(try await alice.store.records(in: ownZone).first { $0.payload.type == .operation })

        try await alice.store.delete(target.ref, now: clock.now)
        try await alice.sync()
        try await bob.sync()
        #expect(try await bob.store.records(in: sharedZone).contains { $0.payload.type == .operation }, "still in the undo window")

        // Undone in time: nothing reaches Bob.
        try await alice.store.save(target, now: clock.now + 1)
        clock.advance(OutgoingQueue.undoWindow + 1)
        try await alice.sync()
        try await bob.sync()
        #expect(try await bob.store.records(in: sharedZone).contains { $0.payload.type == .operation })

        try await alice.store.delete(target.ref, now: clock.now)
        clock.advance(OutgoingQueue.undoWindow)
        try await alice.sync()
        try await bob.sync()
        #expect(!(try await bob.store.records(in: sharedZone).contains { $0.payload.type == .operation }))
    }

    @Test func offlineEditsOnBothSidesSettleOnTheLaterOne() async throws {
        let (alice, bob) = try await sharedPair()
        let base = try #require(try await alice.store.records(in: ownZone).first { $0.payload.type == .operation })
        var atAlice = base
        var atBob = try #require(try await bob.store.record(SyncRecordRef(zone: sharedZone, type: .operation, id: base.payload.id)))

        // Both edit the same expense with no network; Bob's edit is the later one.
        if case .operation(var op, let count) = atAlice.payload { op.note = "Хинкали (A)"; atAlice.payload = .operation(op, postingCount: count) }
        atAlice.updatedAt = clock.now + 10
        if case .operation(var op, let count) = atBob.payload { op.note = "Хинкали (B)"; atBob.payload = .operation(op, postingCount: count) }
        atBob.updatedAt = clock.now + 20
        atBob.authorDevice = "B"
        try await alice.store.save(atAlice, now: clock.now)
        try await bob.store.save(atBob, now: clock.now)

        // Alice reaches the server first; Bob's save then conflicts, and his later edit wins.
        try await alice.sync()
        try await bob.sync()
        try await alice.sync()
        #expect(try await alice.store.record(base.ref)?.note == "Хинкали (B)")
        #expect(try await bob.store.record(atBob.ref)?.note == "Хинкали (B)")
        #expect(await cloud.record(base.ref, ownedBy: "alice")?.note == "Хинкали (B)")
        #expect(try await alice.store.outgoing().isEmpty)
        #expect(try await bob.store.outgoing().isEmpty)
    }

    @Test func theParticipantLeavesAndTheOwnerKeepsTheProfile() async throws {
        let (alice, bob) = try await sharedPair()
        try await bob.transport.removeZone(sharedZone)
        #expect(try await bob.store.profiles().isEmpty)
        try await alice.sync()
        try await bob.sync()
        #expect(try await alice.store.profiles().map(\.zone) == [ownZone])
        #expect(try await bob.store.profiles().isEmpty)
    }

    @Test func stoppingSharingTakesTheProfileFromTheParticipantOnly() async throws {
        let (alice, bob) = try await sharedPair()
        try await alice.transport.stopSharing(ownZone)
        try await bob.sync()
        try await alice.sync()
        #expect(try await bob.store.profiles().isEmpty)
        #expect(try await alice.store.records(in: ownZone).count == 3)
    }

    @Test func theOwnerDeletingTheProfileTakesItFromEveryone() async throws {
        let (alice, bob) = try await sharedPair()
        try await alice.transport.removeZone(ownZone)
        try await alice.sync()
        try await bob.sync()
        #expect(try await alice.store.profiles().isEmpty)
        #expect(try await bob.store.profiles().isEmpty)
    }

    @Test func aNewProcessResumesFromTheSavedCursorAndQueue() async throws {
        let (alice, bob) = try await sharedPair()
        // Bob writes with no network, then the app is killed.
        let (offline, _) = Fixtures.expense("Офлайн", 100, in: sharedZone, by: "B")
        try await bob.store.save(offline, now: clock.now)
        await bob.transport.outgoingChanged()

        let relaunched = try await phone("bob", store: bob.store)
        try await relaunched.sync()
        try await alice.sync()
        #expect(try await alice.store.records(in: ownZone).compactMap(\.note).contains("Офлайн"))
        // The cursor came back: nothing old arrives again as new.
        #expect(try await relaunched.store.records(in: sharedZone).count == 4)
    }
}
