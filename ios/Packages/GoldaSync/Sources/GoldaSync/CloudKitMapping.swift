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
/// flags are 0 and 1; ids are lowercase UUID strings.
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
            values["incomeHourly"] = flag(profile.settings.incomeHourly)
            values["hourlyRate"] = profile.settings.hourlyRate
            values["monthlySalary"] = profile.settings.monthlySalary
            values["taxPercent"] = profile.settings.taxPercent
            values["hoursPerWeek"] = profile.settings.hoursPerWeek
            values["payday"] = Int64(profile.settings.payday)
            values["markup"] = profile.settings.markup
        case .account(let account):
            values["name"] = account.name
            values["currency"] = account.currency
            values["type"] = account.type.rawValue
            values["groupName"] = account.groupName
            values["includeInFree"] = flag(account.includeInFree)
            values["interestRate"] = account.interestRate
            values["sort"] = Int64(account.sort)
            values["paymentDay"] = account.paymentDay.map { Int64($0) }
            values["paymentMinor"] = account.paymentMinor
            values["graceUntil"] = account.graceUntil
            values["reconciledAt"] = account.reconciledAt
            values["creditLimitMinor"] = account.creditLimitMinor
        case .operation(let op, let postings):
            values["type"] = op.type.rawValue
            values["timestamp"] = op.timestamp
            values["categoryKey"] = op.categoryKey
            values["note"] = op.note
            values["voiceText"] = op.voiceText
            values["purchaseAmountMinor"] = op.purchaseAmountMinor
            values["purchaseCurrency"] = op.purchaseCurrency
            values["isEstimate"] = flag(op.isEstimate)
            values["cbrFrom"] = op.cbrFrom
            values["cbrTo"] = op.cbrTo
            values["postings"] = PostingWire.encode(postings)
        case .obligation(let obligation, let createdAt):
            values["name"] = obligation.name
            values["amountMinor"] = obligation.amountMinor
            values["currency"] = obligation.currency
            values["dayOfMonth"] = Int64(obligation.dayOfMonth)
            values["createdAt"] = createdAt
        case .goal(let goal, let createdAt):
            values["name"] = goal.name
            values["targetMinor"] = goal.targetMinor
            values["currency"] = goal.currency
            values["accountId"] = goal.accountId.map(id)
            values["savedMinor"] = goal.savedMinor
            values["isMain"] = flag(goal.isMain)
            values["createdAt"] = createdAt
        case .wish(let wish):
            values["title"] = wish.title
            values["amountMinor"] = wish.amountMinor
            values["currency"] = wish.currency
            values["createdAt"] = wish.createdAt
            values["decideAt"] = wish.decideAt
            values["status"] = wish.status.rawValue
            values["decidedAt"] = wish.decidedAt
        case .category(let category, let createdAt):
            values["name"] = category.name
            values["kind"] = category.kind.rawValue
            values["hint"] = category.hint
            values["symbol"] = category.symbol
            values["createdAt"] = createdAt
        }
        return ck
    }

    /// The record [ck] holds, or nil when it is not one of ours (the zone's `CKShare`, a type of a
    /// later version) or lacks a field this version needs.
    public static func syncRecord(from ck: CKRecord, scope: SyncScope) -> SyncRecord? {
        guard let ref = SyncRecordRef(recordID: ck.recordID, scope: scope), ref.type.rawValue == ck.recordType,
              let updatedAt = ck[Field.updatedAt] as? Int64,
              let payload = payload(ref, Values(ck.encryptedValues))
        else { return nil }
        let author = ck[Field.authorDevice] as? String ?? ""
        return SyncRecord(zone: ref.zone, payload: payload, updatedAt: updatedAt, authorDevice: author)
    }

    /// Typed reads of a record's encrypted values.
    private struct Values {
        let values: any CKRecordKeyValueSetting

        init(_ values: any CKRecordKeyValueSetting) {
            self.values = values
        }

        func int(_ key: String) -> Int64? { values[key] as? Int64 }
        func double(_ key: String) -> Double? { values[key] as? Double }
        func string(_ key: String) -> String? { values[key] as? String }
        func data(_ key: String) -> Data? { values[key] as? Data }
        func uuid(_ key: String) -> UUID? { string(key).flatMap(UUID.init(uuidString:)) }
        func flag(_ key: String) -> Bool { (int(key) ?? 0) != 0 }
    }

    private static func payload(_ ref: SyncRecordRef, _ v: Values) -> SyncPayload? {
        switch ref.type {
        case .profile:
            // The zone's root has the zone's profile id, whatever its record says.
            guard ref.id == ref.zone.profileId, let name = v.string("name") else { return nil }
            let defaults = ProfileSettings()
            return .profile(Profile(
                id: ref.id, name: name, sort: Int(v.int("sort") ?? 0),
                settings: ProfileSettings(
                    incomeHourly: v.flag("incomeHourly"),
                    hourlyRate: v.double("hourlyRate") ?? defaults.hourlyRate,
                    monthlySalary: v.double("monthlySalary") ?? defaults.monthlySalary,
                    taxPercent: v.double("taxPercent") ?? defaults.taxPercent,
                    hoursPerWeek: v.double("hoursPerWeek") ?? defaults.hoursPerWeek,
                    payday: Int(v.int("payday") ?? Int64(defaults.payday)),
                    markup: v.double("markup") ?? defaults.markup
                )
            ))
        case .account:
            guard let name = v.string("name"), let currency = v.string("currency"),
                  let type = v.string("type").flatMap(AccountType.init(rawValue:))
            else { return nil }
            return .account(Account(
                id: ref.id, name: name, currency: currency, type: type, groupName: v.string("groupName"),
                includeInFree: v.flag("includeInFree"), interestRate: v.double("interestRate"), sort: Int(v.int("sort") ?? 0),
                paymentDay: v.int("paymentDay").map { Int($0) }, paymentMinor: v.int("paymentMinor"),
                graceUntil: v.int("graceUntil"), reconciledAt: v.int("reconciledAt"),
                creditLimitMinor: v.int("creditLimitMinor")
            ))
        case .operation:
            // An operation of the first 5b builds has no postings in it, only their count: skipped,
            // and its author sends it again in this shape once updated (`SyncSchema.v3`).
            guard let type = v.string("type").flatMap(OpType.init(rawValue:)), let timestamp = v.int("timestamp"),
                  let postings = v.data("postings").flatMap({ PostingWire.decode($0, operationId: ref.id) })
            else { return nil }
            return .operation(
                GoldaCore.Operation(
                    id: ref.id, type: type, timestamp: timestamp, categoryKey: v.string("categoryKey"),
                    note: v.string("note") ?? "", voiceText: v.string("voiceText"),
                    purchaseAmountMinor: v.int("purchaseAmountMinor"), purchaseCurrency: v.string("purchaseCurrency"),
                    isEstimate: v.flag("isEstimate"), cbrFrom: v.double("cbrFrom"), cbrTo: v.double("cbrTo")
                ),
                postings: postings
            )
        case .obligation:
            guard let name = v.string("name"), let amountMinor = v.int("amountMinor"), let currency = v.string("currency"),
                  let day = v.int("dayOfMonth")
            else { return nil }
            return .obligation(
                Obligation(id: ref.id, name: name, amountMinor: amountMinor, currency: currency, dayOfMonth: Int(day)),
                createdAt: v.int("createdAt") ?? 0
            )
        case .goal:
            guard let name = v.string("name"), let target = v.int("targetMinor"), let currency = v.string("currency") else { return nil }
            return .goal(
                Goal(
                    id: ref.id, name: name, targetMinor: target, currency: currency, accountId: v.uuid("accountId"),
                    savedMinor: v.int("savedMinor") ?? 0, isMain: v.flag("isMain")
                ),
                createdAt: v.int("createdAt") ?? 0
            )
        case .wish:
            guard let title = v.string("title"), let amountMinor = v.int("amountMinor"), let currency = v.string("currency"),
                  let createdAt = v.int("createdAt"), let decideAt = v.int("decideAt"),
                  let status = v.string("status").flatMap(WishStatus.init(rawValue:))
            else { return nil }
            return .wish(Wish(
                id: ref.id, title: title, amountMinor: amountMinor, currency: currency, createdAt: createdAt,
                decideAt: decideAt, status: status, decidedAt: v.int("decidedAt")
            ))
        case .category:
            guard let name = v.string("name"), let kind = v.string("kind").flatMap(CategoryKind.init(rawValue:)) else { return nil }
            return .category(
                CustomCategory(id: ref.id, name: name, kind: kind, hint: v.string("hint") ?? "", symbol: v.string("symbol")),
                createdAt: v.int("createdAt") ?? 0
            )
        }
    }

    /// An operation's postings inside its record, as JSON in one encrypted field: a list keeps
    /// the ledger's order, and the record stays one unit for conflicts (D58). Ids are lowercase
    /// strings, money minor units.
    private struct PostingWire: Codable {
        var id: String
        var accountId: String
        var amountMinor: Int64
        var rubMinor: Int64

        static func encode(_ postings: [Posting]) -> Data {
            let wire = postings.map {
                PostingWire(id: CloudKitMapping.id($0.id), accountId: CloudKitMapping.id($0.accountId), amountMinor: $0.amountMinor, rubMinor: $0.rubMinor)
            }
            // Encoding plain strings and integers cannot fail.
            return (try? JSONEncoder().encode(wire)) ?? Data("[]".utf8)
        }

        static func decode(_ data: Data, operationId: UUID) -> [Posting]? {
            guard let wire = try? JSONDecoder().decode([PostingWire].self, from: data) else { return nil }
            var postings: [Posting] = []
            for item in wire {
                guard let id = UUID(uuidString: item.id), let accountId = UUID(uuidString: item.accountId) else { return nil }
                postings.append(Posting(id: id, operationId: operationId, accountId: accountId, amountMinor: item.amountMinor, rubMinor: item.rubMinor))
            }
            return postings
        }
    }

    private static func flag(_ value: Bool) -> Int64 { value ? 1 : 0 }

    private static func id(_ value: UUID) -> String { value.uuidString.lowercased() }

    /// The server's part of [ck] (ids, change tag, who changed it and when), to keep without the values.
    public static func systemFields(of ck: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        ck.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    /// The user record name of whoever created the record, from its server fields (D67):
    /// `CKCurrentUserDefaultName` for this iCloud account, nil before the server has saved it.
    public static func creator(ofSystemFields data: Data) -> String? {
        record(fromSystemFields: data)?.creatorUserRecordID?.recordName
    }

    public static func record(fromSystemFields data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }
}

extension SyncProblem {
    /// What [error] means for the person. CloudKit's codes are sorted into what they can act on:
    /// sign in, free iCloud space, wait, find a network. A time to wait, when the server gives one,
    /// beats the code: on 2026-10-04 the first share failed with `quotaExceeded` and "retry after
    /// 330 s" on an account with free space, and went through when tried again later (D58).
    public init(_ error: any Error) {
        if let problem = error as? SyncProblem {
            self = problem
            return
        }
        if error is URLError {
            self = .offline
            return
        }
        guard let ck = error as? CKError else {
            self = .other(code: (error as NSError).code)
            return
        }
        if ck.code == .partialFailure, let first = ck.partialErrorsByItemID?.values.first {
            self.init(first)
            return
        }
        if let seconds = ck.retryAfterSeconds, seconds > 0 {
            self = .retryLater(seconds: Int(seconds.rounded(.up)))
            return
        }
        switch ck.code {
        case .notAuthenticated, .accountTemporarilyUnavailable: self = .noAccount
        case .quotaExceeded: self = .iCloudFull
        case .networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy: self = .offline
        case .permissionFailure, .participantMayNeedVerification: self = .notPermitted
        default: self = .other(code: ck.code.rawValue)
        }
    }
}
