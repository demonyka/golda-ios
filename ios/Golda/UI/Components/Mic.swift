import SwiftUI

// MARK: - State and level

/// What the microphone is doing. The views below are drawn from this and the level alone: they
/// record nothing and know nothing of the recorder, which arrives at stage 3.
enum MicState: Equatable, Sendable {
    case idle
    case recording
    case thinking

    /// What VoiceOver says: the button shows only pictures. Recording also says how to end it.
    var accessibilityLabel: LocalizedStringResource {
        switch self {
        case .idle: LocalizedStringResource("Say it", table: "Components")
        case .recording: LocalizedStringResource("Listening. Tap when done", table: "Components")
        case .thinking: LocalizedStringResource("Working it out…", table: "Components")
        }
    }

    var accessibilityHint: LocalizedStringResource? {
        self == .idle ? LocalizedStringResource("Starts recording a note", table: "Components") : nil
    }
}

/// How the loudness the microphone hears becomes the height of the waveform bars. Plain arithmetic,
/// so a test can check it.
enum MicLevel {
    /// Speech peaks sit well under full scale; the square root lifts quiet talk into view (the
    /// Android cookie does the same). 0 stays 0, a third of full scale already shows as full.
    static func lifted(_ raw: Double) -> Double {
        raw.isNaN ? 0 : sqrt(min(1, max(0, raw * 3)))
    }

    /// Never fully flat, so a silent mic still reads as "listening".
    static let restingHeight = 0.2

    /// The height of each of `count` bars as a share of the full height, for a raw `level` 0...1.
    /// The middle bars are taller, and `phase` (in turns) makes the bars take turns, so the
    /// waveform keeps moving while someone speaks steadily.
    static func barHeights(level: Double, count: Int, phase: Double) -> [Double] {
        guard count > 0 else { return [] }
        let energy = lifted(level)
        return (0..<count).map { index in
            let position = (Double(index) + 0.5) / Double(count)
            let weight = 0.55 + 0.45 * sin(.pi * position)
            let turn = 0.5 + 0.5 * sin(2 * .pi * (phase + Double(index) * 0.37))
            let variation = 1 - 0.35 * turn
            return min(1, restingHeight + (1 - restingHeight) * energy * weight * variation)
        }
    }
}

// MARK: - Waveform

/// Bars that follow the voice. `level` is the raw loudness, 0...1; the bars lift and smooth it.
struct LevelWaveform: View {
    var level: Double
    var ink: Color
    var barCount = 5
    var maxHeight: CGFloat = 24
    var barWidth: CGFloat = 3

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // The bars take turns only when motion is allowed; with Reduce Motion they still follow the level.
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion)) { context in
            let phase = reduceMotion ? 0 : (context.date.timeIntervalSinceReferenceDate / 1.3).truncatingRemainder(dividingBy: 1)
            let heights = MicLevel.barHeights(level: level, count: barCount, phase: phase)
            HStack(spacing: barWidth) {
                ForEach(heights.indices, id: \.self) { index in
                    Capsule()
                        .fill(ink)
                        .frame(width: barWidth, height: max(barWidth, heights[index] * maxHeight))
                }
            }
            .frame(height: maxHeight)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: level)
        }
        // Decorative: the label of the mic already says it is listening.
        .accessibilityHidden(true)
    }
}

// MARK: - Round floating mic

/// The mic: a 64 pt gold button that floats over the content. On iOS 26 it is Liquid Glass tinted
/// gold; with Reduce Transparency it is a plain gold disc. Recording shows the waveform above a stop
/// square, thinking a spinner. Gold is the one main-action colour and appears only here.
struct MicFloatingButton: View {
    var state: MicState
    /// Raw loudness, 0...1, while recording.
    var level: Double = 0
    var action: () -> Void

    static let diameter: CGFloat = 64

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Button(action: action) {
            face
                .frame(width: Self.diameter, height: Self.diameter)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .background {
            // Under the button rather than in its label: the spinner is UIKit underneath and, in
            // the label, it would take the tap that ends "thinking".
            if state == .thinking {
                ProgressView()
                    .tint(Theme.Color.onGold)
                    .allowsHitTesting(false)
            }
        }
        .modifier(GoldDisc(reduceTransparency: reduceTransparency))
        .accessibilityLabel(Text(state.accessibilityLabel))
        .accessibilityHint(state.accessibilityHint.map { Text($0) } ?? Text(verbatim: ""))
        .animation(.snappy, value: state)
    }

    @ViewBuilder private var face: some View {
        switch state {
        case .idle:
            Image(systemName: Symbols.mic)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.Color.onGold)
                .contentTransition(.symbolEffect(.replace))
        case .recording:
            VStack(spacing: 6) {
                LevelWaveform(level: level, ink: Theme.Color.onGold, maxHeight: 20)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Theme.Color.onGold)
                    .frame(width: 13, height: 13)
            }
        case .thinking:
            // The spinner is drawn under the button, see `body`.
            Color.clear
        }
    }
}

/// Gold glass on iOS 26, a plain gold disc when transparency is reduced.
private struct GoldDisc: ViewModifier {
    var reduceTransparency: Bool

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Theme.Color.gold, in: .circle)
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        } else {
            content
                .glassEffect(.regular.tint(Theme.Color.gold).interactive(), in: .circle)
        }
    }
}

// MARK: - Previews

private struct MicGallery: View {
    var body: some View {
        VStack(spacing: Theme.Gap.l) {
            ForEach([MicState.idle, .recording, .thinking], id: \.self) { state in
                MicFloatingButton(state: state, level: 0.12) {}
            }
        }
        .padding(Theme.Gap.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.page)
    }
}

#Preview("Light") { MicGallery() }
#Preview("Dark") { MicGallery().preferredColorScheme(.dark) }
