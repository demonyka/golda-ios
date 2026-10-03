import CoreGraphics
import Testing

@testable import Golda

@Suite struct WavyBarGeometryTests {
    private func geometry(_ progress: Double, _ size: WavyBarGeometry.Size = .row, width: CGFloat = 300) -> WavyBarGeometry {
        WavyBarGeometry(size: size, progress: progress, width: width)
    }

    // MARK: Progress

    @Test func progressIsClampedToTheUnitInterval() {
        #expect(geometry(-0.5).progress == 0)
        #expect(geometry(1.7).progress == 1)
        #expect(geometry(0.4).progress == 0.4)
    }

    @Test func notANumberCountsAsNothingDone() {
        // A goal of 0 divided by 0 must not poison the layout.
        #expect(geometry(.nan).progress == 0)
        #expect(geometry(.nan).indicatorRange == nil)
        #expect(WavyBarGeometry.clamped(.infinity) == 1)
        #expect(WavyBarGeometry.clamped(-.infinity) == 0)
    }

    @Test func percentIsWholeAndNeverZeroForARealStart() {
        #expect(WavyBarGeometry.percentText(0) == "0 %")
        #expect(WavyBarGeometry.percentText(0.001) == "<1 %")
        #expect(WavyBarGeometry.percentText(0.005) == "1 %")
        #expect(WavyBarGeometry.percentText(0.624) == "62 %")
        #expect(WavyBarGeometry.percentText(0.625) == "63 %")
        #expect(WavyBarGeometry.percentText(1) == "100 %")
        #expect(WavyBarGeometry.percentText(3) == "100 %")
        #expect(WavyBarGeometry.percentText(-1) == "0 %")
    }

    // MARK: Sizes

    @Test func aHeroBarIsEightPointsAndARowBarIsFour() {
        #expect(WavyBarGeometry.Size.hero.thickness == 8)
        #expect(WavyBarGeometry.Size.row.thickness == 4)
        #expect(WavyBarGeometry.trackOpacity == 0.24)
    }

    @Test func theBarKeepsItsHeightWhateverTheProgress() {
        for size in [WavyBarGeometry.Size.hero, .row] {
            // The wave stays inside the bar's own height, with room for the stroke.
            #expect(size.height >= size.thickness + 2 * size.maxAmplitude)
        }
    }

    // MARK: Flat and wavy

    private func spread(_ points: [CGPoint]) -> CGFloat {
        guard let low = points.map(\.y).min(), let high = points.map(\.y).max() else { return 0 }
        return high - low
    }

    @Test func aWavyIndicatorRipples() {
        let points = geometry(0.6, .hero).indicatorPoints(envelope: 1, phase: 0)
        #expect(points.count > 10)
        #expect(spread(points) > 1, "peak to peak is a visible fraction of the amplitude")
        #expect(spread(points) <= 2 * WavyBarGeometry.Size.hero.maxAmplitude + 0.001)
    }

    @Test func aSettledIndicatorIsAStraightLine() {
        let points = geometry(0.6, .hero).indicatorPoints(envelope: 0, phase: 0.3)
        #expect(points.count == 2)
        #expect(spread(points) == 0)
        #expect(points.first?.y == WavyBarGeometry.Size.hero.height / 2)
    }

    @Test func aFullBarIsWavyUntilToldToSettle() {
        // Full alone does not flatten the geometry: the envelope does, over 0.9 s.
        #expect(spread(geometry(1).indicatorPoints(envelope: 1, phase: 0)) > 0.5)
        #expect(spread(geometry(1).indicatorPoints(envelope: 0, phase: 0)) == 0)
    }

    @Test func theWaveGrowsWithProgress() {
        var last = -1.0
        for progress in stride(from: 0.0, through: 1.0, by: 0.1) {
            let scale = geometry(progress).amplitudeScale
            #expect(scale >= last)
            #expect(scale <= 1)
            last = scale
        }
        #expect(geometry(0.1).amplitude(envelope: 1) < geometry(0.9).amplitude(envelope: 1))
    }

    @Test func theEnvelopeScalesTheAmplitudeAndIsPinned() {
        let g = geometry(0.5, .hero)
        #expect(g.amplitude(envelope: 0) == 0)
        #expect(g.amplitude(envelope: 2) == g.amplitude(envelope: 1))
        #expect(g.amplitude(envelope: -1) == 0)
        #expect(abs(g.amplitude(envelope: 0.5) * 2 - g.amplitude(envelope: 1)) < 0.0001)
    }

    @Test func thePhaseSlidesTheWaveAlong() {
        let a = geometry(0.6).indicatorPoints(envelope: 1, phase: 0)
        let b = geometry(0.6).indicatorPoints(envelope: 1, phase: 0.25)
        #expect(a.map(\.y) != b.map(\.y))
        #expect(a.map(\.x) == b.map(\.x))
        // A full turn is the same wave again.
        let c = geometry(0.6).indicatorPoints(envelope: 1, phase: 1)
        for (p, q) in zip(a, c) { #expect(abs(p.y - q.y) < 0.0001) }
    }

    // MARK: Indicator and track

    @Test func emptyHasATrackAndNoIndicator() {
        let g = geometry(0)
        #expect(g.indicatorRange == nil)
        #expect(g.indicatorPoints(envelope: 1, phase: 0).isEmpty)
        let track = g.trackRange
        #expect(track != nil)
        #expect(track?.lowerBound == 2)
        #expect(track?.upperBound == 298)
    }

    @Test func aBarThatHasJustStartedIsADotNotNothing() {
        // One point alone would stroke to nothing; two equal points stroke to a round dot.
        for envelope in [0.0, 1.0] {
            let points = geometry(0.01).indicatorPoints(envelope: envelope, phase: 0)
            #expect(points.count >= 2)
            #expect(points.first == points.last)
        }
    }

    @Test func fullHasAnIndicatorAcrossAndNoTrack() {
        let g = geometry(1)
        #expect(g.trackRange == nil)
        #expect(g.indicatorRange == 2...298)
    }

    @Test func indicatorAndTrackNeverOverlapAndKeepTheGap() throws {
        for progress in [0.05, 0.25, 0.5, 0.75, 0.95] {
            let g = geometry(progress, .hero)
            let indicator = try #require(g.indicatorRange)
            let track = try #require(g.trackRange)
            let thickness = WavyBarGeometry.Size.hero.thickness
            // Between the two round caps there is at least the gap.
            let space = (track.lowerBound - thickness / 2) - (indicator.upperBound + thickness / 2)
            #expect(space >= WavyBarGeometry.Size.hero.gap - 0.001, "progress \(progress)")
            #expect(track.upperBound <= 300 - thickness / 2)
        }
    }

    @Test func theIndicatorEndsNearTheProgressPoint() throws {
        let g = geometry(0.5, .row, width: 400)
        let indicator = try #require(g.indicatorRange)
        let end = indicator.upperBound + 2 // plus the round cap
        #expect(abs(end - 200) <= WavyBarGeometry.Size.row.gap)
    }

    @Test func aTooNarrowBarDrawsNothingAndDoesNotCrash() {
        let g = geometry(0.5, .hero, width: 3)
        #expect(g.indicatorRange == nil)
        #expect(g.trackRange == nil)
        #expect(g.indicatorPoints(envelope: 1, phase: 0).isEmpty)
        #expect(geometry(0.5, .row, width: 0).indicatorRange == nil)
    }
}

@Suite struct WaveEnvelopeTests {
    @Test func aBarThatIsNotFullRipplesFromTheStart() {
        let envelope = WaveEnvelope(flat: false)
        #expect(envelope.value(at: 0) == 1)
        #expect(envelope.value(at: 100) == 1)
        #expect(envelope.isSettled(at: 0))
    }

    @Test func aBarThatIsFullFromTheStartIsFlatAtOnce() {
        let envelope = WaveEnvelope(flat: true)
        #expect(envelope.value(at: 0) == 0)
        #expect(envelope.isFlatTarget)
        #expect(envelope.isSettled(at: 0))
    }

    @Test func theWaveSettlesOverNinetyHundredthsOfASecond() {
        #expect(WaveEnvelope.settleDuration == 0.9)
        var envelope = WaveEnvelope(flat: false)
        envelope.retarget(flat: true, at: 10)
        #expect(envelope.value(at: 10) == 1)
        #expect(!envelope.isSettled(at: 10.5))
        // Ease in-out: halfway through the time it is halfway down.
        #expect(abs(envelope.value(at: 10.45) - 0.5) < 0.0001)
        #expect(envelope.value(at: 10.9) == 0)
        #expect(envelope.isSettled(at: 10.9))
        #expect(envelope.value(at: 12) == 0)
    }

    @Test func theSettleIsMonotonic() {
        var envelope = WaveEnvelope(flat: false)
        envelope.retarget(flat: true, at: 0)
        var last = 2.0
        for step in 0...20 {
            let value = envelope.value(at: Double(step) * 0.05)
            #expect(value <= last)
            last = value
        }
    }

    @Test func changingYourMindMidSettleDoesNotJump() {
        var envelope = WaveEnvelope(flat: false)
        envelope.retarget(flat: true, at: 0)
        let before = envelope.value(at: 0.3)
        envelope.retarget(flat: false, at: 0.3)
        #expect(abs(envelope.value(at: 0.3) - before) < 0.0001)
        #expect(envelope.value(at: 5) == 1)
    }

    @Test func retargetingToTheSameStateChangesNothing() {
        var envelope = WaveEnvelope(flat: false)
        let copy = envelope
        envelope.retarget(flat: false, at: 3)
        #expect(envelope == copy)
    }
}
