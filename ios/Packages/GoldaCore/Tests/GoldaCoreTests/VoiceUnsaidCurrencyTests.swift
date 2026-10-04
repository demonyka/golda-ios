import Foundation
import Testing

@testable import GoldaCore

/// An amount said without a currency (D44, unlike Android): money moved between the person's own
/// accounts or coming into one is counted in those accounts' money; a purchase stays in the local
/// money, whatever card pays for it.
@Suite struct VoiceUnsaidCurrencyTests {
    let rates = Rates(["USD": 83.2454, "GEL": 31.9597, "THB": 2.47438], markup: 0.10)
    let rubCard = Account(id: uid(1), name: "Карта ₽", currency: "RUB", type: .card, includeInFree: true, sort: 0)
    let multiUsd = Account(id: uid(2), name: "Мультивалютная USD", currency: "USD", type: .card, includeInFree: true, sort: 1)
    let cash = Account(id: uid(3), name: "Наличные", currency: "GEL", type: .cash, includeInFree: true, sort: 2)
    let savings = Account(id: uid(4), name: "Накопительный", currency: "RUB", type: .savings, includeInFree: false, sort: 3)
    let now = LocalDate(2026, 10, 2).atTimeMillis(hour: 20, in: utc)

    var settings: Settings {
        Settings(displayCurrencies: ["RUB", "USD", "GEL"], localCurrency: "GEL", lastAccountId: multiUsd.id)
    }

    func draft(_ intent: String, _ amount: String, from: String? = nil, to: String? = nil) throws -> Draft {
        let item = VoiceItem(intent: intent, amount: amount, currency: nil, note: "", accountId: from, toAccountId: to)
        let actions = VoiceMapper.actions(
            VoiceResult(transcript: "…", items: [item]), accounts: [rubCard, multiUsd, cash, savings], categories: [],
            settings: settings, rates: rates, recordedAt: now, zone: utc
        )
        guard case .record(let draft) = actions.first else { throw Failure() }
        return draft
    }

    struct Failure: Error {}

    /// «Перевёл с карты на накопительный восемьдесят тысяч»: rubles, not 80 000 lari.
    @Test func aTransferBetweenRubleAccountsIsInRubles() throws {
        let d = try draft("transfer", "80000", from: "1", to: "4")
        #expect(d.accountId == rubCard.id && d.toAccountId == savings.id)
        #expect(d.amountMinor == 8_000_000)
        #expect(d.toAmountMinor == 8_000_000)
        #expect(!d.isEstimate)
    }

    /// «Отложил восемьдесят тысяч на накопительный»: the destination's money, and the ruble card it
    /// comes from.
    @Test func aTransferNamingOnlyTheDestinationIsInItsCurrency() throws {
        let d = try draft("transfer", "80000", to: "4")
        #expect(d.accountId == rubCard.id)
        #expect(d.amountMinor == 8_000_000)
    }

    /// «Перевёл сто с долларовой на рублёвую», the local money being lari: the dollars it leaves in.
    @Test func aTransferBetweenTwoForeignCurrenciesIsInTheSourceCurrency() throws {
        let d = try draft("transfer", "100", from: "2", to: "1")
        #expect(d.amountMinor == 10_000)
        #expect(d.toAmountMinor == rates.convert(10_000, from: "USD", to: "RUB"))
    }

    /// «Снял двести с карты в наличные»: a cash machine gives local money, as before.
    @Test func aTransferIntoLocalCashStaysInLocalMoney() throws {
        let d = try draft("transfer", "200", from: "1", to: "3")
        #expect(d.amountMinor == rates.convert(20_000, from: "GEL", to: "RUB"))
    }

    /// «Зарплата сто пятьдесят тысяч на карту»: rubles on the ruble card.
    @Test func incomeToANamedAccountIsInItsCurrency() throws {
        let d = try draft("income", "150000", from: "1")
        #expect(d.accountId == rubCard.id)
        #expect(d.amountMinor == 15_000_000)
    }

    @Test func incomeWithoutAnAccountIsInLocalMoney() throws {
        let d = try draft("income", "100")
        #expect(d.accountId == cash.id)
        #expect(d.amountMinor == 10_000)
    }

    /// «Кофе восемь с рублёвой карты» abroad: eight lari, charged to the card as an estimate.
    @Test func aPurchaseFromANamedForeignCardStaysInLocalMoney() throws {
        let d = try draft("expense", "8", from: "1")
        #expect(d.accountId == rubCard.id)
        #expect(d.purchaseAmountMinor == 800 && d.purchaseCurrency == "GEL")
        #expect(d.isEstimate)
    }
}
