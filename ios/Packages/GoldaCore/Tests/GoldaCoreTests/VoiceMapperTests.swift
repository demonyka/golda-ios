import Foundation
import Testing

@testable import GoldaCore

/// Port of VoiceMapperTest.kt. The mapper reads account numbers as positions in the list, so the
/// accounts below are 1, 2 and 3 exactly as the Kotlin ids were.
@Suite struct VoiceMapperTests {
    let rates = Rates(["USD": 83.2454, "GEL": 31.9597, "THB": 2.47438], markup: 0.10)
    let rubCard = Account(id: uid(1), name: "Карта ₽", currency: "RUB", type: .card, includeInFree: true, sort: 0)
    let multiUsd = Account(id: uid(2), name: "Мультивалютная USD", currency: "USD", type: .card, includeInFree: true, sort: 1)
    let cash = Account(id: uid(3), name: "Наличные", currency: "GEL", type: .cash, includeInFree: true, sort: 2)
    let food = Category(key: "eating_out", name: "Еда вне дома", kind: .expense)
    let now = LocalDate(2026, 10, 2).atTimeMillis(hour: 20, in: utc)

    var accounts: [Account] { [rubCard, multiUsd, cash] }
    var settings: Settings {
        Settings(displayCurrencies: ["RUB", "USD", "GEL", "THB"], localCurrency: "GEL", lastAccountId: multiUsd.id)
    }

    func item(_ intent: String, _ amount: String?, _ currency: String?, _ note: String = "", _ extra: [String: String] = [:]) -> VoiceItem {
        VoiceItem(
            intent: intent, amount: amount, currency: currency, note: note, category: extra["category"],
            accountId: extra["account"], toAccountId: extra["to"], toAmount: extra["toAmount"], date: extra["date"]
        )
    }

    func map(_ items: VoiceItem...) -> [VoiceAction] {
        VoiceMapper.actions(VoiceResult(transcript: "…", items: items), accounts: accounts, categories: [food], settings: settings, rates: rates, recordedAt: now, zone: utc)
    }

    func draft(_ action: VoiceAction) throws -> Draft {
        guard case .record(let draft) = action else { throw Failure("not a record: \(action)") }
        return draft
    }

    struct Failure: Error { init(_ message: String) { self.message = message }; let message: String }

    @Test func lariGoToTheLariAccountEvenIfTheLastOneWasDollars() throws {
        let d = try draft(map(item("expense", "15", "GEL", "шаурма", ["category": "eating_out"]))[0])
        #expect(d.accountId == cash.id)
        #expect(d.amountMinor == 1_500)
        #expect(d.categoryKey == food.key)
        #expect(d.note == "Шаурма")
        #expect(d.timestamp == now)
    }

    @Test func noCurrencyMeansLocalCurrency() throws {
        let d = try draft(map(item("expense", "8", nil, "кофе"))[0])
        #expect(d.accountId == cash.id)
        #expect(d.amountMinor == 800)
    }

    @Test func bahtFromADollarCardIsAnEstimatedCharge() throws {
        let d = try draft(map(item("expense", "80", "THB", "пад тай"))[0])
        #expect(d.accountId == multiUsd.id)
        #expect(d.amountMinor == 243)
        #expect(d.purchaseAmountMinor == 8_000)
        #expect(d.purchaseCurrency == "THB")
        #expect(d.isEstimate)
    }

    @Test func twoThingsInOnePhrase() throws {
        let actions = map(item("expense", "8", "GEL", "кофе"), item("expense", "6", "GEL", "круассан"))
        #expect(try actions.map { try draft($0).amountMinor } == [800, 600])
    }

    @Test func wantingIsNotSpending() {
        #expect(map(item("consider", "50", "USD", "бургер")) == [.consider(Consider(title: "Бургер", amountMinor: 5_000, currency: "USD"))])
    }

    @Test func transferWithBothAmounts() throws {
        let d = try draft(map(item("transfer", "10000", "RUB", "", ["account": "1", "to": "2", "toAmount": "108"]))[0])
        #expect(d.type == .transfer)
        #expect(d.amountMinor == 1_000_000)
        #expect(d.toAmountMinor == 10_800)
        #expect(d.toAccountId == multiUsd.id)
        #expect(d.isEstimate == false)
        let guessed = try draft(map(item("transfer", "10000", "RUB", "", ["account": "1", "to": "2"]))[0])
        #expect(guessed.isEstimate)
    }

    @Test func transferWithoutDestinationIsNotGuessed() {
        guard case .notUnderstood = map(item("transfer", "100", "USD", "", ["account": "2"]))[0] else {
            Issue.record("expected notUnderstood")
            return
        }
    }

    @Test func yesterdayLandsAtNoonYesterday() throws {
        let d = try draft(map(item("expense", "20", "GEL", "такси", ["date": "2026-10-01"]))[0])
        #expect(d.timestamp == LocalDate(2026, 10, 1).atTimeMillis(hour: 12, in: utc))
    }

    @Test func nonsenseAndMissingAmountsAreReported() {
        func isLost(_ action: VoiceAction) -> Bool { if case .notUnderstood = action { true } else { false } }
        #expect(isLost(map(item("unknown", nil, nil))[0]))
        #expect(isLost(map(item("expense", nil, "GEL", "что-то"))[0]))
        let empty = VoiceMapper.actions(VoiceResult(transcript: "ммм", items: []), accounts: accounts, categories: [food], settings: settings, rates: rates, recordedAt: now, zone: utc)
        #expect(empty.count == 1 && isLost(empty[0]))
    }

    @Test func promptListsAccountsAndCategories() {
        let prompt = VoicePrompt.system(accounts: accounts, categories: [food], settings: settings, today: LocalDate(2026, 10, 2))
        #expect(prompt.contains("- 3: Наличные, GEL, cash"))
        #expect(prompt.contains("eating_out (Еда вне дома)"))
        #expect(prompt.contains("Местная валюта: GEL"))
    }
}
