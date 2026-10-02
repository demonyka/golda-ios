import Foundation
import Testing

@testable import GoldaCore

/// Port of SettingsEffectsTest.kt. Where each setting reaches the logic: a change in Settings has
/// to change what these return.
@Suite struct SettingsEffectsTests {
    let rubCard = Account(id: uid(1), name: "Карта ₽", currency: "RUB", type: .card, includeInFree: true, sort: 0)
    let usdCard = Account(id: uid(2), name: "Доллары", currency: "USD", type: .card, includeInFree: true, sort: 1)
    let gelCash = Account(id: uid(3), name: "Лари", currency: "GEL", type: .cash, includeInFree: true, sort: 2)

    var accounts: [Account] { [rubCard, usdCard, gelCash] }

    func rates(_ s: Settings) -> Rates { Rates(["USD": 83.25, "GEL": 31.96], markup: s.markup) }

    @Test func theLocalCurrencyLeadsTheCurrencyChoicesAndTheOthersLine() {
        let shown = ["RUB", "USD", "GEL"]
        let rub = Settings(displayCurrencies: shown, localCurrency: "RUB")
        let gel = Settings(displayCurrencies: shown, localCurrency: "GEL")
        #expect(CurrencyDisplay.currencyChoices(settings: rub) == ["RUB", "USD", "GEL"])
        #expect(CurrencyDisplay.currencyChoices(settings: gel) == ["GEL", "RUB", "USD"])
        let others = CurrencyDisplay.others(rubMinor: 100_000, exclude: "RUB", settings: gel, rates: rates(gel))
        #expect(symbols(of: others) == ["₾", "$"])
    }

    @Test func theOthersLineShowsExactlyTheShownCurrencies() {
        let s = Settings(displayCurrencies: ["RUB", "USD"], localCurrency: "RUB")
        let line = CurrencyDisplay.others(rubMinor: 100_000, exclude: "RUB", settings: s, rates: rates(s))
        #expect(symbols(of: line) == ["$"])
    }

    @Test func aNewPurchaseIsPaidFromAnAccountInTheLocalCurrency() {
        // The entry form asks the same question as voice: who pays in this currency?
        let usedLast = Settings(localCurrency: "GEL", lastAccountId: rubCard.id)
        #expect(VoiceMapper.pick(accounts, usedLast.localCurrency, usedLast)?.id == gelCash.id)
        #expect(VoiceMapper.pick(accounts, "USD", usedLast)?.id == usdCard.id)
        #expect(VoiceMapper.pick(accounts, "RUB", usedLast)?.id == rubCard.id)
        // No account in the local currency: the last one used, converted.
        #expect(VoiceMapper.pick(accounts, "THB", usedLast)?.id == rubCard.id)
    }

    @Test func hidingTheLocalCurrencyFallsBackToRubles() {
        let s = Settings(displayCurrencies: ["RUB", "USD", "GEL"], localCurrency: "GEL")
        let hidden = CurrencyDisplay.toggleDisplayCurrency(s, "GEL")
        #expect(hidden.displayCurrencies == ["RUB", "USD"])
        #expect(hidden.localCurrency == "RUB")
        // Rubles can't be hidden: they are the base.
        #expect(CurrencyDisplay.toggleDisplayCurrency(s, "RUB") == s)
    }

    @Test func paydaySetsTheDaysLeft() {
        let today = LocalDate(2026, 10, 2)
        #expect(Settings(payday: 15).nextPayday(today) == LocalDate(2026, 10, 15))
        // On payday itself the next one is a month away.
        #expect(Settings(payday: 2).nextPayday(today) == LocalDate(2026, 11, 2))
        #expect(Settings(payday: 1).nextPayday(today) == LocalDate(2026, 11, 1))
        // The 31st in a 30-day month is its last day.
        #expect(Settings(payday: 31).nextPayday(LocalDate(2026, 11, 2)) == LocalDate(2026, 11, 30))

        let states = Ledger.states(accounts, [])
        func daysLeft(_ payday: Int) -> Int {
            Budget.today(states: states, operations: [], settings: Settings(payday: payday), today: today, zone: utc).daysLeft
        }
        #expect(daysLeft(15) == 13)
        #expect(daysLeft(10) == 8)
        #expect(daysLeft(2) == 31)
    }

    @Test func rateAndTaxSetTheHourOnHand() {
        expectClose(Settings(incomeHourly: true, hourlyRate: 3_000, taxPercent: 20).hourNet, 2_400, 1e-9)
        // A salary of 173 333 ₽ over 40 h a week (173.33 h a month), 13 % tax: about 870 ₽ an hour.
        expectClose(Settings(incomeHourly: false, monthlySalary: 173_333, taxPercent: 13, hoursPerWeek: 40).hourNet, 870, 0.5)
    }
}
