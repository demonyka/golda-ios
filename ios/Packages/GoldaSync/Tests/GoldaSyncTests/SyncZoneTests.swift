import Foundation
import Testing

@testable import GoldaSync

@Suite struct SyncZoneTests {
    @Test func aProfilesZoneIsNamedAfterItInLowercase() {
        let zone = SyncZone.own(Fixtures.profileId)
        #expect(zone.zoneName == "profile-6f9619ff-8b86-d011-b42d-00c04fc964ff")
        #expect(zone.ownerName == SyncZone.currentUser)
        #expect(zone.scope == .private)
        #expect(zone.isOwned)
    }

    @Test func aZoneNameReadsBackWhateverTheCase() {
        let upper = SyncZone(zoneName: "profile-6F9619FF-8B86-D011-B42D-00C04FC964FF", ownerName: "_abc", scope: .shared)
        #expect(upper == SyncZone(profileId: Fixtures.profileId, ownerName: "_abc", scope: .shared))
        #expect(upper?.isOwned == false)
    }

    @Test func zonesThatAreNotAProfilesAreNotRead() {
        #expect(SyncZone(zoneName: "_defaultZone", ownerName: SyncZone.currentUser, scope: .private) == nil)
        #expect(SyncZone(zoneName: "profile-not-a-uuid", ownerName: SyncZone.currentUser, scope: .private) == nil)
        #expect(SyncZone(zoneName: "account-6f9619ff-8b86-d011-b42d-00c04fc964ff", ownerName: "x", scope: .shared) == nil)
    }

    @Test func aRecordNameSaysItsTypeAndId() throws {
        let zone = SyncZone.own(Fixtures.profileId)
        for type in SyncRecordType.allCases {
            let ref = SyncRecordRef(zone: zone, type: type, id: Fixtures.accountId)
            #expect(ref.recordName == "\(type.rawValue).11111111-2222-3333-4444-555555555555")
            #expect(SyncRecordRef(recordName: ref.recordName, zone: zone) == ref)
        }
    }

    @Test func recordNamesThisVersionDoesNotKnowAreNotRead() {
        let zone = SyncZone.own(Fixtures.profileId)
        #expect(SyncRecordRef(recordName: "cloudkit.zoneshare", zone: zone) == nil)
        #expect(SyncRecordRef(recordName: "Goal.11111111-2222-3333-4444-555555555555", zone: zone) == nil)
        #expect(SyncRecordRef(recordName: "Operation.42", zone: zone) == nil)
    }

    @Test func aRecordsRefFollowsItsPayload() {
        let zone = SyncZone.own(Fixtures.profileId)
        let (operation, posting) = Fixtures.expense("Хинкали", 2500, in: zone)
        #expect(operation.ref.type == .operation)
        #expect(posting.ref.type == .posting)
        #expect(Fixtures.profile().ref == SyncRecordRef(zone: zone, type: .profile, id: Fixtures.profileId))
    }

    @Test func theLaterWriterWinsAndEqualTimesFallToTheLargerDevice() {
        let early = Fixtures.profile("Old", at: 100, by: "B")
        let late = Fixtures.profile("New", at: 200, by: "A")
        #expect(SyncConflict.incomingWins(late, over: early))
        #expect(!SyncConflict.incomingWins(early, over: late))
        let fromA = Fixtures.profile("A", at: 100, by: "A")
        let fromB = Fixtures.profile("B", at: 100, by: "B")
        // Both phones pick B's, whichever side resolves.
        #expect(SyncConflict.incomingWins(fromB, over: fromA))
        #expect(!SyncConflict.incomingWins(fromA, over: fromB))
    }
}
