import Foundation
import GoldaCore
import GoldaData

@testable import Golda

/// One profile's books for the operation form, built by hand: a ruble card, lari cash, a dollar
/// card and ruble savings (out of the budget). Rates are 80 ₽ a dollar and 30 ₽ a lari with the
/// default 10 % markup; lari are the local currency and rubles, dollars and lari are shown. Paid
/// 1 000 ₽ an hour with 10 % tax (900 ₽ on hand), payday on the 10th, and "now" 2026-10-02 10:00
/// in UTC, the day the Kotlin tests call today.
struct EntryFixture {
    typealias F = HomeFixture

    static let today = F.today
    static let now = F.at(hour: 10)
    static let yesterday = today.minusDays(1)

    var profile = Profile(
        name: "Личный",
        settings: ProfileSettings(from: Settings(incomeHourly: true, hourlyRate: 1000, taxPercent: 10, payday: 10))
    )
    let rub = Account(name: "Карта ₽", currency: "RUB", type: .card, includeInFree: true, sort: 0)
    let cash = Account(name: "Наличные ₾", currency: "GEL", type: .cash, includeInFree: true, sort: 1)
    let usd = Account(name: "Доллары", currency: "USD", type: .card, includeInFree: true, sort: 2)
    let savings = Account(name: "Накопительный", currency: "RUB", type: .savings, includeInFree: false, sort: 3)
    var extraAccounts: [Account] = []
    /// Newest first, as the snapshot hands them over.
    var operations: [OperationFull] = []
    var goals: [Goal] = []
    var device = DeviceSettings(onboarded: true, displayCurrencies: ["RUB", "USD", "GEL"], localCurrency: "GEL")

    var accounts: [Account] { [rub, cash, usd, savings] + extraAccounts }

    var data: AppData {
        AppData(
            snapshot: ProfileSnapshot(
                profile: profile, accounts: accounts, operations: operations, obligations: [], goals: goals, wishes: []
            ),
            device: device,
            rates: [
                RateRecord(code: "USD", rubPerUnit: 80, date: "2026-10-02"),
                RateRecord(code: "GEL", rubPerUnit: 30, date: "2026-10-02"),
            ],
            zone: F.utc
        )
    }

    /// The phone last paid from [account] in this profile.
    mutating func lastUsed(_ account: Account) {
        device.lastAccountId[profile.id] = account.id
    }

    func form(_ request: EntryRequest = EntryRequest()) -> EntryFormModel {
        EntryFormModel(data: data, request: request, today: Self.today)
    }

    /// An operation with its postings, each `(account, amountMinor, rubMinor)`.
    static func operation(
        _ type: OpType, at timestamp: Int64 = now, note: String = "", category: String? = nil,
        purchase: (minor: Int64, currency: String)? = nil, estimate: Bool = false, voice: String? = nil,
        _ postings: [(account: Account, minor: Int64, rub: Int64)]
    ) -> OperationFull {
        var full = F.operation(type, at: timestamp, note: note, category: category, purchase: purchase, estimate: estimate, postings)
        full.op.voiceText = voice
        return full
    }
}
