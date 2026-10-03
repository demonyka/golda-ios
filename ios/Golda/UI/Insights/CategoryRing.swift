import Charts
import SwiftUI

/// The tones of the ring's slices by rank: quiet greys, never black, the last one for "everything
/// else" (DESIGN.md: the ring stays quiet, as on Android). Built from the tokens so both themes work.
enum RingTone {
    static func color(slice: Int, isRest: Bool) -> Color {
        if isRest { return Theme.Color.soft }
        switch slice {
        case 0: return Theme.Color.muted
        case 1: return Theme.Color.muted.opacity(0.6)
        default: return Theme.Color.line
        }
    }
}

/// The period's spending as a ring of slices with round ends and gaps between them, starting at
/// twelve o'clock, and the total (or the picked slice) in the middle. A tap on the ring picks a
/// slice and fades the others; a tap on the middle, or on the same slice again, puts it back.
struct CategoryRing: View {
    let content: InsightsContent
    @Binding var picked: Int?

    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The ring takes this share of the width it is given, about as much as on Android.
    private static let share: CGFloat = 0.72

    var body: some View {
        let focus = content.focus(picked)
        let center = content.center(focus: focus)
        Chart(content.slices) { slice in
            SectorMark(
                angle: .value("Spent", Double(slice.rubMinor)),
                innerRadius: .ratio(0.8),
                angularInset: 3
            )
            .cornerRadius(6)
            // What is picked is graphite (D34); the others step back.
            .foregroundStyle(focus == slice.id ? Theme.Color.graphite : RingTone.color(slice: slice.id, isRest: slice.isRest))
            .opacity(focus == nil || focus == slice.id ? 1 : 0.35)
        }
        .chartLegend(.hidden)
        .animation(reduceMotion ? nil : .snappy, value: focus)
        .animation(reduceMotion ? nil : .snappy, value: content.slices)
        .overlay {
            GeometryReader { geometry in
                centerView(center)
                    .frame(width: geometry.size.width * 0.56)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        // Not `chartAngleSelection`: inside a list it waits for a long press, and a slice should
        // answer to a plain tap, as on Android. The tap is read by its angle, where the first slice
        // starts at twelve o'clock; the middle and the space round the ring put the whole back.
        .overlay {
            GeometryReader { geometry in
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture { point in
                        tap(at: point, in: geometry.size)
                    }
            }
        }
        // Square first, then the width: the other way round the square takes the whole row.
        .aspectRatio(1, contentMode: .fit)
        .containerRelativeFrame(.horizontal) { width, _ in min(width * Self.share, 360) }
        .frame(maxWidth: .infinity)
        // The rows say it all and in words; the ring is a picture of them, so it reads as its middle.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: content.centerAccessibilityLabel(center, in: locale)))
        .accessibilityIdentifier("insights.ring")
    }

    private func centerView(_ center: InsightsCenter) -> some View {
        VStack(spacing: Theme.Gap.xs) {
            if let title = center.title {
                Text(verbatim: title.text(in: locale))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.Color.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            BigNumber(AmountParts(parsing: center.amount), value: center.value, color: Theme.Color.text, maxSize: 56, alignment: .center)
                .accessibilityIdentifier("insights.total")
            Text(verbatim: content.centerCaption(center, in: locale))
                .font(.subheadline)
                .tabularDigits()
                .foregroundStyle(Theme.Color.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The ring's band, as shares of the chart's side: the chart keeps a margin round it, and the
    /// hole is 0.8 of the outer radius.
    private static let band: ClosedRange<CGFloat> = 0.32...0.5

    private func tap(at point: CGPoint, in size: CGSize) {
        let dx = point.x - size.width / 2, dy = point.y - size.height / 2
        guard Self.band.contains(hypot(dx, dy) / size.width) else {
            picked = nil
            return
        }
        // Clockwise from twelve o'clock, as a share of the full turn.
        var turn = atan2(dx, -dy) / (2 * .pi)
        if turn < 0 { turn += 1 }
        let total = content.slices.reduce(0) { $0 + Double($1.rubMinor) }
        if let slice = content.slice(atAngle: Double(turn) * total) { toggle(slice) }
    }

    private func toggle(_ slice: Int) {
        picked = picked == slice ? nil : slice
    }
}
