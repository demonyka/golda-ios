import Foundation
import GoldaCore
import GoldaData

@testable import Golda

/// One profile's books built by hand, no database: a ruble card (the usual account), lari cash, a
/// dollar card and savings, rates of 80 ₽ a dollar and 30 ₽ a lari with the default 10 % markup,
/// payday on the 10th, and "today" 2026-10-02 in UTC. Postings carry their ruble worth as written,
/// so each test reads like the Kotlin row it mirrors.
struct HomeFixture {
    static let utc = TimeZone(secondsFromGMT: 0)!
    static let today = LocalDate(2026, 10, 2)
    static let ru = Locale(identifier: "ru")
    static let en = Locale(identifier: "en")

    static func at(_ date: LocalDate = today, hour: Int) -> Int64 {
        date.atTimeMillis(hour: hour, in: utc)
    }

    var profile = Profile(name: "Личный", settings: ProfileSettings(from: Settings(payday: 10)))
    let rub = Account(name: "Карта ₽", currency: "RUB", type: .card, includeInFree: true, sort: 0)
    let cash = Account(name: "Наличные ₾", currency: "GEL", type: .cash, includeInFree: true, sort: 1)
    let usd = Account(name: "Доллары", currency: "USD", type: .card, includeInFree: true, sort: 2)
    let savings = Account(name: "Накопительный", currency: "RUB", type: .savings, includeInFree: false, sort: 3)
    var extraAccounts: [Account] = []
    /// Newest first, as the snapshot hands them over.
    var operations: [OperationFull] = []
    var obligations: [Obligation] = []
    var device = DeviceSettings(onboarded: true, displayCurrencies: ["RUB", "USD", "GEL"], localCurrency: "GEL")
    var zone = HomeFixture.utc

    var accounts: [Account] { [rub, cash, usd, savings] + extraAccounts }

    var data: AppData {
        AppData(
            snapshot: ProfileSnapshot(
                profile: profile, accounts: accounts, operations: operations, obligations: obligations, goals: [], wishes: []
            ),
            device: device,
            rates: [
                RateRecord(code: "USD", rubPerUnit: 80, date: "2026-10-02"),
                RateRecord(code: "GEL", rubPerUnit: 30, date: "2026-10-02"),
            ],
            zone: zone
        )
    }

    /// The phone last paid from [account] in this profile, so that one becomes the usual one.
    mutating func lastUsed(_ account: Account) {
        device.lastAccountId[profile.id] = account.id
    }

    /// An operation with its postings, each `(account, amountMinor, rubMinor)`.
    static func operation(
        _ type: OpType, at timestamp: Int64, note: String = "", category: String? = nil,
        purchase: (minor: Int64, currency: String)? = nil, estimate: Bool = false,
        _ postings: [(account: Account, minor: Int64, rub: Int64)]
    ) -> OperationFull {
        let op = Operation(
            type: type, timestamp: timestamp, categoryKey: category, note: note, purchaseAmountMinor: purchase?.minor,
            purchaseCurrency: purchase?.currency, isEstimate: estimate
        )
        return OperationFull(op, postings.map { Posting(operationId: op.id, accountId: $0.account.id, amountMinor: $0.minor, rubMinor: $0.rub) })
    }

    /// The row Home draws for [full] in these books.
    func row(_ full: OperationFull, accountId: UUID? = nil) throws -> OperationRowModel {
        guard let row = OperationRowModel(full, in: data, accountId: accountId) else {
            throw FixtureError.noRow
        }
        return row
    }

    enum FixtureError: Error { case noRow }
}
