import CloudKit
import Foundation
import GoldaData
import Testing

@testable import GoldaSync

/// The seed is what the Development schema learns from before it goes to Production, where a field
/// the schema lacks fails the save: every type, with every field the mapping can write.
@Suite struct CloudKitSchemaSeedTests {
    @Test func everyTypeIsThereOnceInTheSeedZone() {
        let records = CloudKitSchemaSeed.records()
        #expect(records.map(\.recordType).sorted() == SyncRecordType.allCases.map(\.rawValue).sorted())
        #expect(records.allSatisfy { $0.recordID.zoneID == CloudKitSchemaSeed.zoneID })
        // Not a profile's zone, so a sync engine that sees it ignores it.
        #expect(SyncZone(zoneID: CloudKitSchemaSeed.zoneID, scope: .private) == nil)
    }

    /// The optional fields are written only when they have a value, so the seed fills each of them.
    @Test func everyOptionalFieldHasAValue() {
        let fields = Dictionary(uniqueKeysWithValues: CloudKitSchemaSeed.records().map {
            ($0.recordType, Set($0.allKeys() + $0.encryptedValues.allKeys()))
        })
        let optional: [SyncRecordType: Set<String>] = [
            .account: ["groupName", "interestRate", "paymentDay", "paymentMinor", "graceUntil", "reconciledAt"],
            .operation: ["categoryKey", "voiceText", "purchaseAmountMinor", "purchaseCurrency", "cbrFrom", "cbrTo", "postings"],
            .goal: ["accountId"],
            .wish: ["decidedAt"],
        ]
        for (type, keys) in optional {
            #expect(fields[type.rawValue]?.isSuperset(of: keys) == true, "\(type): \(fields[type.rawValue] ?? [])")
        }
        #expect(fields.values.allSatisfy { $0.isSuperset(of: ["updatedAt", "authorDevice"]) })
    }
}
