import SwiftUI

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
