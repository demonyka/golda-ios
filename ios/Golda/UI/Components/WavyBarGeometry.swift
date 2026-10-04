import Foundation

/// Everything about the wavy bar that is arithmetic rather than drawing, kept apart so tests can
/// check it: what is drawn flat, where the indicator ends, how tall the wave is. A file of its
/// own, compiled into the widgets too, which draw the bar still.
struct WavyBarGeometry: Equatable, Sendable {
    /// 8 pt in a hero, 4 pt in a row.
    enum Size: Sendable {
        case hero, row

        var thickness: CGFloat { self == .hero ? 8 : 4 }
        /// Peak height of the wave when the bar is nowhere near full.
        var maxAmplitude: CGFloat { self == .hero ? 3 : 2 }
        var wavelength: CGFloat { self == .hero ? 36 : 20 }
        /// Fixed whatever the progress, so a bar that settles flat does not change the layout around it.
        var height: CGFloat { self == .hero ? 20 : 12 }
        /// Air between the end of the indicator and the start of the track.
        var gap: CGFloat { thickness * 0.75 }
    }

    /// The track is the ink at this opacity (the same on Android).
    static let trackOpacity = 0.24

    let size: Size
    /// 0...1 whatever was asked for.
    let progress: Double
    let width: CGFloat

    init(size: Size, progress: Double, width: CGFloat) {
        self.size = size
        self.progress = Self.clamped(progress)
        self.width = max(0, width)
    }

    /// Progress outside 0...1 is pinned to it; NaN (a goal of 0 divided by 0) counts as nothing done.
    static func clamped(_ progress: Double) -> Double {
        progress.isNaN ? 0 : min(1, max(0, progress))
    }

    var isFull: Bool { progress >= 1 }

    /// How much of the largest wave is drawn at this progress, before the settle envelope. It grows
    /// with progress: a bar that has hardly started ripples gently, a nearly full one is at full height.
    var amplitudeScale: Double { 0.25 + 0.75 * progress }

    /// Peak height of the wave in points, `envelope` being the 0...1 factor of `WaveEnvelope`.
    func amplitude(envelope: Double) -> CGFloat {
        size.maxAmplitude * amplitudeScale * min(1, max(0, envelope))
    }

    private var cap: CGFloat { size.thickness / 2 }

    /// Where the indicator's centre line starts and ends. A bar at 0 has no indicator.
    var indicatorRange: ClosedRange<CGFloat>? {
        guard progress > 0, width > 2 * cap else { return nil }
        let start = cap
        // Not full: stop short by half the gap, so the gap is shared by both ends.
        let end = isFull ? width - cap : max(start, progress * width - size.gap / 2 - cap)
        return start...min(end, width - cap)
    }

    /// Where the track's centre line starts and ends. None when the bar is full or the indicator
    /// has swallowed what is left.
    var trackRange: ClosedRange<CGFloat>? {
        guard !isFull, width > 2 * cap else { return nil }
        let start: CGFloat
        if let indicator = indicatorRange {
            start = indicator.upperBound + cap + size.gap + cap
        } else {
            start = cap
        }
        let end = width - cap
        return start < end ? start...end : nil
    }

    /// The indicator as a polyline: the sine of the wave, shifted by `phase` (in wavelengths).
    /// Flat (zero amplitude) gives a straight line through the middle of the bar.
    func indicatorPoints(envelope: Double, phase: Double) -> [CGPoint] {
        guard let range = indicatorRange else { return [] }
        let amplitude = self.amplitude(envelope: envelope)
        let midY = size.height / 2
        if amplitude < 0.01 {
            return [CGPoint(x: range.lowerBound, y: midY), CGPoint(x: range.upperBound, y: midY)]
        }
        var points: [CGPoint] = []
        let step: CGFloat = 1.5
        var x = range.lowerBound
        while x < range.upperBound {
            points.append(CGPoint(x: x, y: y(at: x, midY: midY, amplitude: amplitude, phase: phase)))
            x += step
        }
        points.append(CGPoint(x: range.upperBound, y: y(at: range.upperBound, midY: midY, amplitude: amplitude, phase: phase)))
        // A bar that has only just started is a single point; stroked with round caps, a line of
        // zero length is a dot, while a lone move-to draws nothing.
        if points.count == 1 { points.append(points[0]) }
        return points
    }

    private func y(at x: CGFloat, midY: CGFloat, amplitude: CGFloat, phase: Double) -> CGFloat {
        let turns = Double(x / size.wavelength) - phase
        return midY + amplitude * CGFloat(sin(2 * .pi * turns))
    }

    /// "62 %", or "<1 %" for a bar that has started but not reached a whole percent. The caption
    /// under a bar says this; the percent never goes inside it.
    static func percentText(_ progress: Double) -> String {
        let value = clamped(progress)
        if value > 0, value < 0.005 { return "<1 %" }
        return "\(Int((value * 100).rounded(.toNearestOrAwayFromZero))) %"
    }
}
