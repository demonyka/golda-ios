import SwiftUI

// MARK: - Geometry

/// Everything about the wavy bar that is arithmetic rather than drawing, kept apart so tests can
/// check it: what is drawn flat, where the indicator ends, how tall the wave is.
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

// MARK: - Settling

/// The 0...1 factor that scales the wave: 1 while it ripples, 0 when it is flat. Reaching a goal
/// is the wave calming down, slowly on purpose, so the change is a timed ease rather than a jump.
/// Times are plain seconds, so a test can drive it without a clock.
struct WaveEnvelope: Equatable, Sendable {
    static let settleDuration: TimeInterval = 0.9

    private var from: Double
    private var target: Double
    private var start: TimeInterval = 0

    init(flat: Bool) {
        from = flat ? 0 : 1
        target = from
    }

    var isFlatTarget: Bool { target == 0 }

    /// The factor at `time`: an ease-in-out between where the last change started and its target.
    func value(at time: TimeInterval) -> Double {
        let t = min(1, max(0, (time - start) / Self.settleDuration))
        let eased = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
        return from + (target - from) * eased
    }

    func isSettled(at time: TimeInterval) -> Bool {
        time - start >= Self.settleDuration || from == target
    }

    /// Aims at a new state. It starts from wherever the wave is now, so changing your mind
    /// mid-settle does not jump.
    mutating func retarget(flat: Bool, at time: TimeInterval) {
        let newTarget: Double = flat ? 0 : 1
        guard newTarget != target else { return }
        from = value(at: time)
        target = newTarget
        start = time
    }
}

// MARK: - View

/// The one progress mark: a wavy line, 8 pt in a hero and 4 pt in a row, in the ink of what it sits
/// on over a track of the same ink at 0.24. Full is also the overflow: the bar fills and the wave
/// settles flat over 0.9 s. With Reduce Motion it is flat from the start.
struct WavyBar: View {
    var progress: Double
    var size: WavyBarGeometry.Size = .row
    /// Defaults to the foreground style of whatever the bar sits on, so a hero on red stays legible.
    var ink: Color?
    /// Flat while the bar is full. Pass `true` to flatten it earlier (an overflow shown as a full bar).
    var flat: Bool?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var envelope: WaveEnvelope
    @State private var settling = false

    init(progress: Double, hero: Bool = false, ink: Color? = nil, flat: Bool? = nil) {
        self.progress = progress
        self.size = hero ? .hero : .row
        self.ink = ink
        self.flat = flat
        _envelope = State(initialValue: WaveEnvelope(flat: Self.isFlat(progress: progress, flat: flat)))
    }

    private static func isFlat(progress: Double, flat: Bool?) -> Bool {
        flat ?? (WavyBarGeometry.clamped(progress) >= 1)
    }

    private var isFlat: Bool { Self.isFlat(progress: progress, flat: flat) }

    var body: some View {
        Group {
            if reduceMotion {
                canvas(time: 0, forceFlat: true)
            } else {
                // Nothing to redraw once the wave has settled flat: pause the timeline then.
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: isFlat && !settling)) { context in
                    canvas(time: context.date.timeIntervalSinceReferenceDate, forceFlat: false)
                }
            }
        }
        .frame(height: size.height)
        .frame(maxWidth: .infinity)
        .onChange(of: isFlat) { _, nowFlat in
            let now = Date.now.timeIntervalSinceReferenceDate
            envelope.retarget(flat: nowFlat, at: now)
            settling = true
        }
        .task(id: isFlat) {
            // A little past the envelope, so the last frame is drawn before the timeline pauses. A
            // change of mind cancels this sleep and the new task takes over, so cancellation must not
            // clear the flag.
            do { try await Task.sleep(for: .seconds(WaveEnvelope.settleDuration + 0.1)) } catch { return }
            settling = false
        }
        .accessibilityElement(children: .ignore)
        .accessibilityValue(Text(verbatim: WavyBarGeometry.percentText(progress)))
    }

    private func canvas(time: TimeInterval, forceFlat: Bool) -> some View {
        Canvas { context, canvasSize in
            let geometry = WavyBarGeometry(size: size, progress: progress, width: canvasSize.width)
            let factor = forceFlat ? 0 : envelope.value(at: time)
            // The wave drifts along the bar, one wavelength every 1.6 s.
            let phase = forceFlat ? 0 : (time / 1.6).truncatingRemainder(dividingBy: 1)
            let style = StrokeStyle(lineWidth: size.thickness, lineCap: .round, lineJoin: .round)
            let shading: GraphicsContext.Shading = ink.map { .color($0) } ?? .foreground

            if let track = geometry.trackRange {
                context.drawLayer { layer in
                    layer.opacity = WavyBarGeometry.trackOpacity
                    var line = Path()
                    line.move(to: CGPoint(x: track.lowerBound, y: size.height / 2))
                    line.addLine(to: CGPoint(x: track.upperBound, y: size.height / 2))
                    layer.stroke(line, with: shading, style: style)
                }
                // The stop mark: a dot in the end of the track, the way the Android bar ends.
                let dot = size.thickness / 2.6
                let centre = CGPoint(x: track.upperBound, y: size.height / 2)
                context.fill(
                    Path(ellipseIn: CGRect(x: centre.x - dot / 2, y: centre.y - dot / 2, width: dot, height: dot)),
                    with: shading
                )
            }

            let points = geometry.indicatorPoints(envelope: factor, phase: phase)
            if let first = points.first {
                var path = Path()
                path.move(to: first)
                for point in points.dropFirst() { path.addLine(to: point) }
                context.stroke(path, with: shading, style: style)
            }
        }
    }
}

// MARK: - Previews

#Preview("Light") {
    WavyBarGallery()
        .padding(Theme.Gap.m)
        .background(Theme.Color.page)
}

#Preview("Dark") {
    WavyBarGallery()
        .padding(Theme.Gap.m)
        .background(Theme.Color.page)
        .preferredColorScheme(.dark)
}

#Preview("Dynamic Type XXXL and Reduce Motion off") {
    WavyBarGallery()
        .padding(Theme.Gap.m)
        .background(Theme.Color.page)
        .dynamicTypeSize(.accessibility3)
}

/// The bars in the states that matter: empty, started, half, nearly full, full, in a hero and in a row.
struct WavyBarGallery: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Gap.l) {
            Card {
                VStack(alignment: .leading, spacing: Theme.Gap.s) {
                    Text(verbatim: "Hero · 65 %").font(.footnote).foregroundStyle(.secondary)
                    WavyBar(progress: 0.65, hero: true)
                    Text(verbatim: "Hero · full, flat").font(.footnote).foregroundStyle(.secondary)
                    WavyBar(progress: 1, hero: true)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: Theme.Gap.s) {
                    ForEach([0.0, 0.01, 0.3, 0.62, 0.97, 1.0], id: \.self) { value in
                        HStack(spacing: Theme.Gap.m) {
                            WavyBar(progress: value)
                            Text(verbatim: WavyBarGeometry.percentText(value))
                                .font(.footnote).tabularDigits().foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
            }
            HeroCard(tone: .error) {
                VStack(alignment: .leading, spacing: Theme.Gap.s) {
                    Text(verbatim: "Overspent").font(.footnote)
                    WavyBar(progress: 1, hero: true, flat: false)
                }
            }
        }
    }
}
