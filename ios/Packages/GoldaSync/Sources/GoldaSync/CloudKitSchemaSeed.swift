import CloudKit
import Foundation
import GoldaCore
import GoldaData

/// One record of every type with every field filled, for the Development schema to learn from.
///
/// Development creates a type or a field the first time a save carries it; Production never does,
/// and a save with a field its schema lacks fails. The optional fields travel only when they have a
/// value, so ordinary use leaves gaps (a goal never saved, an operation never bought abroad). A debug
/// build saves these to a zone of their own and deletes the zone, and the schema is complete before
/// it is deployed (stage 6).
public enum CloudKitSchemaSeed {
    /// Not a profile's zone (`profile-<uuid>`), so the sync engines pass over it.
    public static let zoneID = CKRecordZone.ID(zoneName: "schema-seed", ownerName: CKCurrentUserDefaultName)

    public static func records() -> [CKRecord] {
        let zone = SyncZone.own(UUID())
        let accountId = UUID()
        let operationId = UUID()
        let payloads: [SyncPayload] = [
            .profile(Profile(name: "Seed", sort: 1, settings: ProfileSettings())),
            .account(Account(
                id: accountId, name: "Seed", currency: "GEL", type: .credit, groupName: "Seed", includeInFree: true,
                interestRate: 1, sort: 1, paymentDay: 1, paymentMinor: 1, graceUntil: 1, reconciledAt: 1
            )),
            .operation(
                GoldaCore.Operation(
                    id: operationId, type: .expense, timestamp: 1, categoryKey: "food", note: "Seed", voiceText: "Seed",
                    purchaseAmountMinor: 1, purchaseCurrency: "GEL", isEstimate: true, cbrFrom: 1, cbrTo: 1
                ),
                postings: [Posting(operationId: operationId, accountId: accountId, amountMinor: -1, rubMinor: -1)]
            ),
            .obligation(Obligation(name: "Seed", amountMinor: 1, currency: "GEL", dayOfMonth: 1), createdAt: 1),
            .goal(Goal(name: "Seed", targetMinor: 1, currency: "GEL", accountId: accountId, savedMinor: 1, isMain: true), createdAt: 1),
            .wish(Wish(title: "Seed", amountMinor: 1, currency: "GEL", createdAt: 1, decideAt: 1, status: .bought, decidedAt: 1)),
        ]
        return payloads.map { payload in
            let mapped = CloudKitMapping.ckRecord(
                for: SyncRecord(zone: zone, payload: payload, updatedAt: 1, authorDevice: "seed"), systemFields: nil
            )
            let record = CKRecord(recordType: mapped.recordType, recordID: CKRecord.ID(recordName: mapped.recordID.recordName, zoneID: zoneID))
            for key in mapped.allKeys() { record[key] = mapped[key] }
            for key in mapped.encryptedValues.allKeys() { record.encryptedValues[key] = mapped.encryptedValues[key] }
            return record
        }
    }

    /// Saves the seed to its zone in [container]'s private database, then deletes the zone with it.
    public static func run(in container: CKContainer) async throws {
        let database = container.privateCloudDatabase
        _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
        let (saved, _) = try await database.modifyRecords(saving: records(), deleting: [], savePolicy: .allKeys)
        for (_, result) in saved { _ = try result.get() }
        _ = try await database.modifyRecordZones(saving: [], deleting: [zoneID])
    }
}
