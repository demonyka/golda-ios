import Foundation
import Testing

@testable import GoldaCore

/// The person's own currencies in a voice note: «хлеб 200 песо» with Argentine pesos among them is
/// pesos of Argentina, and «хлеб 50 тетри» is half a lari. The prompt tells the model; the mapper
/// catches a model that still answers with another peso.
@Suite struct VoiceCurrencyNamesTests {
    let rates = Rates(["USD": 83.2454, "GEL": 31.9597, "ARS": 0.0853, "AUD": 54.6], markup: 0.10)
    let rubCard = Account(id: uid(1), name: "Карта ₽", currency: "RUB", type: .card, includeInFree: true, sort: 0)
    let cash = Account(id: uid(2), name: "Наличные", currency: "GEL", type: .cash, includeInFree: true, sort: 1)
    let pesos = Account(id: uid(3), name: "Песо", currency: "ARS", type: .cash, includeInFree: true, sort: 2)
    let now = LocalDate(2026, 10, 4).atTimeMillis(hour: 20, in: utc)

    struct Failure: Error {}

    func prompt(_ accounts: [Account], _ settings: Settings) -> String {
        VoicePrompt.system(accounts: accounts, categories: [], settings: settings, today: LocalDate(2026, 10, 4))
    }

    func map(_ item: VoiceItem, _ accounts: [Account], _ settings: Settings) -> VoiceAction? {
        VoiceMapper.actions(
            VoiceResult(transcript: "…", items: [item]), accounts: accounts, categories: [], settings: settings,
            rates: rates, recordedAt: now, zone: utc
        ).first
    }

    /// What the mapper makes of a «хочу купить» in [currency]: the currency it settles on, with no
    /// account or rate in the way.
    func considered(_ currency: String, holding display: [String], local: String = "RUB", accounts: [Account] = []) throws -> String {
        let item = VoiceItem(intent: "consider", amount: "200", currency: currency, note: "хлеб")
        guard case .consider(let consider) = map(item, accounts, Settings(displayCurrencies: display, localCurrency: local)) else { throw Failure() }
        return consider.currency
    }

    func expense(_ amount: String, _ currency: String, from account: String? = nil) throws -> Draft {
        let item = VoiceItem(intent: "expense", amount: amount, currency: currency, note: "хлеб", accountId: account)
        let settings = Settings(displayCurrencies: ["RUB", "USD", "GEL"], localCurrency: "GEL", lastAccountId: rubCard.id)
        guard case .record(let draft) = map(item, [rubCard, cash, pesos], settings) else { throw Failure() }
        return draft
    }

    // MARK: The prompt

    @Test func thePromptNamesEachOfThePersonsCurrenciesOnceLocalFirst() {
        let text = prompt([rubCard, cash, pesos], Settings(displayCurrencies: ["RUB", "USD"], localCurrency: "GEL"))
        let lines = [
            "- GEL — грузинский лари, «лари»; тетри = 1/100",
            "- RUB — российский рубль, «рубль», «руб»; копейка = 1/100",
            "- USD — доллар США, «доллар», «бакс»; цент = 1/100",
            "- ARS — аргентинский песо, «песо»; сентаво = 1/100",
        ]
        let positions = lines.map { text.range(of: $0)?.lowerBound }
        #expect(positions.allSatisfy { $0 != nil })
        #expect(positions.compactMap { $0 } == positions.compactMap { $0 }.sorted())
        #expect(text.components(separatedBy: "- RUB —").count == 2)
    }

    @Test func aCurrencyIsListedAsFarAsItIsKnown() {
        let text = prompt([], Settings(displayCurrencies: ["RUB", "VND", "XYZ"], localCurrency: "RUB"))
        // The dong has no coin to speak of; a code Foundation does not know is listed as it is.
        #expect(text.contains("- VND — вьетнамский донг, «донг»\n"))
        #expect(text.contains("- XYZ\n"))
    }

    @Test func thePromptStatesTheSharedNameAndCoinRules() {
        let text = prompt([cash, pesos], Settings(displayCurrencies: ["RUB", "USD"], localCurrency: "GEL"))
        // The explicit mapping still stands, for currencies the person does not hold.
        #expect(text.contains("Валюта — код ISO: лари GEL, бат THB, доллар/бакс USD, рубль RUB, евро EUR"))
        #expect(text.contains("Название, которое носят несколько валют (рубль, доллар, дирхам, рупия, песо, фунт, крона, франк, динар, риал, риял, шиллинг, вона"))
        #expect(text.contains("«хлеб 200 песо» при ARS в списке — ARS"))
        #expect(text.contains("доллар — USD"))
        #expect(text.contains("«50 тетри» — amount \"0.50\", currency GEL"))
        #expect(text.contains("«2 лари 50 тетри» — \"2.50\", GEL"))
        #expect(text.contains("«50 копеек» — \"0.50\", RUB"))
    }

    // MARK: A shared name the model got wrong

    /// «Хлеб 200 песо»: the model wrote Mexican pesos, the person holds Argentine ones.
    @Test func anotherPesoBecomesThePersonsOwnPeso() throws {
        #expect(try considered("MXN", holding: ["RUB", "USD"], accounts: [pesos]) == "ARS")
        #expect(try considered("MXN", holding: ["RUB", "ARS"]) == "ARS")
        let d = try expense("200", "MXN")
        #expect(d.accountId == pesos.id)
        #expect(d.amountMinor == 20_000)
        #expect(!d.isEstimate)
    }

    /// Both dollars held: whichever was said stands, and a third dollar stays the one said.
    @Test func aNameTwoHeldCurrenciesShareKeepsWhatWasSaid() throws {
        #expect(try considered("USD", holding: ["RUB", "USD", "AUD"]) == "USD")
        #expect(try considered("AUD", holding: ["RUB", "USD", "AUD"]) == "AUD")
        #expect(try considered("CAD", holding: ["RUB", "USD", "AUD"]) == "CAD")
    }

    @Test func aNameNoHeldCurrencyHasKeepsWhatWasSaid() throws {
        #expect(try considered("MXN", holding: ["RUB", "USD"], local: "GEL") == "MXN")
        #expect(try considered("THB", holding: ["RUB", "USD"], local: "GEL") == "THB")
    }

    /// Kronas and dollars are different names: an Australian holding no krona still gets the krona said.
    @Test func onlyTheSameNameIsTakenForTheHeldOne() throws {
        #expect(try considered("SEK", holding: ["RUB", "AUD"]) == "SEK")
        #expect(try considered("USD", holding: ["RUB", "AUD"]) == "AUD")
    }

    // MARK: Coins

    /// «Хлеб 50 тетри»: half a lari, from the lari cash.
    @Test func fiftyTetriAreFiftyMinorLari() throws {
        let d = try expense("0.50", "GEL")
        #expect(d.accountId == cash.id)
        #expect(d.amountMinor == 50)
        #expect(!d.isEstimate)
        #expect(try expense("2.50", "GEL").amountMinor == 250)
    }

    /// «Хлеб 50 тетри с рублёвой карты»: the purchase stays 50 tetri, the card charge is a guess.
    @Test func fiftyTetriFromTheRubleCardIsAnEstimate() throws {
        let d = try expense("0.50", "GEL", from: "1")
        #expect(d.accountId == rubCard.id)
        #expect(d.purchaseAmountMinor == 50 && d.purchaseCurrency == "GEL")
        #expect(d.amountMinor == rates.cardCharge(50, purchase: "GEL", account: "RUB"))
        #expect(d.isEstimate)
    }

    @Test func fiftyKopecksAreFiftyMinorRubles() throws {
        let d = try expense("0.50", "RUB")
        #expect(d.accountId == rubCard.id)
        #expect(d.amountMinor == 50)
    }
}
