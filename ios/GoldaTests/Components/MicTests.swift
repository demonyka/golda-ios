import Foundation
import Testing

@testable import Golda

@Suite struct MicLevelTests {
    @Test func silenceStaysSilentAndAThirdOfFullScaleShowsAsFull() {
        #expect(MicLevel.lifted(0) == 0)
        #expect(abs(MicLevel.lifted(1.0 / 3.0) - 1) < 0.0001)
        #expect(MicLevel.lifted(1) == 1)
    }

    @Test func quietTalkIsLiftedAboveItsRawLevel() {
        // The square root: a raw 0.02 shows as about 0.24, not as a barely visible 0.02.
        #expect(MicLevel.lifted(0.02) > 0.2)
        #expect(MicLevel.lifted(0.02) > 0.02 * 3)
    }

    @Test func theLiftIsMonotonicAndPinned() {
        var last = -1.0
        for step in 0...20 {
            let value = MicLevel.lifted(Double(step) / 20)
            #expect(value >= last)
            #expect((0...1).contains(value))
            last = value
        }
        #expect(MicLevel.lifted(-4) == 0)
        #expect(MicLevel.lifted(9) == 1)
        #expect(MicLevel.lifted(.nan) == 0)
    }

    @Test func aSilentMicStillShowsRestingBars() {
        let heights = MicLevel.barHeights(level: 0, count: 5, phase: 0.3)
        #expect(heights.count == 5)
        #expect(heights.allSatisfy { $0 == MicLevel.restingHeight })
    }

    @Test func louderMeansTallerBars() {
        let quiet = MicLevel.barHeights(level: 0.01, count: 5, phase: 0)
        let loud = MicLevel.barHeights(level: 0.2, count: 5, phase: 0)
        #expect(zip(quiet, loud).allSatisfy { $0 < $1 })
        #expect(loud.allSatisfy { $0 <= 1 })
    }

    @Test func theMiddleBarsAreTheTallest() {
        let heights = MicLevel.barHeights(level: 0.3, count: 5, phase: 0)
        #expect(heights[2] >= heights[0])
        #expect(heights[2] >= heights[4])
    }

    @Test func thePhaseMakesTheBarsTakeTurnsButNeverLeaveTheBounds() {
        let a = MicLevel.barHeights(level: 0.2, count: 5, phase: 0)
        let b = MicLevel.barHeights(level: 0.2, count: 5, phase: 0.5)
        #expect(a != b)
        for heights in [a, b] {
            #expect(heights.allSatisfy { $0 >= MicLevel.restingHeight && $0 <= 1 })
        }
    }

    @Test func noBarsForNoCount() {
        #expect(MicLevel.barHeights(level: 1, count: 0, phase: 0).isEmpty)
    }
}

@Suite struct MicStateTests {
    @Test func eachStateShowsItsOwnSymbolOrSpinner() {
        #expect(MicState.idle.symbol == Symbols.mic)
        #expect(MicState.recording.symbol == Symbols.stop)
    }

    @Test func onlyAnIdleMicHasAHint() {
        #expect(MicState.idle.accessibilityHint != nil)
        #expect(MicState.recording.accessibilityHint == nil)
        #expect(MicState.thinking.accessibilityHint == nil)
    }
}
