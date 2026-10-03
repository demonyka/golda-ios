import Foundation
import GoldaCore
import GoldaData

@testable import Golda

/// One profile's accounts built by hand, shaped like Android's demo: a ruble card, savings at 12 %,
/// a multi-currency card in two parts (dollars and lari), lari cash, a credit card at 29,9 % and a
/// loan at 19,9 %. Rates are 80 ₽ a dollar and 30 ₽ a lari with the default 10 % markup, "today" is
/// 2026-10-02 in UTC, and the postings carry their ruble worth as written:
///
/// - Карта ₽: 20 000 ₽ opened on September 1, 18 400 ₽ sent to dollars on the 20th: 1 600 ₽.
/// - Накопительный: 250 000 ₽ opened on September 1.
/// - Мультивалютная USD: 200 $ for 18 400 ₽, 100 $ of them changed into 268 ₾ on the 21st: 100 $
///   worth 9 200 ₽ (92 ₽ a dollar).
/// - Мультивалютная GEL: those 268 ₾, 10 ₾ spent this morning: 258 ₾ worth 8 856,72 ₽.
/// - Наличные ₾: 172 ₾ opened at 30 ₽: 5 160 ₽.
/// - Кредитка: −15 000 ₽. Кредит: −200 000 ₽.
struct AccountsFixture {
    typealias F = HomeFixture

    var profile = Profile(name: "Личный", settings: ProfileSettings(from: Settings(payday: 10)))
    var card = Account(name: "Карта ₽", currency: "RUB", type: .card, includeInFree: true, sort: 0)
    var savings = Account(name: "Накопительный", currency: "RUB", type: .savings, includeInFree: false, interestRate: 12, sort: 1)
    var usd = Account(
        name: "Мультивалютная USD", currency: "USD", type: .card, groupName: "Мультивалютная", includeInFree: true, sort: 2
    )
    var gel = Account(
        name: "Мультивалютная GEL", currency: "GEL", type: .card, groupName: "Мультивалютная", includeInFree: true, sort: 3
    )
    var cash = Account(name: "Наличные ₾", currency: "GEL", type: .cash, includeInFree: true, sort: 4)
    var credit = Account(name: "Кредитка", currency: "RUB", type: .credit, includeInFree: false, interestRate: 29.9, sort: 5)
    var loan = Account(name: "Кредит", currency: "RUB", type: .loan, includeInFree: false, interestRate: 19.9, sort: 6)
    var device = DeviceSettings(onboarded: true, displayCurrencies: ["RUB", "USD", "GEL"], localCurrency: "GEL")

    var accounts: [Account] { [card, savings, usd, gel, cash, credit, loan] }

    let september1 = LocalDate(2026, 9, 1)

    /// Newest first, as the snapshot hands them over.
    var operations: [OperationFull] {
        [
            F.operation(.expense, at: F.at(hour: 9), note: "Продукты", category: "groceries", [(gel, -1_000, -34_328)]),
            F.operation(
                .transfer, at: F.at(LocalDate(2026, 9, 21), hour: 12), note: "Обмен",
                [(usd, -10_000, -920_000), (gel, 26_800, 920_000)]
            ),
            F.operation(
                .transfer, at: F.at(LocalDate(2026, 9, 20), hour: 12), note: "Перевод за границу",
                [(card, -1_840_000, -1_840_000), (usd, 20_000, 1_840_000)]
            ),
            F.operation(.opening, at: F.at(september1, hour: 8), [(loan, -20_000_000, -20_000_000)]),
            F.operation(.opening, at: F.at(september1, hour: 8), [(credit, -1_500_000, -1_500_000)]),
            F.operation(.opening, at: F.at(september1, hour: 8), [(cash, 17_200, 516_000)]),
            F.operation(.opening, at: F.at(september1, hour: 8), [(savings, 25_000_000, 25_000_000)]),
            F.operation(.opening, at: F.at(september1, hour: 8), [(card, 2_000_000, 2_000_000)]),
        ]
    }

    func data(accounts: [Account]? = nil, operations: [OperationFull]? = nil) -> AppData {
        AppData(
            snapshot: ProfileSnapshot(
                profile: profile, accounts: accounts ?? self.accounts, operations: operations ?? self.operations,
                obligations: [], goals: [], wishes: []
            ),
            device: device,
            rates: [
                RateRecord(code: "USD", rubPerUnit: 80, date: "2026-10-02"),
                RateRecord(code: "GEL", rubPerUnit: 30, date: "2026-10-02"),
            ],
            zone: F.utc
        )
    }

    var data: AppData { data() }

    var content: AccountsContent { AccountsContent(data: data, today: F.today) }

    /// The row of [account] on the Accounts tab.
    func row(_ account: Account, in data: AppData? = nil) throws -> AccountRowModel {
        let data = data ?? self.data
        guard let state = data.states[account.id] else { throw FixtureError.noAccount }
        return AccountRowModel(state, in: data, today: F.today)
    }

    func page(_ account: Account) throws -> AccountPageModel {
        guard let page = AccountPageModel(data: data, accountId: account.id, today: F.today) else { throw FixtureError.noAccount }
        return page
    }

    enum FixtureError: Error { case noAccount }
}
