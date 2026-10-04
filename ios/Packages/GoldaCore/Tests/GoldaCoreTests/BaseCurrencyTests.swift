import Foundation
import Testing

@testable import GoldaCore

/// Port of BaseCurrencyTest.kt, except the backup case, which belongs to stage 1 with the backup code.
/// The main currency: ruble aggregates shown in it at today's display rate, and nothing else changes.
@Suite struct BaseCurrencyTests {
    let rates = Rates(["USD": 83.25, "GEL": 31.96], markup: 0.10)

    // 1 849 ₽ "можно сегодня", 2 648 ₽ a day.
    let left: Int64 = 184_900
    let perDay: Int64 = 264_800

    @Test func rublesStayExactlyAsTheyWere() {
        let base = Base(rates, "RUB")
        #expect(base.whole(left) == Fmt.split(left, "RUB").whole + " ₽")
        #expect(base.approx(perDay) == Fmt.approx(Double(perDay) / 100.0, "RUB"))
        #expect(base.minor(left) == left)
        #expect(base.code == "RUB")
    }

    @Test func aggregatesConvertAtTheDisplayRate() {
        let usd = Base(rates, "USD")
        let dollar = 83.25 * 1.10
        expectClose(usd.major(left), 1_849.0 / dollar, 1e-9)
        #expect(usd.approx(perDay) == Fmt.approx(2_648.0 / dollar, "USD"))
        #expect(usd.whole(left) == "20 $") // 20,19 $
        #expect(usd.minor(left) == 2_019)

        let lari = Base(rates, "GEL")
        #expect(lari.whole(left) == "53 ₾") // 52,59 ₾, rounded like `approx` (D61; Kotlin cuts to 52)
        #expect(lari.approx(left) == Fmt.approx(1_849.0 / (31.96 * 1.10), "GEL"))
    }

    /// The hero and the toast under it say the same number (D61): 1 941,52 ₽ is «1 942 ₽» in both.
    @Test func wholeUnitsRoundAsTheApproximateAmountsDo() {
        let base = Base(rates, "RUB")
        #expect(base.whole(194_152) == "1\u{202F}942 ₽")
        #expect(base.whole(194_152) == base.approx(194_152))
        #expect(base.whole(-12_060) == base.approx(-12_060))
    }

    @Test func aCurrencyWithoutARateFallsBackToRubles() {
        let base = Base(rates, "THB")
        #expect(base.code == "RUB")
        #expect(base.whole(left) == Base(rates, "RUB").whole(left))
    }

    @Test func theOthersLineLeavesOutTheMainCurrencyAndKeepsRubles() {
        let settings = Settings(displayCurrencies: ["RUB", "USD", "GEL"], localCurrency: "GEL", baseCurrency: "GEL")
        let rates = Rates(["USD": 83.25, "GEL": 31.96], markup: settings.markup)
        let base = Base.of(settings, rates)
        let line = CurrencyDisplay.others(rubMinor: left, exclude: base.code, settings: settings, rates: rates)
        #expect(symbols(of: line) == ["₽", "$"])
    }

    @Test func hidingTheMainCurrencyFallsBackToRubles() {
        let s = Settings(displayCurrencies: ["RUB", "USD", "GEL"], localCurrency: "RUB", baseCurrency: "USD")
        let hidden = CurrencyDisplay.toggleDisplayCurrency(s, "USD")
        #expect(hidden.baseCurrency == "RUB")
        #expect(!hidden.displayCurrencies.contains("USD"))
        // Hiding another one leaves it alone.
        #expect(CurrencyDisplay.toggleDisplayCurrency(s, "GEL").baseCurrency == "USD")
    }
}
