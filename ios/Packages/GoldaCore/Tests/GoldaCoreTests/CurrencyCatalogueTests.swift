import Foundation
import Testing

@testable import GoldaCore

/// Every currency in circulation can be picked, the popular ones first. Not in Android, whose
/// pickers offered the twelve of `Currencies.common`; see DECISIONS.md.
@Suite struct CurrencyCatalogueTests {
    @Test func thePopularOnesAreAndroidsTwelveWithThePoundAfterTheEuro() {
        #expect(Currencies.popular == ["RUB", "USD", "EUR", "GBP", "GEL", "THB", "TRY", "KZT", "AMD", "CNY", "AED", "VND", "IDR"])
    }

    @Test func everyCurrencyComesOnceThePopularOnesFirstThenTheRestByCode() {
        let all = Currencies.all
        #expect(Set(all).count == all.count)
        #expect(Array(all.prefix(Currencies.popular.count)) == Currencies.popular)
        let rest = Array(all.dropFirst(Currencies.popular.count))
        #expect(rest == rest.sorted())
        #expect(all.allSatisfy { $0.wholeMatch(of: /[A-Z]{3}/) != nil })
    }

    @Test func currenciesTheBankOfRussiaDoesNotPublishAreThere() {
        for code in ["ARS", "MXN", "CLP", "COP", "PEN", "UYU", "PHP", "MYR", "LKR", "KES", "ILS", "ISK", "MAD", "TND"] {
            #expect(Currencies.all.contains(code), "\(code)")
        }
    }

    /// The 53 currencies of cbr-xml-daily.ru on 2026-10-03, without XDR.
    @Test func everyCurrencyTheBankOfRussiaPublishesIsThere() {
        let cbr = """
            AED AMD AUD AZN BDT BHD BOB BRL BYN CAD CHF CNY CUP CZK DKK DZD EGP ETB EUR GBP GEL HKD HUF IDR INR IRR \
            JPY KGS KRW KZT MDL MMK MNT NGN NOK NZD OMR PLN QAR RON RSD SAR SEK SGD THB TJS TMT TRY UAH USD UZS VND ZAR
            """.split(separator: " ").map(String.init)
        for code in cbr { #expect(Currencies.all.contains(code), "\(code)") }
    }

    @Test func fundsMetalsTestCodesAndWithdrawnCurrenciesAreNot() {
        let notMoney = [
            "XAU", "XAG", "XPT", "XPD", "XDR", "XTS", "XXX", "XBA", "XBB", "XBC", "XBD", "XSU", "XUA",
            "CLF", "UYI", "UYW", "BOV", "CHE", "CHW", "COU", "MXV", "USN",
            "HRK", "VEF", "CUC", "SLL", "ZWL", "BGN", "ANG",
        ]
        for code in notMoney { #expect(!Currencies.all.contains(code), "\(code)") }
    }

    @Test func everyCurrencyHasTheMinorUnitsOfISO4217() {
        // The ones with other than two; everything else in the catalogue has two.
        let none = ["BIF", "CLP", "DJF", "GNF", "ISK", "JPY", "KMF", "KRW", "PYG", "RWF", "UGX", "VND", "VUV", "XAF", "XOF", "XPF"]
        let three = ["BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND"]
        for code in Currencies.all {
            let expected = none.contains(code) ? 0 : three.contains(code) ? 3 : 2
            #expect(Currencies.digits(code) == expected, "\(code)")
        }
    }

    @Test func orderingPutsThePopularOnesFirstThenTheRestByCode() {
        #expect(Currencies.ordered(["MXN", "GEL", "ARS", "RUB", "GBP"]) == ["RUB", "GBP", "GEL", "ARS", "MXN"])
        // Each once; a code outside the catalogue (an old backup can have one) is kept, among the rest.
        #expect(Currencies.ordered(["ZZZ", "USD", "ARS", "USD"]) == ["USD", "ARS", "ZZZ"])
        #expect(Currencies.ordered([]) == [])
    }
}

/// The shown currencies keep the catalogue's order, whatever is added.
@Suite struct ShownCurrencyOrderTests {
    @Test func aRareCurrencyGoesAfterThePopularOnes() {
        let s = Settings(displayCurrencies: ["RUB", "USD", "GEL"])
        let pesos = CurrencyDisplay.toggleDisplayCurrency(s, "ARS")
        #expect(pesos.displayCurrencies == ["RUB", "USD", "GEL", "ARS"])
        #expect(CurrencyDisplay.toggleDisplayCurrency(pesos, "GBP").displayCurrencies == ["RUB", "USD", "GBP", "GEL", "ARS"])
        #expect(CurrencyDisplay.toggleDisplayCurrency(pesos, "MXN").displayCurrencies == ["RUB", "USD", "GEL", "ARS", "MXN"])
        #expect(CurrencyDisplay.toggleDisplayCurrency(pesos, "ARS").displayCurrencies == ["RUB", "USD", "GEL"])
    }

    @Test func aShownCodeOutsideTheCatalogueSurvivesAnotherToggle() {
        // Before, the list was rebuilt from the twelve common ones and lost anything else.
        let s = Settings(displayCurrencies: ["RUB", "BGN", "USD"])
        #expect(CurrencyDisplay.toggleDisplayCurrency(s, "GEL").displayCurrencies == ["RUB", "USD", "GEL", "BGN"])
        #expect(CurrencyDisplay.toggleDisplayCurrency(s, "BGN").displayCurrencies == ["RUB", "USD"])
    }

    @Test func aRareLocalOrMainCurrencyFallsBackToRublesWhenHidden() {
        let s = Settings(displayCurrencies: ["RUB", "USD", "ARS"], localCurrency: "ARS", baseCurrency: "ARS")
        let hidden = CurrencyDisplay.toggleDisplayCurrency(s, "ARS")
        #expect(hidden.localCurrency == "RUB")
        #expect(hidden.baseCurrency == "RUB")
        // The ruble still always stays.
        #expect(CurrencyDisplay.toggleDisplayCurrency(s, "RUB") == s)
    }

    @Test func aMainCurrencyWithoutARateYetIsShownInRubles() {
        // Pesos are picked before any source had their rate: amounts stay in rubles, nothing breaks.
        let rates = Rates(["USD": 83.25], markup: 0.10)
        let base = Base.of(Settings(displayCurrencies: ["RUB", "ARS"], baseCurrency: "ARS"), rates)
        #expect(base.code == "RUB")
        #expect(base.whole(184_900) == Base(rates, "RUB").whole(184_900))
        let others = CurrencyDisplay.others(
            rubMinor: 184_900, exclude: "RUB", settings: Settings(displayCurrencies: ["RUB", "USD", "ARS"]), rates: rates
        )
        #expect(symbols(of: others) == ["$"])
    }
}
