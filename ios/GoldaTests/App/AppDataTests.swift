import Foundation
import GoldaCore
import GoldaData
import Testing

@testable import Golda

/// The values Android's `AppData` derives, on the debug fill and the sample life.
@MainActor @Suite(.timeLimit(.minutes(1))) struct AppDataTests {
    let harness: AppHarness

    init() throws {
        harness = try AppHarness()
    }

    /// The made-up person's books as the screens get them.
    private func open(_ command: LaunchCommand) async throws -> AppData {
        await harness.model.start(command: command, profileName: "Личный")
        return try await harness.data()
    }

    private func account(_ name: String, in data: AppData) throws -> Account {
        try #require(data.accounts.first { $0.name == name })
    }

    @Test func visibleOperationsLeaveOutTheOpeningBalances() async throws {
        let data = try await open(.samples)

        #expect(data.operations.count == 28)
        #expect(data.visibleOperations.count == 24)
        #expect(!data.visibleOperations.contains { $0.op.type == .opening })
        // Newest first, as stored: the coffee an hour ago, then the shawarma.
        #expect(data.visibleOperations.prefix(2).map(\.op.note) == ["Кофе", "Шаурма"])
    }

    @Test func theUsualAccountIsTheFirstFreeOneUntilAnExpenseNamesAnother() async throws {
        let data = try await open(.demo)
        #expect(data.settings.lastAccountId == nil)
        // The savings account comes second but does not count towards today's money.
        #expect(data.usualAccountId == (try account("Карта ₽", in: data)).id)

        let cash = try account("Наличные ₾", in: data)
        try await harness.model.save(
            Draft(type: .expense, timestamp: AppHarness.now, accountId: cash.id, amountMinor: 500, categoryKey: "eating_out")
        )

        await eventually { harness.model.data?.usualAccountId == cash.id }
        #expect(harness.model.data?.settings.lastAccountId == cash.id)
    }

    @Test func theUsualAccountIsNoneWithoutAFreeAccount() async throws {
        let savings = Account(name: "Накопительный", currency: "RUB", type: .savings, includeInFree: false)
        let personal = try await harness.profile("Личный", accounts: [savings])
        harness.onboard(active: personal)
        await harness.model.start()

        #expect(try await harness.data().usualAccountId == nil)
    }

    @Test func allObligationsAddTheDebtPaymentsAfterTheTypedOnes() async throws {
        let data = try await open(.samples)
        let credit = try account("Кредитка", in: data)
        let loan = try account("Кредит", in: data)

        #expect(data.obligations.count == 2)
        // Typed payments of one day come in id order, so only their set is fixed.
        #expect(Set(data.allObligations.prefix(2).map(\.name)) == ["Аренда", "Подписки"])
        #expect(data.allObligations.dropFirst(2).map(\.id) == [credit.id, loan.id])
        #expect(data.allObligations.dropFirst(2).map(\.amountMinor) == [300_000, 1_000_000])
        #expect(data.allObligations.dropFirst(2).map(\.dayOfMonth) == [25, 5])
    }

    @Test func theSamplesGiveAPlausibleBaseAndOthersLine() async throws {
        let data = try await open(.samples)

        #expect(data.settings.localCurrency == "GEL")
        #expect(data.settings.displayCurrencies == ["RUB", "USD", "GEL"])
        // 73 600 ₽ for 800 $ taught the profile its markup: a dollar costs 92 ₽.
        #expect(abs(data.rates.markup - (92 / 83.2454 - 1)) < 1e-12)
        #expect(data.base.code == "RUB")
        // The local currency first, then the display ones, without the main one.
        #expect(data.others(rubMinor: 920_000, exclude: "RUB") == "260 ₾ · 100 $")
        #expect(data.currencyChoices(extra: ["THB"]) == ["GEL", "RUB", "USD", "THB"])
        #expect(data.ratesDate == "2026-10-02")
    }

    @Test func anotherMainCurrencyMovesTheBigNumbersAndTheOthersLine() async throws {
        _ = try await open(.samples)

        harness.device.update { $0.baseCurrency = "USD" }

        await eventually { harness.model.data?.base.code == "USD" }
        let data = try #require(harness.model.data)
        #expect(data.base.whole(920_000) == "100 $")
        #expect(data.others(rubMinor: 920_000, exclude: data.base.code) == "260 ₾ · 9\u{202F}200 ₽")
    }

    @Test func aMainCurrencyWithoutARateFallsBackToRubles() async throws {
        _ = try await open(.samples)

        harness.device.update { $0.baseCurrency = "AMD" }

        await eventually { harness.model.data?.settings.baseCurrency == "AMD" }
        #expect(harness.model.data?.base.code == "RUB")
    }

    @Test func statesSumEachAccountsPostings() async throws {
        let data = try await open(.samples)

        let balances = Dictionary(uniqueKeysWithValues: data.accounts.map { ($0.name, data.states[$0.id]?.balanceMinor) })
        #expect(balances["Карта ₽"] == 910_100)
        #expect(balances["Мультивалютная GEL"] == 23_690)
        #expect(balances["Кредит"] == -20_000_000)
        #expect(data.accountById.count == 7)
    }
}
