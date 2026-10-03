import Foundation
import GoldaCore

// The Android app's backup (`version: 1`, `Backup.kt`): kotlinx.serialization JSON with
// `encodeDefaults`, long ids, upper-case enum names, and every setting in one `settings` object.
// Reading follows the Kotlin class definitions: a property with a default takes it when the key is
// missing, one without a default is required, unknown keys are skipped. Each Kotlin default comes
// from the Swift domain (`Settings()`, the model initializers) so the two cannot drift.

struct AndroidBackup: Decodable {
    var exportedAt: Int64
    var settings: AndroidSettings
    var accounts: [AndroidAccount]
    var categories: [AndroidCategory]
    var operations: [AndroidOperation]
    var postings: [AndroidPosting]
    var rates: [RateRecord]
    var obligations: [AndroidObligation]
    var goals: [AndroidGoal]
    var wishes: [AndroidWish]
}

struct AndroidSettings: Decodable {
    var incomeHourly: Bool
    var hourlyRate: Double
    var monthlySalary: Double
    var taxPercent: Double
    var hoursPerWeek: Double
    var payday: Int
    var displayCurrencies: [String]
    var localCurrency: String
    var baseCurrency: String
    var markup: Double
    var geminiModel: String
    var reconcileReminder: Bool
    /// Account id to epoch milliseconds. JSON object keys are strings, so the ids arrive as text.
    var reconciledAt: [String: Int64]

    private enum CodingKeys: String, CodingKey {
        case incomeHourly, hourlyRate, monthlySalary, taxPercent, hoursPerWeek, payday, displayCurrencies
        case localCurrency, baseCurrency, markup, geminiModel, reconcileReminder, reconciledAt
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = Settings()
        let device = BackupDevice()
        incomeHourly = try c.value(.incomeHourly, or: s.incomeHourly)
        hourlyRate = try c.value(.hourlyRate, or: s.hourlyRate)
        monthlySalary = try c.value(.monthlySalary, or: s.monthlySalary)
        taxPercent = try c.value(.taxPercent, or: s.taxPercent)
        hoursPerWeek = try c.value(.hoursPerWeek, or: s.hoursPerWeek)
        payday = try c.value(.payday, or: s.payday)
        displayCurrencies = try c.value(.displayCurrencies, or: s.displayCurrencies)
        localCurrency = try c.value(.localCurrency, or: s.localCurrency)
        baseCurrency = try c.value(.baseCurrency, or: s.baseCurrency)
        markup = try c.value(.markup, or: s.markup)
        geminiModel = try c.value(.geminiModel, or: device.geminiModel)
        reconcileReminder = try c.value(.reconcileReminder, or: device.reconcileReminder)
        reconciledAt = try c.value(.reconciledAt, or: [:])
    }
}

struct AndroidAccount: Decodable {
    var id: Int64
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

    private enum CodingKeys: String, CodingKey {
        case id, name, currency, type, groupName, includeInFree, interestRate, sort, paymentDay, paymentMinor, graceUntil
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.value(.id, or: 0)
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
    }
}

/// Only what the import needs: the id an operation points at and the key it stands for. The emoji,
/// Russian name and order are the built-in categories' business now.
struct AndroidCategory: Decodable {
    var id: Int64
    var key: String

    private enum CodingKeys: String, CodingKey { case id, key }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.value(.id, or: 0)
        key = try c.decode(String.self, forKey: .key)
    }
}

struct AndroidOperation: Decodable {
    var id: Int64
    var type: OpType
    var timestamp: Int64
    var categoryId: Int64?
    var note: String
    var voiceText: String?
    var purchaseAmountMinor: Int64?
    var purchaseCurrency: String?
    var isEstimate: Bool
    var cbrFrom: Double?
    var cbrTo: Double?

    private enum CodingKeys: String, CodingKey {
        case id, type, timestamp, categoryId, note, voiceText, purchaseAmountMinor, purchaseCurrency, isEstimate
        case cbrFrom, cbrTo
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.value(.id, or: 0)
        type = try c.decode(OpType.self, forKey: .type)
        timestamp = try c.decode(Int64.self, forKey: .timestamp)
        categoryId = try c.decodeIfPresent(Int64.self, forKey: .categoryId)
        note = try c.value(.note, or: "")
        voiceText = try c.decodeIfPresent(String.self, forKey: .voiceText)
        purchaseAmountMinor = try c.decodeIfPresent(Int64.self, forKey: .purchaseAmountMinor)
        purchaseCurrency = try c.decodeIfPresent(String.self, forKey: .purchaseCurrency)
        isEstimate = try c.value(.isEstimate, or: false)
        cbrFrom = try c.decodeIfPresent(Double.self, forKey: .cbrFrom)
        cbrTo = try c.decodeIfPresent(Double.self, forKey: .cbrTo)
    }
}

struct AndroidPosting: Decodable {
    var id: Int64
    var operationId: Int64
    var accountId: Int64
    var amountMinor: Int64
    var rubMinor: Int64

    private enum CodingKeys: String, CodingKey { case id, operationId, accountId, amountMinor, rubMinor }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.value(.id, or: 0)
        operationId = try c.value(.operationId, or: 0)
        accountId = try c.decode(Int64.self, forKey: .accountId)
        amountMinor = try c.decode(Int64.self, forKey: .amountMinor)
        rubMinor = try c.decode(Int64.self, forKey: .rubMinor)
    }
}

struct AndroidObligation: Decodable {
    var id: Int64
    var name: String
    var amountMinor: Int64
    var currency: String
    var dayOfMonth: Int

    private enum CodingKeys: String, CodingKey { case id, name, amountMinor, currency, dayOfMonth }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.value(.id, or: 0)
        name = try c.decode(String.self, forKey: .name)
        amountMinor = try c.decode(Int64.self, forKey: .amountMinor)
        currency = try c.decode(String.self, forKey: .currency)
        dayOfMonth = try c.decode(Int.self, forKey: .dayOfMonth)
    }
}

struct AndroidGoal: Decodable {
    var id: Int64
    var name: String
    var targetMinor: Int64
    var currency: String
    var accountId: Int64?
    var savedMinor: Int64
    var isMain: Bool

    private enum CodingKeys: String, CodingKey { case id, name, targetMinor, currency, accountId, savedMinor, isMain }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.value(.id, or: 0)
        name = try c.decode(String.self, forKey: .name)
        targetMinor = try c.decode(Int64.self, forKey: .targetMinor)
        currency = try c.decode(String.self, forKey: .currency)
        accountId = try c.decodeIfPresent(Int64.self, forKey: .accountId)
        savedMinor = try c.value(.savedMinor, or: 0)
        isMain = try c.value(.isMain, or: false)
    }
}

struct AndroidWish: Decodable {
    var id: Int64
    var title: String
    var amountMinor: Int64
    var currency: String
    var createdAt: Int64
    var decideAt: Int64
    var status: WishStatus
    var decidedAt: Int64?

    private enum CodingKeys: String, CodingKey {
        case id, title, amountMinor, currency, createdAt, decideAt, status, decidedAt
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.value(.id, or: 0)
        title = try c.decode(String.self, forKey: .title)
        amountMinor = try c.decode(Int64.self, forKey: .amountMinor)
        currency = try c.decode(String.self, forKey: .currency)
        createdAt = try c.decode(Int64.self, forKey: .createdAt)
        decideAt = try c.decode(Int64.self, forKey: .decideAt)
        status = try c.value(.status, or: .waiting)
        decidedAt = try c.decodeIfPresent(Int64.self, forKey: .decidedAt)
    }
}
