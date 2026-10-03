import GoldaCore
import SwiftUI
import Testing
import UIKit

@testable import Golda

@Suite struct AmountPartsTests {
    private let thin = "\u{202F}"

    @Test func wholeUnitsOnly() {
        let parts = AmountParts(parsing: "1\(thin)849 ₽")
        #expect(parts.whole == "1\(thin)849")
        #expect(parts.fraction == "")
        #expect(parts.symbol == "₽")
        #expect(parts.text == "1\(thin)849 ₽")
    }

    @Test func fractionKeepsItsSeparator() {
        let parts = AmountParts(parsing: "174,75 $")
        #expect(parts.whole == "174")
        #expect(parts.fraction == ",75")
        #expect(parts.symbol == "$")
    }

    @Test func aNegativeAmountKeepsItsMinusInTheWholePart() {
        let parts = AmountParts(parsing: "−4\(thin)210,50 ₽")
        #expect(parts.whole == "−4\(thin)210")
        #expect(parts.fraction == ",50")
        #expect(parts.symbol == "₽")
    }

    @Test func aPlainNumberHasNoSymbol() {
        let parts = AmountParts(parsing: "12,5")
        #expect(parts.whole == "12")
        #expect(parts.fraction == ",5")
        #expect(parts.symbol == "")
        #expect(AmountParts(parsing: "1 849").symbol == "", "a trailing group of digits is not a symbol")
    }

    @Test func partsAlwaysPutBackTheTextTheyCameFrom() {
        for text in ["1\(thin)849 ₽", "174,75 $", "−4\(thin)210,50 ₽", "12,5", "0 ₾", "5\(thin)000 ¥"] {
            #expect(AmountParts(parsing: text).text == text)
        }
    }

    @Test func fromMinorUnitsHiddenShowsWholeUnitsOnly() {
        let parts = AmountParts(minor: 184_950, currency: "RUB", fraction: .hidden)
        #expect(parts.whole == "1\(thin)849")
        #expect(parts.fraction == "")
        #expect(parts.symbol == "₽")
    }

    @Test func fromMinorUnitsAutomaticDropsAZeroFractionOnly() {
        #expect(AmountParts(minor: 184_900, currency: "RUB", fraction: .automatic).fraction == "")
        #expect(AmountParts(minor: 184_950, currency: "RUB", fraction: .automatic).fraction == ",50")
    }

    @Test func fromMinorUnitsAlwaysShowsTheFraction() {
        let parts = AmountParts(minor: 184_900, currency: "RUB", fraction: .always)
        #expect(parts.fraction == ",00")
        #expect(AmountParts(minor: 17_475, currency: "USD", fraction: .always).text == "174,75 $")
    }

    @Test func aCurrencyWithoutDecimalsHasNoFraction() {
        #expect(AmountParts(minor: 5_000, currency: "VND", fraction: .always).fraction == "")
        #expect(AmountParts(minor: 5_000, currency: "VND", fraction: .always).whole == "5\(thin)000")
    }

    @Test func aNegativeAmountFromMinorUnitsCarriesTheMinus() {
        let parts = AmountParts(minor: -32_000, currency: "RUB", fraction: .hidden)
        #expect(parts.whole == "−320")
    }
}

/// `BigNumber` fills the width it is offered up to its maximum size, in one line.
@Suite @MainActor struct BigNumberSizingTests {
    private func size(of view: some View, width: CGFloat, dynamicType: DynamicTypeSize = .large) -> CGSize {
        let host = UIHostingController(rootView: view.dynamicTypeSize(dynamicType))
        return host.sizeThatFits(in: CGSize(width: width, height: 10_000))
    }

    private func height(minor: Int64, currency: String = "RUB", width: CGFloat, dynamicType: DynamicTypeSize = .large) -> CGFloat {
        size(of: BigNumber(minor: minor, currency: currency), width: width, dynamicType: dynamicType).height
    }

    @Test func aShortNumberKeepsTheMaximumSizeAndOneLine() {
        let short = height(minor: 800, width: 320)
        let longer = height(minor: 184_900, width: 320)
        #expect(short > 40)
        #expect(short == longer, "both fit at the maximum size, so both are as tall as one line at that size")
    }

    @Test func aLongNumberShrinksToTheWidthInsteadOfWrapping() {
        let fits = height(minor: 184_900, width: 320)
        let long = height(minor: 123_456_789_000, width: 320)
        #expect(long < fits)
        // One line: well under two lines of the smaller text.
        #expect(long < 1.6 * 88 * BigNumber.minimumScale * 1.3)
    }

    @Test func theResultNeverExceedsTheWidthItWasOffered() {
        for width in [200.0, 280, 320, 400] {
            let measured = size(of: BigNumber(minor: 123_456_789_000, currency: "RUB"), width: width)
            #expect(measured.width <= width + 0.5, "width \(width)")
        }
    }

    @Test func theMaximumSizeFollowsDynamicType() {
        let normal = height(minor: 800, width: 400, dynamicType: .large)
        let huge = height(minor: 800, width: 400, dynamicType: .accessibility3)
        #expect(huge > normal)
    }
}
