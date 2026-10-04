import CloudKit
import Foundation
import GoldaCore
import GoldaData
import Testing

@testable import GoldaSync

/// The CKRecord side is built locally, with no container: nothing here needs iCloud.
@Suite struct CloudKitMappingTests {
    @Test func theCurrentUsersOwnerNameIsCloudKits() {
        #expect(SyncZone.currentUser == CKCurrentUserDefaultName)
    }

    @Test func zonesAndRecordsMapToCloudKitIds() {
        let zone = SyncZone(profileId: Fixtures.profileId, ownerName: "_owner", scope: .shared)
        #expect(zone.zoneID == CKRecordZone.ID(zoneName: "profile-6f9619ff-8b86-d011-b42d-00c04fc964ff", ownerName: "_owner"))
        #expect(SyncZone(zoneID: zone.zoneID, scope: .shared) == zone)
        #expect(zone.shareRecordID.recordName == CKRecordNameZoneWideShare)
        let ref = SyncRecordRef(zone: zone, type: .posting, id: Fixtures.accountId)
        #expect(SyncRecordRef(recordID: ref.recordID, scope: .shared) == ref)
    }

    @Test func aProfileGoesThereAndBack() throws {
        let record = Fixtures.profile(at: 1_760_000_000_123, by: "iPhone17,5 · K3Q")
        let ck = CloudKitMapping.ckRecord(for: record, systemFields: nil)
        #expect(ck.recordType == "Profile")
        #expect(ck["updatedAt"] as? Int64 == 1_760_000_000_123)
        // What the person wrote is not in the plain fields.
        #expect(ck["name"] == nil)
        #expect(CloudKitMapping.syncRecord(from: ck, scope: .private) == record)
    }

    @Test func anOperationAndItsPostingGoThereAndBack() throws {
        let zone = SyncZone.own(Fixtures.profileId)
        var (operation, posting) = Fixtures.expense("Хинкали", 2500, in: zone, at: 5)
        if case .operation(var op, _) = operation.payload {
            op.voiceText = "хинкали двадцать пять лари"
            op.purchaseAmountMinor = 9000
            op.purchaseCurrency = "GEL"
            op.isEstimate = true
            op.cbrFrom = 29.5
            operation.payload = .operation(op, postingCount: 2)
        }
        posting.payload = .posting(Posting(operationId: operation.payload.id, accountId: Fixtures.accountId, amountMinor: Int64.min + 1, rubMinor: -1))
        for record in [operation, posting] {
            let ck = CloudKitMapping.ckRecord(for: record, systemFields: nil)
            #expect(CloudKitMapping.syncRecord(from: ck, scope: .private) == record)
        }
    }

    @Test func recordsThatAreNotOursAreSkipped() {
        let zone = SyncZone.own(Fixtures.profileId)
        let share = CKShare(recordZoneID: zone.zoneID)
        #expect(CloudKitMapping.syncRecord(from: share, scope: .private) == nil)
        // A profile record in another profile's zone, a record without the time.
        let stray = CloudKitMapping.ckRecord(for: Fixtures.profile(id: Fixtures.accountId, zone: zone), systemFields: nil)
        #expect(CloudKitMapping.syncRecord(from: stray, scope: .private) == nil)
        let bare = CKRecord(recordType: "Operation", recordID: SyncRecordRef(zone: zone, type: .operation, id: UUID()).recordID)
        #expect(CloudKitMapping.syncRecord(from: bare, scope: .private) == nil)
    }

    @Test func systemFieldsComeBackAsTheSameRecord() throws {
        let record = Fixtures.profile()
        let ck = CloudKitMapping.ckRecord(for: record, systemFields: nil)
        let data = CloudKitMapping.systemFields(of: ck)
        let restored = try #require(CloudKitMapping.record(fromSystemFields: data))
        #expect(restored.recordID == ck.recordID)
        #expect(restored.recordType == "Profile")
        // Saving on top of them writes the values again.
        let again = CloudKitMapping.ckRecord(for: record, systemFields: data)
        #expect(CloudKitMapping.syncRecord(from: again, scope: .private) == record)
    }

    @Test func systemFieldsOfAnotherRecordAreNotReused() {
        let other = CloudKitMapping.systemFields(of: CloudKitMapping.ckRecord(for: Fixtures.profile(), systemFields: nil))
        let (operation, _) = Fixtures.expense("Кофе", 300, in: .own(Fixtures.profileId))
        let ck = CloudKitMapping.ckRecord(for: operation, systemFields: other)
        #expect(ck.recordID == operation.ref.recordID)
    }
}
