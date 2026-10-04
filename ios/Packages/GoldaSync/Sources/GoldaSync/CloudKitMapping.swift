import CloudKit
import Foundation
import GoldaCore
import GoldaData

extension SyncScope {
    init?(_ scope: CKDatabase.Scope) {
        switch scope {
        case .private: self = .private
        case .shared: self = .shared
        default: return nil
        }
    }
}

extension SyncZone {
    public var zoneID: CKRecordZone.ID { CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName) }

    public init?(zoneID: CKRecordZone.ID, scope: SyncScope) {
        self.init(zoneName: zoneID.zoneName, ownerName: zoneID.ownerName, scope: scope)
    }

    /// The zone's one share (`CKShare(recordZoneID:)`), which always has this name.
    public var shareRecordID: CKRecord.ID { CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID) }
}

extension SyncRecordRef {
    public var recordID: CKRecord.ID { CKRecord.ID(recordName: recordName, zoneID: zone.zoneID) }

    public init?(recordID: CKRecord.ID, scope: SyncScope) {
        guard let zone = SyncZone(zoneID: recordID.zoneID, scope: scope) else { return nil }
        self.init(recordName: recordID.recordName, zone: zone)
    }
}

/// `SyncRecord` to `CKRecord` and back.
///
/// What the person wrote (names, notes, amounts, settings) goes into `encryptedValues`, so it is
/// end-to-end encrypted when the account has Advanced Data Protection and never readable in the
/// CloudKit console; only `updatedAt` and `authorDevice` stay plain. Money is `Int64` minor units;
/// flags are 0 and 1.
public enum CloudKitMapping {
    enum Field {
        static let updatedAt = "updatedAt"
        static let authorDevice = "authorDevice"
    }

    /// [record] as a CKRecord, on top of the server's [systemFields] when the server has seen it,
    /// so the save carries the change tag it is based on.
    public static func ckRecord(for record: SyncRecord, systemFields: Data?) -> CKRecord {
        let ref = record.ref
        let ck = systemFields.flatMap(Self.record(fromSystemFields:)).flatMap { $0.recordID == ref.recordID ? $0 : nil }
            ?? CKRecord(recordType: ref.type.rawValue, recordID: ref.recordID)
        ck[Field.updatedAt] = record.updatedAt
        ck[Field.authorDevice] = record.authorDevice
        let values = ck.encryptedValues
        switch record.payload {
        case .profile(let profile):
            values["name"] = profile.name
            values["sort"] = Int64(profile.sort)
            values["incomeHourly"] = profile.settings.incomeHourly ? Int64(1) : Int64(0)
            values["hourlyRate"] = profile.settings.hourlyRate
            values["monthlySalary"] = profile.settings.monthlySalary
            values["taxPercent"] = profile.settings.taxPercent
            values["hoursPerWeek"] = profile.settings.hoursPerWeek
            values["payday"] = Int64(profile.settings.payday)
            values["markup"] = profile.settings.markup
        case .operation(let op, let postingCount):
            values["type"] = op.type.rawValue
            values["timestamp"] = op.timestamp
            values["categoryKey"] = op.categoryKey
            values["note"] = op.note
            values["voiceText"] = op.voiceText
            values["purchaseAmountMinor"] = op.purchaseAmountMinor
            values["purchaseCurrency"] = op.purchaseCurrency
            values["isEstimate"] = op.isEstimate ? Int64(1) : Int64(0)
            values["cbrFrom"] = op.cbrFrom
            values["cbrTo"] = op.cbrTo
            values["postingCount"] = Int64(postingCount)
        case .posting(let posting):
            values["operationId"] = posting.operationId.uuidString.lowercased()
            values["accountId"] = posting.accountId.uuidString.lowercased()
            values["amountMinor"] = posting.amountMinor
            values["rubMinor"] = posting.rubMinor
        }
        return ck
    }

    /// The record [ck] holds, or nil when it is not one of ours (the zone's `CKShare`, a type of a
    /// later version) or lacks a field this version needs.
    public static func syncRecord(from ck: CKRecord, scope: SyncScope) -> SyncRecord? {
        guard let ref = SyncRecordRef(recordID: ck.recordID, scope: scope), ref.type.rawValue == ck.recordType,
              let updatedAt = ck[Field.updatedAt] as? Int64
        else { return nil }
        let author = ck[Field.authorDevice] as? String ?? ""
        let values = ck.encryptedValues
        let payload: SyncPayload
        switch ref.type {
        case .profile:
            // The zone's root has the zone's profile id, whatever its record says.
            guard ref.id == ref.zone.profileId, let name = values["name"] as? String else { return nil }
            let defaults = ProfileSettings()
            payload = .profile(Profile(
                id: ref.id, name: name, sort: Int(values["sort"] as? Int64 ?? 0),
                settings: ProfileSettings(
                    incomeHourly: (values["incomeHourly"] as? Int64 ?? 0) != 0,
                    hourlyRate: values["hourlyRate"] as? Double ?? defaults.hourlyRate,
                    monthlySalary: values["monthlySalary"] as? Double ?? defaults.monthlySalary,
                    taxPercent: values["taxPercent"] as? Double ?? defaults.taxPercent,
                    hoursPerWeek: values["hoursPerWeek"] as? Double ?? defaults.hoursPerWeek,
                    payday: Int(values["payday"] as? Int64 ?? Int64(defaults.payday)),
                    markup: values["markup"] as? Double ?? defaults.markup
                )
            ))
        case .operation:
            guard let type = (values["type"] as? String).flatMap(OpType.init(rawValue:)),
                  let timestamp = values["timestamp"] as? Int64,
                  let postingCount = values["postingCount"] as? Int64
            else { return nil }
            payload = .operation(
                GoldaCore.Operation(
                    id: ref.id, type: type, timestamp: timestamp, categoryKey: values["categoryKey"] as? String,
                    note: values["note"] as? String ?? "", voiceText: values["voiceText"] as? String,
                    purchaseAmountMinor: values["purchaseAmountMinor"] as? Int64,
                    purchaseCurrency: values["purchaseCurrency"] as? String,
                    isEstimate: (values["isEstimate"] as? Int64 ?? 0) != 0,
                    cbrFrom: values["cbrFrom"] as? Double, cbrTo: values["cbrTo"] as? Double
                ),
                postingCount: Int(postingCount)
            )
        case .posting:
            guard let operationId = (values["operationId"] as? String).flatMap(UUID.init(uuidString:)),
                  let accountId = (values["accountId"] as? String).flatMap(UUID.init(uuidString:)),
                  let amountMinor = values["amountMinor"] as? Int64, let rubMinor = values["rubMinor"] as? Int64
            else { return nil }
            payload = .posting(Posting(
                id: ref.id, operationId: operationId, accountId: accountId, amountMinor: amountMinor, rubMinor: rubMinor
            ))
        }
        return SyncRecord(zone: ref.zone, payload: payload, updatedAt: updatedAt, authorDevice: author)
    }

    /// The server's part of [ck] (ids, change tag, who changed it and when), to keep without the values.
    public static func systemFields(of ck: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        ck.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    public static func record(fromSystemFields data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }
}
