import Foundation
import Testing

@testable import GoldaCore

/// Where a literal Swift translation of the Kotlin money code gives a different answer. The
/// expected values were taken from the JVM (`Math.round`, `DecimalFormat`, `BigDecimal`).
@Suite struct MoneyParityTests {
    @Test func roundingTiesGoTowardPositiveInfinity() {
        #expect(Money.roundHalfUp(2.5) == 3)
        #expect(Money.roundHalfUp(-2.5) == -2)
        #expect(Money.roundHalfUp(-1.5) == -1)
        #expect(Money.roundHalfUp(-0.5) == 0)
        #expect(Money.roundHalfUp(0.49999999999999994) == 0)
        #expect(Money.roundHalfUp(-0.49999999999999994) == 0)
        #expect(Money.roundHalfUp(1e30) == Int64.max)
        #expect(Money.roundHalfUp(-1e30) == Int64.min)
        #expect(Money.roundHalfUp(.nan) == 0)
        // A negative tie in minor units: -0.125 $ is -12.5 cents.
        #expect(Currencies.toMinor(-0.125, "USD") == -12)
    }

    @Test func amountsAreWrittenTheRussianWay() {
        #expect(Fmt.amount(-421_050, "RUB") == "−4\u{202F}210,50 ₽")
        #expect(Fmt.amount(421_000, "RUB") == "4\u{202F}210 ₽")
        #expect(Fmt.amount(500, "USD", signed: true) == "+5 $")
        #expect(Fmt.amount(-500, "USD", signed: true) == "−5 $")
        #expect(Fmt.amount(0, "USD", signed: true) == "0 $")
        #expect(Fmt.amount(123_456_789, "RUB") == "1\u{202F}234\u{202F}567,89 ₽")
        #expect(Fmt.amount(5, "RUB") == "0,05 ₽")
    }

    @Test func currenciesWithoutMinorUnitsHaveNoFraction() {
        #expect(Fmt.amount(150_000, "VND") == "150\u{202F}000 ₫")
        #expect(Fmt.amount(1_500, "JPY") == "1\u{202F}500 JPY")
        #expect(Fmt.split(1_500, "JPY").fraction == "")
        #expect(Fmt.approx(1_234.5, "JPY") == "1\u{202F}234 JPY") // an exact tie goes to the even digit
        #expect(Fmt.editable(100_000, "JPY") == "100000")
        #expect(Currencies.toMinor(15.4, "JPY") == 15)
    }

    @Test func theBigNumberSplitsIntoWholeAndFraction() {
        let rub = Fmt.split(421_050, "RUB")
        #expect(rub.whole == "4\u{202F}210" && rub.fraction == ",50")
        let round = Fmt.split(421_000, "RUB")
        #expect(round.whole == "4\u{202F}210" && round.fraction == ",00")
        #expect(Fmt.split(-1_050, "RUB").whole == "−10")
    }

    @Test func approximateValuesRoundLikeDecimalFormat() {
        #expect(Fmt.approx(0.15, "USD") == "0,1 $") // 0.15 is a hair under, in binary
        #expect(Fmt.approx(-0.04, "USD") == "−0 $") // a negative that rounds to zero keeps its sign, as in Java
        #expect(Fmt.approx(1_234.5, "RUB") == "1\u{202F}234 ₽")
        #expect(Fmt.approx(1_235.5, "RUB") == "1\u{202F}236 ₽")
        #expect(Fmt.approx(5.0, "USD") == "5 $")
        #expect(Fmt.approx(99.95, "USD") == "100 $") // "100,0" loses its ",0"
        #expect(Fmt.approx(99.94, "USD") == "99,9 $")
        #expect(Fmt.approx(99.5, "USD") == "99,5 $")
        #expect(Fmt.approx(100.5, "USD") == "100 $") // from 100 up there are no decimals, and a tie goes to even
        #expect(Fmt.approx(0.05, "USD") == "0,1 $") // 0.05 is a hair over, in binary
        #expect(Fmt.approx(0.25, "USD") == "0,2 $") // an exact tie goes to the even digit
        #expect(Fmt.approx(2.35, "USD") == "2,4 $")
    }

    @Test func percentsAndNumbers() {
        #expect(Fmt.percent(0.125) == "12,5 %")
        #expect(Fmt.percent(0.1, signed: true) == "+10 %")
        #expect(Fmt.percent(-0.034) == "−3,4 %")
        #expect(Fmt.percent(0) == "0 %")
        #expect(Fmt.number(2.5) == "2,5")
        #expect(Fmt.number(3.0) == "3")
        #expect(Fmt.number(2.675) == "2,67")
        #expect(Fmt.number(0.125) == "0,12")
        #expect(Fmt.number(-0.001) == "−0")
        #expect(Fmt.number(12.25, decimals: 1) == "12,2")
        #expect(Fmt.number(12.35, decimals: 1) == "12,3")
        #expect(Fmt.number(1_234_567.891) == "1234567,89")
    }

    @Test func parsingAcceptsWhatBigDecimalAccepts() {
        #expect(Fmt.parseMinor("1e3", "RUB") == 100_000)
        #expect(Fmt.parseMinor("1E3", "RUB") == 100_000)
        #expect(Fmt.parseMinor("1e-2", "RUB") == 1)
        #expect(Fmt.parseMinor(".5", "RUB") == 50)
        #expect(Fmt.parseMinor("5.", "RUB") == 500)
        #expect(Fmt.parseMinor("+5", "RUB") == 500)
        #expect(Fmt.parseMinor("-0", "RUB") == 0)
        #expect(Fmt.parseMinor("1,5", "RUB") == 150)
        #expect(Fmt.parseMinor("1 500,25", "RUB") == 150_025)
        #expect(Fmt.parseMinor("1\u{202F}500", "RUB") == 150_000)
        #expect(Fmt.parseMinor("1\u{00A0}500", "RUB") == 150_000)
        #expect(Fmt.parseMinor("0,005", "RUB") == 1) // half up
        #expect(Fmt.parseMinor("0,004", "RUB") == 0)
        #expect(Fmt.parseMinor("1500", "JPY") == 1_500)
    }

    @Test func parsingRejectsWhatIsNotAnAmount() {
        for text in ["", "  ", "abc", "15abc", "1e", "0x10", "1_000", "1.2.3", "+", "-", "-5", "-0,01", "nan", "inf"] {
            #expect(Fmt.parseMinor(text, "RUB") == nil, "\(text)")
        }
        #expect(Fmt.parseMinor("99999999999999999999", "RUB") == nil) // does not fit
    }

    @Test func plainNumbersParseOnlyWhenFinite() {
        #expect(Fmt.parseDouble("2,5") == 2.5)
        #expect(Fmt.parseDouble("1 000.5") == 1_000.5)
        #expect(Fmt.parseDouble("-3") == -3)
        #expect(Fmt.parseDouble("abc") == nil)
        #expect(Fmt.parseDouble("nan") == nil)
        #expect(Fmt.parseDouble("inf") == nil)
    }

    @Test func editableTextDropsTrailingZeros() {
        #expect(Fmt.editable(1_500, "GEL") == "15")
        #expect(Fmt.editable(1_550, "GEL") == "15,5")
        #expect(Fmt.editable(-305, "USD") == "-3,05")
        #expect(Fmt.editable(0, "RUB") == "0")
        #expect(Fmt.editable(5, "USD") == "0,05")
    }

    /// The digits `java.util.Currency` reports (JDK 21) for every currency the CBR publishes, plus the
    /// ones with other than two. Apple's NumberFormatter is no reference here: it reports the cash
    /// digits for IDR, RSD and COP (0), where ISO 4217 and the JVM say 2.
    @Test func minorUnitsMatchTheJVM() {
        let expected: [String: Int] = [
            "AUD": 2, "AZN": 2, "GBP": 2, "AMD": 2, "BYN": 2, "BGN": 2, "BRL": 2, "HUF": 2, "VND": 0, "HKD": 2, "GEL": 2,
            "DKK": 2, "AED": 2, "USD": 2, "EUR": 2, "EGP": 2, "INR": 2, "IDR": 2, "KZT": 2, "CAD": 2, "QAR": 2, "KGS": 2,
            "CNY": 2, "MDL": 2, "NZD": 2, "NOK": 2, "PLN": 2, "RON": 2, "SGD": 2, "TJS": 2, "THB": 2, "TRY": 2, "TMT": 2,
            "UZS": 2, "UAH": 2, "CZK": 2, "SEK": 2, "CHF": 2, "RSD": 2, "ZAR": 2, "KRW": 0, "JPY": 0, "RUB": 2, "COP": 2,
            "CLP": 0, "ISK": 0, "KWD": 3, "BHD": 3, "XDR": 0, "XXX": 0,
        ]
        for (code, digits) in expected { #expect(Currencies.digits(code) == digits, "\(code)") }
        #expect(Currencies.digits("ZZZ") == 2) // unknown codes: two, as the Kotlin fallback does
        for code in Currencies.common { #expect(expected[code] != nil, "\(code) is missing from the table") }
    }
}
