import Foundation
import GoldaCore

// The version 2 file as JSON. The domain models are not encoded directly: the file has its own
// shape (postings live inside their operation, the profile owns every list), and decoding gives a
// missing key its default, as Android's `ignoreUnknownKeys` + defaults did, so a file from before
// a field was added still loads. Keys with no sensible default (ids, names, amounts, currencies,
// types) are required. A value of the wrong type is an error, never a silent default: a damaged
// file must fail rather than import something else.

extension KeyedDecodingContainer {
    /// The value, or [fallback] when the key is missing or null; a value of the wrong type throws.
    func value<T: Decodable>(_ key: Key, or fallback: @autoclosure () -> T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? fallback()
    }
}

struct WireBackup: Codable {
    var version: Int
    var exportedAt: Int64
    var device: WireDevice
    var profiles: [WireProfile]
    var rates: [RateRecord]

    init(_ backup: Backup) {
        version = BackupFormat.version
        exportedAt = backup.exportedAt
        device = WireDevice(backup.device)
        profiles = backup.profiles.map {
            WireProfile($0, goalCreatedAt: backup.goalCreatedAt, obligationCreatedAt: backup.obligationCreatedAt)
        }
        rates = backup.rates
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        exportedAt = try c.value(.exportedAt, or: 0)
        device = try c.value(.device, or: WireDevice(BackupDevice()))
        profiles = try c.decode([WireProfile].self, forKey: .profiles)
        rates = try c.value(.rates, or: [])
    }

    var backup: Backup {
        var goalCreatedAt: [UUID: Int64] = [:]
        var obligationCreatedAt: [UUID: Int64] = [:]
        for profile in profiles {
            goalCreatedAt.merge(profile.goalCreatedAt) { first, _ in first }
            obligationCreatedAt.merge(profile.obligationCreatedAt) { first, _ in first }
        }
        return Backup(
            sourceVersion: version, exportedAt: exportedAt, device: device.device, profiles: profiles.map(\.snapshot),
            goalCreatedAt: goalCreatedAt, obligationCreatedAt: obligationCreatedAt, rates: rates
        )
    }
}

struct WireDevice: Codable {
    var displayCurrencies: [String]
    var localCurrency: String
    var baseCurrency: String
    var geminiModel: String
    var reconcileReminder: Bool

    init(_ device: BackupDevice) {
        displayCurrencies = device.displayCurrencies
        localCurrency = device.localCurrency
        baseCurrency = device.baseCurrency
        geminiModel = device.geminiModel
        reconcileReminder = device.reconcileReminder
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BackupDevice()
        displayCurrencies = try c.value(.displayCurrencies, or: d.displayCurrencies)
        localCurrency = try c.value(.localCurrency, or: d.localCurrency)
        baseCurrency = try c.value(.baseCurrency, or: d.baseCurrency)
        geminiModel = try c.value(.geminiModel, or: d.geminiModel)
        reconcileReminder = try c.value(.reconcileReminder, or: d.reconcileReminder)
    }

    var device: BackupDevice {
        BackupDevice(
            displayCurrencies: displayCurrencies, localCurrency: localCurrency, baseCurrency: baseCurrency,
            geminiModel: geminiModel, reconcileReminder: reconcileReminder
        )
    }
}

struct WireProfile: Codable {
    var id: UUID
    var name: String
    var sort: Int
    var settings: WireProfileSettings
    var accounts: [WireAccount]
    var operations: [WireOperation]
    var obligations: [WireObligation]
    var goals: [WireGoal]
    var wishes: [WireWish]
    /// The profile's own categories in their order (1.0.3, D68); files before it have none.
    var categories: [CustomCategory]

    init(_ snapshot: ProfileSnapshot, goalCreatedAt: [UUID: Int64], obligationCreatedAt: [UUID: Int64]) {
        id = snapshot.profile.id
        name = snapshot.profile.name
        sort = snapshot.profile.sort
        settings = WireProfileSettings(snapshot.profile.settings)
        accounts = snapshot.accounts.map(WireAccount.init)
        operations = snapshot.operations.map(WireOperation.init)
        obligations = snapshot.obligations.map { WireObligation($0, createdAt: obligationCreatedAt[$0.id]) }
        goals = snapshot.goals.map { WireGoal($0, createdAt: goalCreatedAt[$0.id]) }
        wishes = snapshot.wishes.map(WireWish.init)
        categories = snapshot.categories
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        sort = try c.value(.sort, or: 0)
        settings = try c.value(.settings, or: WireProfileSettings(ProfileSettings()))
        accounts = try c.value(.accounts, or: [])
        operations = try c.value(.operations, or: [])
        obligations = try c.value(.obligations, or: [])
        goals = try c.value(.goals, or: [])
        wishes = try c.value(.wishes, or: [])
        categories = try c.value(.categories, or: [])
    }

    var snapshot: ProfileSnapshot {
        ProfileSnapshot(
            profile: Profile(id: id, name: name, sort: sort, settings: settings.settings),
            accounts: accounts.map(\.account), operations: operations.map(\.full),
            obligations: obligations.map(\.obligation), goals: goals.map(\.goal), wishes: wishes.map(\.wish),
            categories: categories
        )
    }

    /// The goals' creation counters, when the file gives every goal its own.
    var goalCreatedAt: [UUID: Int64] {
        Self.counters(goals.map { ($0.id, $0.createdAt) })
    }

    /// The payments' creation counters, when the file gives every payment its own.
    var obligationCreatedAt: [UUID: Int64] {
        Self.counters(obligations.map { ($0.id, $0.createdAt) })
    }

    /// A file from before the counters, or one with a row lacking one or two rows sharing one, gets
    /// none for that kind of row: the rows are then created in the order the file lists them.
    private static func counters(_ rows: [(id: UUID, createdAt: Int64?)]) -> [UUID: Int64] {
        let counters = rows.compactMap { row in row.createdAt.map { (row.id, $0) } }
        guard counters.count == rows.count, Set(counters.map(\.1)).count == counters.count else { return [:] }
        return Dictionary(counters) { first, _ in first }
    }
}

struct WireProfileSettings: Codable {
    var incomeHourly: Bool
    var hourlyRate: Double
    var monthlySalary: Double
    var taxPercent: Double
    var hoursPerWeek: Double
    var payday: Int
    var markup: Double

    init(_ settings: ProfileSettings) {
        incomeHourly = settings.incomeHourly
        hourlyRate = settings.hourlyRate
        monthlySalary = settings.monthlySalary
        taxPercent = settings.taxPercent
        hoursPerWeek = settings.hoursPerWeek
        payday = settings.payday
        markup = settings.markup
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ProfileSettings()
        incomeHourly = try c.value(.incomeHourly, or: d.incomeHourly)
        hourlyRate = try c.value(.hourlyRate, or: d.hourlyRate)
        monthlySalary = try c.value(.monthlySalary, or: d.monthlySalary)
        taxPercent = try c.value(.taxPercent, or: d.taxPercent)
        hoursPerWeek = try c.value(.hoursPerWeek, or: d.hoursPerWeek)
        payday = try c.value(.payday, or: d.payday)
        markup = try c.value(.markup, or: d.markup)
    }

    var settings: ProfileSettings {
        ProfileSettings(
            incomeHourly: incomeHourly, hourlyRate: hourlyRate, monthlySalary: monthlySalary, taxPercent: taxPercent,
            hoursPerWeek: hoursPerWeek, payday: payday, markup: markup
        )
    }
}

struct WireAccount: Codable {
    var id: UUID
    var name: String
    var currency: String
    var type: AccountType
    var groupName: String?
    var includeInFree: Bool
    var interestRate: Double?
    var sort: Int
    var paymentDay: Int?
    var paymentMinor: Int64?
    var graceUntil: Int64?
    var reconciledAt: Int64?
    /// Since 1.0.1 (D62); files before it have none.
    var creditLimitMinor: Int64?

    init(_ a: Account) {
        id = a.id
        name = a.name
        currency = a.currency
        type = a.type
        groupName = a.groupName
        includeInFree = a.includeInFree
        interestRate = a.interestRate
        sort = a.sort
        paymentDay = a.paymentDay
        paymentMinor = a.paymentMinor
        graceUntil = a.graceUntil
        reconciledAt = a.reconciledAt
        creditLimitMinor = a.creditLimitMinor
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        currency = try c.decode(String.self, forKey: .currency)
        type = try c.decode(AccountType.self, forKey: .type)
        groupName = try c.decodeIfPresent(String.self, forKey: .groupName)
        includeInFree = try c.decode(Bool.self, forKey: .includeInFree)
        interestRate = try c.decodeIfPresent(Double.self, forKey: .interestRate)
        sort = try c.value(.sort, or: 0)
        paymentDay = try c.decodeIfPresent(Int.self, forKey: .paymentDay)
        paymentMinor = try c.decodeIfPresent(Int64.self, forKey: .paymentMinor)
        graceUntil = try c.decodeIfPresent(Int64.self, forKey: .graceUntil)
        reconciledAt = try c.decodeIfPresent(Int64.self, forKey: .reconciledAt)
        creditLimitMinor = try c.decodeIfPresent(Int64.self, forKey: .creditLimitMinor)
    }

    var account: Account {
        Account(
            id: id, name: name, currency: currency, type: type, groupName: groupName, includeInFree: includeInFree,
            interestRate: interestRate, sort: sort, paymentDay: paymentDay, paymentMinor: paymentMinor,
            graceUntil: graceUntil, reconciledAt: reconciledAt, creditLimitMinor: creditLimitMinor
        )
    }
}

struct WireOperation: Codable {
    var id: UUID
    var type: OpType
    var timestamp: Int64
    var categoryKey: String?
    var note: String
    var voiceText: String?
    var purchaseAmountMinor: Int64?
    var purchaseCurrency: String?
    var isEstimate: Bool
    var cbrFrom: Double?
    var cbrTo: Double?
    var postings: [WirePosting]

    init(_ full: OperationFull) {
        let op = full.op
        id = op.id
        type = op.type
        timestamp = op.timestamp
        categoryKey = op.categoryKey
        note = op.note
        voiceText = op.voiceText
        purchaseAmountMinor = op.purchaseAmountMinor
        purchaseCurrency = op.purchaseCurrency
        isEstimate = op.isEstimate
        cbrFrom = op.cbrFrom
        cbrTo = op.cbrTo
        postings = full.postings.map(WirePosting.init)
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        type = try c.decode(OpType.self, forKey: .type)
        timestamp = try c.decode(Int64.self, forKey: .timestamp)
        categoryKey = try c.decodeIfPresent(String.self, forKey: .categoryKey)
        note = try c.value(.note, or: "")
        voiceText = try c.decodeIfPresent(String.self, forKey: .voiceText)
        purchaseAmountMinor = try c.decodeIfPresent(Int64.self, forKey: .purchaseAmountMinor)
        purchaseCurrency = try c.decodeIfPresent(String.self, forKey: .purchaseCurrency)
        isEstimate = try c.value(.isEstimate, or: false)
        cbrFrom = try c.decodeIfPresent(Double.self, forKey: .cbrFrom)
        cbrTo = try c.decodeIfPresent(Double.self, forKey: .cbrTo)
        postings = try c.value(.postings, or: [])
    }

    var full: OperationFull {
        // Qualified: Foundation has an `Operation` too.
        OperationFull(
            GoldaCore.Operation(
                id: id, type: type, timestamp: timestamp, categoryKey: categoryKey, note: note, voiceText: voiceText,
                purchaseAmountMinor: purchaseAmountMinor, purchaseCurrency: purchaseCurrency, isEstimate: isEstimate,
                cbrFrom: cbrFrom, cbrTo: cbrTo
            ),
            postings.map { $0.posting(of: id) }
        )
    }
}

/// A posting inside its operation: the operation's id is implied by where it sits.
struct WirePosting: Codable {
    var id: UUID
    var accountId: UUID
    var amountMinor: Int64
    var rubMinor: Int64

    init(_ p: Posting) {
        id = p.id
        accountId = p.accountId
        amountMinor = p.amountMinor
        rubMinor = p.rubMinor
    }

    func posting(of operationId: UUID) -> Posting {
        Posting(id: id, operationId: operationId, accountId: accountId, amountMinor: amountMinor, rubMinor: rubMinor)
    }
}

struct WireObligation: Codable {
    var id: UUID
    var name: String
    var amountMinor: Int64
    var currency: String
    var dayOfMonth: Int
    /// The payment's place in the profile's creation order: a counter, not a time.
    var createdAt: Int64?

    init(_ o: Obligation, createdAt: Int64?) {
        id = o.id
        name = o.name
        amountMinor = o.amountMinor
        currency = o.currency
        dayOfMonth = o.dayOfMonth
        self.createdAt = createdAt
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        amountMinor = try c.decode(Int64.self, forKey: .amountMinor)
        currency = try c.decode(String.self, forKey: .currency)
        dayOfMonth = try c.decode(Int.self, forKey: .dayOfMonth)
        createdAt = try c.decodeIfPresent(Int64.self, forKey: .createdAt)
    }

    var obligation: Obligation {
        Obligation(id: id, name: name, amountMinor: amountMinor, currency: currency, dayOfMonth: dayOfMonth)
    }
}

struct WireGoal: Codable {
    var id: UUID
    var name: String
    var targetMinor: Int64
    var currency: String
    var accountId: UUID?
    var savedMinor: Int64
    var isMain: Bool
    /// The goal's place in the profile's creation order: a counter, not a time.
    var createdAt: Int64?

    init(_ g: Goal, createdAt: Int64?) {
        id = g.id
        name = g.name
        targetMinor = g.targetMinor
        currency = g.currency
        accountId = g.accountId
        savedMinor = g.savedMinor
        isMain = g.isMain
        self.createdAt = createdAt
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        targetMinor = try c.decode(Int64.self, forKey: .targetMinor)
        currency = try c.decode(String.self, forKey: .currency)
        accountId = try c.decodeIfPresent(UUID.self, forKey: .accountId)
        savedMinor = try c.value(.savedMinor, or: 0)
        isMain = try c.value(.isMain, or: false)
        createdAt = try c.decodeIfPresent(Int64.self, forKey: .createdAt)
    }

    var goal: Goal {
        Goal(
            id: id, name: name, targetMinor: targetMinor, currency: currency, accountId: accountId,
            savedMinor: savedMinor, isMain: isMain
        )
    }
}

struct WireWish: Codable {
    var id: UUID
    var title: String
    var amountMinor: Int64
    var currency: String
    var createdAt: Int64
    var decideAt: Int64
    var status: WishStatus
    var decidedAt: Int64?

    init(_ w: Wish) {
        id = w.id
        title = w.title
        amountMinor = w.amountMinor
        currency = w.currency
        createdAt = w.createdAt
        decideAt = w.decideAt
        status = w.status
        decidedAt = w.decidedAt
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        amountMinor = try c.decode(Int64.self, forKey: .amountMinor)
        currency = try c.decode(String.self, forKey: .currency)
        createdAt = try c.decode(Int64.self, forKey: .createdAt)
        decideAt = try c.decode(Int64.self, forKey: .decideAt)
        status = try c.value(.status, or: .waiting)
        decidedAt = try c.decodeIfPresent(Int64.self, forKey: .decidedAt)
    }

    var wish: Wish {
        Wish(
            id: id, title: title, amountMinor: amountMinor, currency: currency, createdAt: createdAt,
            decideAt: decideAt, status: status, decidedAt: decidedAt
        )
    }
}
