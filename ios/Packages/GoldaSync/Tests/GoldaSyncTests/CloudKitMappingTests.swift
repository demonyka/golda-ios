import CloudKit
import Foundation
import GoldaCore
import GoldaData
import Testing

@testable import GoldaSync

/// The CKRecord side is built locally, with no container: nothing here needs iCloud.
@Suite struct CloudKitMappingTests {
    private static let profileId = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!
    private static let accountId = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let zone = SyncZone.own(CloudKitMappingTests.profileId)

    private func record(_ payload: SyncPayload, at time: Int64 = 1_760_000_000_123) -> SyncRecord {
        SyncRecord(zone: zone, payload: payload, updatedAt: time, authorDevice: "a1b2c3d4e5f6")
    }

    /// One of each, with every optional field filled, and one with every optional field empty.
    private var everyKind: [SyncPayload] {
        let operationId = UUID()
        return [
            .profile(Profile(id: Self.profileId, name: "Семья", sort: 2, settings: ProfileSettings(
                incomeHourly: true, hourlyRate: 1500.5, monthlySalary: 0, taxPercent: 13, hoursPerWeek: 40, payday: 10, markup: 0.02
            ))),
            .account(Account(
                id: Self.accountId, name: "Кредитка", currency: "GEL", type: .credit, groupName: "TBC", includeInFree: false,
                interestRate: 24.9, sort: 3, paymentDay: 15, paymentMinor: 50_000, graceUntil: 20_400, reconciledAt: 1_759_000_000_000,
                creditLimitMinor: 15_000_000
            )),
            .account(Account(name: "Наличные", currency: "RUB", type: .cash, includeInFree: true)),
            .operation(
                GoldaCore.Operation(
                    id: operationId, type: .transfer, timestamp: 5, categoryKey: "food", note: "Хинкали",
                    voiceText: "хинкали двадцать пять лари", purchaseAmountMinor: 9000, purchaseCurrency: "GEL", isEstimate: true,
                    cbrFrom: 29.5, cbrTo: 1
                ),
                postings: [
                    Posting(operationId: operationId, accountId: Self.accountId, amountMinor: Int64.min + 1, rubMinor: -1),
                    Posting(operationId: operationId, accountId: UUID(), amountMinor: Int64.max, rubMinor: 0),
                ]
            ),
            .operation(GoldaCore.Operation(type: .opening, timestamp: 0), postings: []),
            .obligation(Obligation(name: "Аренда", amountMinor: 3_000_000, currency: "RUB", dayOfMonth: 5), createdAt: 4),
            .goal(Goal(name: "Отпуск", targetMinor: 1, currency: "USD", accountId: Self.accountId, savedMinor: 7, isMain: true), createdAt: 2),
            .goal(Goal(name: "Без счёта", targetMinor: 1, currency: "USD"), createdAt: 3),
            .wish(Wish(title: "Велосипед", amountMinor: 1, currency: "RUB", createdAt: 1, decideAt: 2, status: .skipped, decidedAt: 3)),
            .wish(Wish(title: "", amountMinor: 1, currency: "RUB", createdAt: 1, decideAt: 2)),
            .category(CustomCategory(name: "Кот", kind: .expense, hint: "корм, ветеринар", symbol: "cat"), createdAt: 1),
            .category(CustomCategory(name: "Аренда", kind: .income), createdAt: 2),
        ]
    }

    @Test func theCurrentUsersOwnerNameIsCloudKits() {
        #expect(SyncZone.currentUser == CKCurrentUserDefaultName)
    }

    @Test func zonesAndRecordsMapToCloudKitIds() {
        let zone = SyncZone(profileId: Self.profileId, ownerName: "_owner", scope: .shared)
        #expect(zone.zoneID == CKRecordZone.ID(zoneName: "profile-6f9619ff-8b86-d011-b42d-00c04fc964ff", ownerName: "_owner"))
        #expect(SyncZone(zoneID: zone.zoneID, scope: .shared) == zone)
        #expect(zone.shareRecordID.recordName == CKRecordNameZoneWideShare)
        let ref = SyncRecordRef(zone: zone, type: .wish, id: Self.accountId)
        #expect(SyncRecordRef(recordID: ref.recordID, scope: .shared) == ref)
    }

    @Test func everyKindOfRecordGoesThereAndBack() {
        for payload in everyKind {
            let original = record(payload)
            let ck = CloudKitMapping.ckRecord(for: original, systemFields: nil)
            #expect(ck.recordType == payload.type.rawValue)
            #expect(ck["updatedAt"] as? Int64 == 1_760_000_000_123)
            #expect(CloudKitMapping.syncRecord(from: ck, scope: .private) == original, "\(payload)")
        }
    }

    @Test func whatThePersonWroteIsOnlyInTheEncryptedValues() {
        for payload in everyKind {
            let ck = CloudKitMapping.ckRecord(for: record(payload), systemFields: nil)
            let hidden = ck.encryptedValues.allKeys()
            #expect(!hidden.isEmpty)
            #expect(hidden.allSatisfy { ck[$0] == nil }, "\(payload.type) has a plain copy")
            #expect(!hidden.contains("updatedAt"))
        }
    }

    @Test func recordsThatAreNotOursAreSkipped() {
        let share = CKShare(recordZoneID: zone.zoneID)
        #expect(CloudKitMapping.syncRecord(from: share, scope: .private) == nil)
        // A profile record in another profile's zone, a record without the time.
        var stray = record(.profile(Profile(id: Self.accountId, name: "x")))
        stray.zone = zone
        #expect(CloudKitMapping.syncRecord(from: CloudKitMapping.ckRecord(for: stray, systemFields: nil), scope: .private) == nil)
        let bare = CKRecord(recordType: "Operation", recordID: SyncRecordRef(zone: zone, type: .operation, id: UUID()).recordID)
        #expect(CloudKitMapping.syncRecord(from: bare, scope: .private) == nil)
        // An operation of the first 5b builds: a count of postings sent apart, not the postings.
        let legacy = CloudKitMapping.ckRecord(for: record(everyKind[4]), systemFields: nil)
        legacy.encryptedValues["postings"] = nil
        legacy.encryptedValues["postingCount"] = Int64(1)
        #expect(CloudKitMapping.syncRecord(from: legacy, scope: .private) == nil)
        let posting = CKRecord(recordType: "Posting", recordID: CKRecord.ID(recordName: "Posting.\(UUID().uuidString.lowercased())", zoneID: zone.zoneID))
        #expect(CloudKitMapping.syncRecord(from: posting, scope: .private) == nil)
    }

    @Test func systemFieldsComeBackAsTheSameRecord() throws {
        let original = record(everyKind[0])
        let ck = CloudKitMapping.ckRecord(for: original, systemFields: nil)
        let data = CloudKitMapping.systemFields(of: ck)
        let restored = try #require(CloudKitMapping.record(fromSystemFields: data))
        #expect(restored.recordID == ck.recordID)
        #expect(restored.recordType == "Profile")
        // Saving on top of them writes the values again.
        let again = CloudKitMapping.ckRecord(for: original, systemFields: data)
        #expect(CloudKitMapping.syncRecord(from: again, scope: .private) == original)
    }

    @Test func systemFieldsOfAnotherRecordAreNotReused() {
        let other = CloudKitMapping.systemFields(of: CloudKitMapping.ckRecord(for: record(everyKind[0]), systemFields: nil))
        let operation = record(everyKind[3])
        let ck = CloudKitMapping.ckRecord(for: operation, systemFields: other)
        #expect(ck.recordID == operation.ref.recordID)
    }

    /// The owner's first share on 2026-10-04 failed with `quotaExceeded` and "retry after 330 s":
    /// the time to wait is what counts (D58).
    @Test func cloudKitErrorsBecomeWhatThePersonCanDo() {
        let wait = CKError(.quotaExceeded, userInfo: [CKErrorRetryAfterKey: 329.4])
        #expect(SyncProblem(wait) == .retryLater(seconds: 330))
        #expect(SyncProblem(CKError(.quotaExceeded)) == .iCloudFull)
        #expect(SyncProblem(CKError(.notAuthenticated)) == .noAccount)
        #expect(SyncProblem(CKError(.networkUnavailable)) == .offline)
        #expect(SyncProblem(CKError(.permissionFailure)) == .notPermitted)
        #expect(SyncProblem(URLError(.notConnectedToInternet)) == .offline)
        #expect(SyncProblem(CKError(.badContainer)) == .other(code: CKError.Code.badContainer.rawValue))
        let partial = CKError(.partialFailure, userInfo: [CKPartialErrorsByItemIDKey: ["x": CKError(.quotaExceeded)]])
        #expect(SyncProblem(partial) == .iCloudFull)
    }

    /// D67: who created a record comes from the server's fields; one the server never saw, or
    /// fields that cannot be read, have no creator yet.
    @Test func aRecordTheServerNeverSawHasNoCreator() {
        let ck = CloudKitMapping.ckRecord(for: record(everyKind[3]), systemFields: nil)
        #expect(CloudKitMapping.creator(ofSystemFields: CloudKitMapping.systemFields(of: ck)) == nil)
        #expect(CloudKitMapping.creator(ofSystemFields: Data([1, 2, 3])) == nil)
    }
}
