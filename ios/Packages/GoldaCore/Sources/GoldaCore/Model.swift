import Foundation

// The domain's value types. They carry no profile: the data layer slices one profile's rows and
// hands them to the domain, as the Android app hands over everything it has. Instants are epoch
// milliseconds (`Int64`), money is minor units (`Int64`), and raw values match the Android backup
// so version 1 files can be imported.

public enum AccountType: String, Sendable, Codable, CaseIterable {
    case card = "CARD", cash = "CASH", savings = "SAVINGS", credit = "CREDIT", loan = "LOAN"
}

public enum OpType: String, Sendable, Codable, CaseIterable {
    case expense = "EXPENSE", income = "INCOME", transfer = "TRANSFER", adjustment = "ADJUSTMENT", opening = "OPENING"
}

public enum CategoryKind: String, Sendable, Codable, CaseIterable {
    case expense = "EXPENSE", income = "INCOME"
}

public enum WishStatus: String, Sendable, Codable, CaseIterable {
    case waiting = "WAITING", bought = "BOUGHT", skipped = "SKIPPED"
}

public extension UUID {
    /// "Not assigned yet": a posting before the operation that owns it exists.
    static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
}

public struct Account: Equatable, Hashable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var currency: String
    public var type: AccountType
    /// Accounts with the same group (one multi-currency card's USD and GEL parts) are shown together.
    public var groupName: String?
    /// Counts towards "можно сегодня".
    public var includeInFree: Bool
    /// Yearly percent: what a savings account earns (on the monthly minimum) or what a debt costs.
    public var interestRate: Double?
    public var sort: Int
    /// Debts: the day of month a payment is due and how much (the annuity, or a card's minimum).
    public var paymentDay: Int?
    public var paymentMinor: Int64?
    /// Credit cards: the last day of the interest-free period, as an epoch day.
    public var graceUntil: Int64?
    /// When the account was last checked against the bank, epoch milliseconds, matches included.
    public var reconciledAt: Int64?
    /// Credit cards: how much the bank lends, in the account's minor units (D62; Android has none).
    public var creditLimitMinor: Int64?

    public init(
        id: UUID = UUID(), name: String, currency: String, type: AccountType, groupName: String? = nil,
        includeInFree: Bool, interestRate: Double? = nil, sort: Int = 0, paymentDay: Int? = nil,
        paymentMinor: Int64? = nil, graceUntil: Int64? = nil, reconciledAt: Int64? = nil, creditLimitMinor: Int64? = nil
    ) {
        self.id = id
        self.name = name
        self.currency = currency
        self.type = type
        self.groupName = groupName
        self.includeInFree = includeInFree
        self.interestRate = interestRate
        self.sort = sort
        self.paymentDay = paymentDay
        self.paymentMinor = paymentMinor
        self.graceUntil = graceUntil
        self.reconciledAt = reconciledAt
        self.creditLimitMinor = creditLimitMinor
    }
}

/// The built-in categories. [key] is the stable id the voice model maps phrases to and the one
/// operations store; [name] is the Russian default the prompt shows the model. Screens localize
/// a category by its key.
public struct Category: Equatable, Hashable, Sendable {
    public var key: String
    public var name: String
    public var kind: CategoryKind
    public var sort: Int

    public init(key: String, name: String, kind: CategoryKind, sort: Int = 0) {
        self.key = key
        self.name = name
        self.kind = kind
        self.sort = sort
    }

    public static let builtIn: [Category] = [
        Category(key: "eating_out", name: "Кафе", kind: .expense, sort: 0),
        Category(key: "groceries", name: "Продукты", kind: .expense, sort: 1),
        Category(key: "transport", name: "Транспорт", kind: .expense, sort: 2),
        Category(key: "housing", name: "Жильё", kind: .expense, sort: 3),
        Category(key: "telecom", name: "Связь", kind: .expense, sort: 4),
        Category(key: "fun", name: "Развлечения", kind: .expense, sort: 5),
        Category(key: "health", name: "Здоровье", kind: .expense, sort: 6),
        Category(key: "clothes", name: "Одежда", kind: .expense, sort: 7),
        Category(key: "subscriptions", name: "Подписки", kind: .expense, sort: 8),
        Category(key: "travel", name: "Путешествия", kind: .expense, sort: 9),
        Category(key: "fees", name: "Комиссии", kind: .expense, sort: 10),
        Category(key: "other", name: "Прочее", kind: .expense, sort: 11),
        Category(key: "salary", name: "Зарплата", kind: .income, sort: 0),
        Category(key: "interest", name: "Проценты", kind: .income, sort: 1),
        Category(key: "gift", name: "Подарок", kind: .income, sort: 2),
        Category(key: "other_income", name: "Прочее", kind: .income, sort: 3),
    ]
}

public struct Operation: Equatable, Hashable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var type: OpType
    public var timestamp: Int64
    public var categoryKey: String?
    public var note: String
    /// What the user said, when the operation came from voice.
    public var voiceText: String?
    /// Price in the shop's currency when it differs from the account's (80 ฿ paid from a USD card).
    public var purchaseAmountMinor: Int64?
    public var purchaseCurrency: String?
    /// The charged amount was estimated, not taken from the bank.
    public var isEstimate: Bool
    /// CBR rates of both sides of a currency exchange when it happened, to measure what it cost.
    public var cbrFrom: Double?
    public var cbrTo: Double?

    public init(
        id: UUID = UUID(), type: OpType, timestamp: Int64, categoryKey: String? = nil, note: String = "",
        voiceText: String? = nil, purchaseAmountMinor: Int64? = nil, purchaseCurrency: String? = nil,
        isEstimate: Bool = false, cbrFrom: Double? = nil, cbrTo: Double? = nil
    ) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.categoryKey = categoryKey
        self.note = note
        self.voiceText = voiceText
        self.purchaseAmountMinor = purchaseAmountMinor
        self.purchaseCurrency = purchaseCurrency
        self.isEstimate = isEstimate
        self.cbrFrom = cbrFrom
        self.cbrTo = cbrTo
    }
}

/// One side of an operation. [amountMinor] is in the account's currency; [rubMinor] is what that
/// money cost in rubles (kopecks), so the sum of an account's postings gives both its balance and
/// its cost basis.
public struct Posting: Equatable, Hashable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var operationId: UUID
    public var accountId: UUID
    public var amountMinor: Int64
    public var rubMinor: Int64

    public init(id: UUID = UUID(), operationId: UUID = .zero, accountId: UUID, amountMinor: Int64, rubMinor: Int64) {
        self.id = id
        self.operationId = operationId
        self.accountId = accountId
        self.amountMinor = amountMinor
        self.rubMinor = rubMinor
    }
}

public struct OperationFull: Equatable, Hashable, Sendable {
    public var op: Operation
    public var postings: [Posting]

    public init(_ op: Operation, _ postings: [Posting]) {
        self.op = op
        self.postings = postings
    }
}

/// A payment that comes every month (loan, rent, subscription) and is set aside before "можно сегодня".
public struct Obligation: Equatable, Hashable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var amountMinor: Int64
    public var currency: String
    public var dayOfMonth: Int

    public init(id: UUID = UUID(), name: String, amountMinor: Int64, currency: String, dayOfMonth: Int) {
        self.id = id
        self.name = name
        self.amountMinor = amountMinor
        self.currency = currency
        self.dayOfMonth = dayOfMonth
    }
}

/// Something to save up for. Progress is the linked account's balance plus what was put aside by
/// skipping purchases.
public struct Goal: Equatable, Hashable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var targetMinor: Int64
    public var currency: String
    public var accountId: UUID?
    public var savedMinor: Int64
    /// The one purchases are compared with.
    public var isMain: Bool

    public init(
        id: UUID = UUID(), name: String, targetMinor: Int64, currency: String, accountId: UUID? = nil,
        savedMinor: Int64 = 0, isMain: Bool = false
    ) {
        self.id = id
        self.name = name
        self.targetMinor = targetMinor
        self.currency = currency
        self.accountId = accountId
        self.savedMinor = savedMinor
        self.isMain = isMain
    }
}

/// A purchase put on hold to think about.
public struct Wish: Equatable, Hashable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var title: String
    public var amountMinor: Int64
    public var currency: String
    public var createdAt: Int64
    public var decideAt: Int64
    public var status: WishStatus
    public var decidedAt: Int64?

    public init(
        id: UUID = UUID(), title: String, amountMinor: Int64, currency: String, createdAt: Int64, decideAt: Int64,
        status: WishStatus = .waiting, decidedAt: Int64? = nil
    ) {
        self.id = id
        self.title = title
        self.amountMinor = amountMinor
        self.currency = currency
        self.createdAt = createdAt
        self.decideAt = decideAt
        self.status = status
        self.decidedAt = decidedAt
    }
}
