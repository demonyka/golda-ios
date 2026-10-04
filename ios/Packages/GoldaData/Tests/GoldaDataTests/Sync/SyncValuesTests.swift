import Foundation
import GoldaCore
import Testing

@testable import GoldaData

private let profileId = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!
private let otherId = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

private func profileRecord(_ name: String, at time: Int64, by device: String) -> SyncRecord {
    SyncRecord(zone: .own(profileId), payload: .profile(Profile(id: profileId, name: name)), updatedAt: time, authorDevice: device)
}

@Suite struct OutgoingQueueTests {
    private let ref = SyncRecordRef(zone: .own(profileId), type: .profile, id: profileId)

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

    @Test func aPostponedEntryWaitsAndIsHandedAgain() {
        var save = OutgoingQueue.merge(nil, kind: .save, ref: ref, now: 0)
        save.handedRevision = save.revision
        let postponed = OutgoingQueue.postponed(save, until: 330_000)
        #expect(!postponed.isDue(at: 329_999))
        #expect(postponed.isDue(at: 330_000))
        // A delete's undo window that ends later is not cut short.
        let delete = OutgoingQueue.merge(nil, kind: .delete, ref: ref, now: 0)
        #expect(OutgoingQueue.postponed(delete, until: 1).notBefore == OutgoingQueue.undoWindow)
    }
}

@Suite struct SyncZoneTests {
    @Test func aProfilesZoneIsNamedAfterItInLowercase() {
        let zone = SyncZone.own(profileId)
        #expect(zone.zoneName == "profile-6f9619ff-8b86-d011-b42d-00c04fc964ff")
        #expect(zone.ownerName == SyncZone.currentUser)
        #expect(zone.scope == .private)
        #expect(zone.isOwned)
    }

    @Test func aZoneNameReadsBackWhateverTheCase() {
        let upper = SyncZone(zoneName: "profile-6F9619FF-8B86-D011-B42D-00C04FC964FF", ownerName: "_abc", scope: .shared)
        #expect(upper == SyncZone(profileId: profileId, ownerName: "_abc", scope: .shared))
        #expect(upper?.isOwned == false)
    }

    @Test func zonesThatAreNotAProfilesAreNotRead() {
        #expect(SyncZone(zoneName: "_defaultZone", ownerName: SyncZone.currentUser, scope: .private) == nil)
        #expect(SyncZone(zoneName: "profile-not-a-uuid", ownerName: SyncZone.currentUser, scope: .private) == nil)
        #expect(SyncZone(zoneName: "account-6f9619ff-8b86-d011-b42d-00c04fc964ff", ownerName: "x", scope: .shared) == nil)
    }

    @Test func aRecordNameSaysItsTypeAndId() {
        let zone = SyncZone.own(profileId)
        for type in SyncRecordType.allCases {
            let ref = SyncRecordRef(zone: zone, type: type, id: otherId)
            #expect(ref.recordName == "\(type.rawValue).11111111-2222-3333-4444-555555555555")
            #expect(SyncRecordRef(recordName: ref.recordName, zone: zone) == ref)
        }
    }

    @Test func everyTableOfTheBooksHasItsRecordType() {
        #expect(SyncRecordType.allCases.map(\.rawValue) == ["Profile", "Account", "Operation", "Posting", "Obligation", "Goal", "Wish"])
        #expect(Set(SyncRecordType.allCases.map(\.tableName)) == Set(SyncSchema.syncedColumns.keys))
    }

    @Test func recordNamesThisVersionDoesNotKnowAreNotRead() {
        let zone = SyncZone.own(profileId)
        #expect(SyncRecordRef(recordName: "cloudkit.zoneshare", zone: zone) == nil)
        #expect(SyncRecordRef(recordName: "Budget.11111111-2222-3333-4444-555555555555", zone: zone) == nil)
        #expect(SyncRecordRef(recordName: "Operation.42", zone: zone) == nil)
    }

    @Test func theLaterWriterWinsAndEqualTimesFallToTheLargerDevice() {
        let early = profileRecord("Old", at: 100, by: "B")
        let late = profileRecord("New", at: 200, by: "A")
        #expect(SyncConflict.incomingWins(late, over: early))
        #expect(!SyncConflict.incomingWins(early, over: late))
        let fromA = profileRecord("A", at: 100, by: "A")
        let fromB = profileRecord("B", at: 100, by: "B")
        // Both phones pick B's, whichever side resolves.
        #expect(SyncConflict.incomingWins(fromB, over: fromA))
        #expect(!SyncConflict.incomingWins(fromA, over: fromB))
    }
}

@Suite struct SyncStateFileTests {
    @Test func engineStateAndTheQueueOutliveTheProcess() async throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "golda-sync-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "golda.sqlite")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let profile: Profile
        do {
            let database = try GoldaDatabase.open(at: url)
            let store = SyncStore(database: database)
            try await store.setEngineState(Data("private-1".utf8), for: .private)
            try await store.setEngineState(Data("shared-1".utf8), for: .shared)
            try await store.setEngineState(Data("private-2".utf8), for: .private)
            profile = Profile(name: "Личный")
            try await database.write { try $0.save(profile) }
        }
        let reopened = SyncStore(database: try GoldaDatabase.open(at: url))
        #expect(try await reopened.engineState(.private) == Data("private-2".utf8))
        #expect(try await reopened.engineState(.shared) == Data("shared-1".utf8))
        #expect(try await reopened.outgoing().map(\.kind) == [.save])
        let ref = SyncRecordRef(zone: .own(profile.id), type: .profile, id: profile.id)
        #expect(try await reopened.record(ref)?.payload == .profile(profile))
    }
}
