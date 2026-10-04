import Testing

@testable import Golda

/// Where a wrapping line may break: at the large text sizes a line under an amount wraps, and it
/// must not leave "₽" or "дней" alone at the start of a line, start a line with "·", or end one on "≈".
@Suite struct LineBreakTests {
    /// The thousands space of `Fmt`, already a no-break one.
    private let thousands = "\u{202F}"
    private let glue = "\u{00A0}"

    @Test func aNumberKeepsItsCurrencySign() {
        #expect("сентябрь ≈ 158\(thousands)400 ₽".keepingMarksOnTheLine == "сентябрь ≈\(glue)158\(thousands)400\(glue)₽")
        #expect("78,01 $".keepingMarksOnTheLine == "78,01\(glue)$")
    }

    @Test func aNumberKeepsTheWordAfterIt() {
        #expect(
            "3\(thousands)026 ₽ в день · 7 дней до зарплаты".keepingMarksOnTheLine
                == "3\(thousands)026\(glue)₽ в день\(glue)· 7\(glue)дней до зарплаты"
        )
        #expect("110 % · из 300\(thousands)000 ₽".keepingMarksOnTheLine == "110\(glue)%\(glue)· из 300\(thousands)000\(glue)₽")
    }

    @Test func theDotsAndTheApproximateSignStayAsBefore() {
        #expect("Наличные · ≈ 5\(thousands)971 ₽".keepingMarksOnTheLine == "Наличные\(glue)· ≈\(glue)5\(thousands)971\(glue)₽")
    }

    @Test func wordsAndALastSpaceAreLeftAlone() {
        #expect("Pay off early".keepingMarksOnTheLine == "Pay off early")
        #expect("Rent 5 ".keepingMarksOnTheLine == "Rent 5 ")
        #expect("5  days".keepingMarksOnTheLine == "5  days")
        #expect("".keepingMarksOnTheLine == "")
    }
}
