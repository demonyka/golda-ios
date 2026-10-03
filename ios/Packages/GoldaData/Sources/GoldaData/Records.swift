import Foundation
import GoldaCore
import GRDB

// One row type per table. The domain models carry no profile, so each record adds `profileId` and
// converts to and from its model explicitly; column names are the property names.

/// A row that belongs to a profile, so the store can refuse to read or write it from another one.
protocol ProfileOwnedRecord: Codable, FetchableRecord, PersistableRecord, Identifiable where ID == UUID {
    var profileId: UUID { get }
}

struct ProfileRecord: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "profile"

    var id: UUID
    var name: String
    var sort: Int
    var incomeHourly: Bool
    var hourlyRate: Double
    var monthlySalary: Double
    var taxPercent: Double
    var hoursPerWeek: Double
    var payday: Int
    var markup: Double

    init(_ profile: Profile) {
        id = profile.id
        name = profile.name
        sort = profile.sort
        incomeHourly = profile.settings.incomeHourly
        hourlyRate = profile.settings.hourlyRate
        monthlySalary = profile.settings.monthlySalary
        taxPercent = profile.settings.taxPercent
        hoursPerWeek = profile.settings.hoursPerWeek
        payday = profile.settings.payday
        markup = profile.settings.markup
    }

    var profile: Profile {
        Profile(
            id: id, name: name, sort: sort,
            settings: ProfileSettings(
                incomeHourly: incomeHourly, hourlyRate: hourlyRate, monthlySalary: monthlySalary,
                taxPercent: taxPercent, hoursPerWeek: hoursPerWeek, payday: payday, markup: markup
            )
        )
    }
}

struct AccountRecord: ProfileOwnedRecord {
    static let databaseTableName = "account"

    var id: UUID
    var profileId: UUID
    var name: String
    var currency: String
    var type: AccountType
    var groupName: String?
    var includeInFree: Bool
    var sort: Int
    var interestRate: Double?
    var paymentDay: Int?
    var paymentMinor: Int64?
    var graceUntil: Int64?
    var reconciledAt: Int64?

    init(_ account: Account, profileId: UUID) {
        id = account.id
        self.profileId = profileId
        name = account.name
        currency = account.currency
        type = account.type
        groupName = account.groupName
        includeInFree = account.includeInFree
        sort = account.sort
        interestRate = account.interestRate
        paymentDay = account.paymentDay
        paymentMinor = account.paymentMinor
        graceUntil = account.graceUntil
        reconciledAt = account.reconciledAt
    }

    var account: Account {
        Account(
            id: id, name: name, currency: currency, type: type, groupName: groupName, includeInFree: includeInFree,
            interestRate: interestRate, sort: sort, paymentDay: paymentDay, paymentMinor: paymentMinor,
            graceUntil: graceUntil, reconciledAt: reconciledAt
        )
    }
}

struct OperationRecord: ProfileOwnedRecord {
    static let databaseTableName = "operation"

    var id: UUID
    var profileId: UUID
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
    /// Epoch milliseconds of the last change, for last-writer-wins between devices.
    var updatedAt: Int64
    /// The operation's place in its profile's order of writing; the store fills it in when nil.
    var sequence: Int64?

    // Qualified: Foundation has an `Operation` too.
    init(_ operation: GoldaCore.Operation, profileId: UUID, updatedAt: Int64, sequence: Int64? = nil) {
        id = operation.id
        self.profileId = profileId
        type = operation.type
        timestamp = operation.timestamp
        categoryKey = operation.categoryKey
        note = operation.note
        voiceText = operation.voiceText
        purchaseAmountMinor = operation.purchaseAmountMinor
        purchaseCurrency = operation.purchaseCurrency
        isEstimate = operation.isEstimate
        cbrFrom = operation.cbrFrom
        cbrTo = operation.cbrTo
        self.updatedAt = updatedAt
        self.sequence = sequence
    }

    var operation: GoldaCore.Operation {
        GoldaCore.Operation(
            id: id, type: type, timestamp: timestamp, categoryKey: categoryKey, note: note, voiceText: voiceText,
            purchaseAmountMinor: purchaseAmountMinor, purchaseCurrency: purchaseCurrency, isEstimate: isEstimate,
            cbrFrom: cbrFrom, cbrTo: cbrTo
        )
    }
}

struct PostingRecord: ProfileOwnedRecord {
    static let databaseTableName = "posting"

    var id: UUID
    var profileId: UUID
    var operationId: UUID
    var accountId: UUID
    var amountMinor: Int64
    var rubMinor: Int64

    init(_ posting: Posting, profileId: UUID) {
        id = posting.id
        self.profileId = profileId
        operationId = posting.operationId
        accountId = posting.accountId
        amountMinor = posting.amountMinor
        rubMinor = posting.rubMinor
    }

    var posting: Posting {
        Posting(id: id, operationId: operationId, accountId: accountId, amountMinor: amountMinor, rubMinor: rubMinor)
    }
}

struct ObligationRecord: ProfileOwnedRecord {
    static let databaseTableName = "obligation"

    var id: UUID
    var profileId: UUID
    var name: String
    var amountMinor: Int64
    var currency: String
    var dayOfMonth: Int

    init(_ obligation: Obligation, profileId: UUID) {
        id = obligation.id
        self.profileId = profileId
        name = obligation.name
        amountMinor = obligation.amountMinor
        currency = obligation.currency
        dayOfMonth = obligation.dayOfMonth
    }

    var obligation: Obligation {
        Obligation(id: id, name: name, amountMinor: amountMinor, currency: currency, dayOfMonth: dayOfMonth)
    }
}

struct GoalRecord: ProfileOwnedRecord {
    static let databaseTableName = "goal"

    var id: UUID
    var profileId: UUID
    var name: String
    var targetMinor: Int64
    var currency: String
    var accountId: UUID?
    var savedMinor: Int64
    var isMain: Bool
    /// The goal's place in its profile's creation order (1, 2, 3…), not a time: the domain model
    /// has no such field, so the store fills it in when it is nil (D27). The column is NOT NULL, so
    /// a record that skips the store cannot be written without one.
    var createdAt: Int64?

    init(_ goal: Goal, profileId: UUID, createdAt: Int64? = nil) {
        id = goal.id
        self.profileId = profileId
        name = goal.name
        targetMinor = goal.targetMinor
        currency = goal.currency
        accountId = goal.accountId
        savedMinor = goal.savedMinor
        isMain = goal.isMain
        self.createdAt = createdAt
    }

    var goal: Goal {
        Goal(
            id: id, name: name, targetMinor: targetMinor, currency: currency, accountId: accountId,
            savedMinor: savedMinor, isMain: isMain
        )
    }
}

struct WishRecord: ProfileOwnedRecord {
    static let databaseTableName = "wish"

    var id: UUID
    var profileId: UUID
    var title: String
    var amountMinor: Int64
    var currency: String
    var createdAt: Int64
    var decideAt: Int64
    var status: WishStatus
    var decidedAt: Int64?

    init(_ wish: Wish, profileId: UUID) {
        id = wish.id
        self.profileId = profileId
        title = wish.title
        amountMinor = wish.amountMinor
        currency = wish.currency
        createdAt = wish.createdAt
        decideAt = wish.decideAt
        status = wish.status
        decidedAt = wish.decidedAt
    }

    var wish: Wish {
        Wish(
            id: id, title: title, amountMinor: amountMinor, currency: currency, createdAt: createdAt,
            decideAt: decideAt, status: status, decidedAt: decidedAt
        )
    }
}

/// Official CBR rate: rubles per one unit of [code], as of [date] ("2026-10-02").
public struct RateRecord: Equatable, Hashable, Sendable, Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "rate"

    public var code: String
    public var rubPerUnit: Double
    public var date: String

    public init(code: String, rubPerUnit: Double, date: String) {
        self.code = code
        self.rubPerUnit = rubPerUnit
        self.date = date
    }
}
