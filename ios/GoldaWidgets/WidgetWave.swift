import SwiftUI

/// Home's wavy bar, still: a widget is drawn once, so the wave stands where the app's would be at
/// rest, rippling while there is room left and flat once the share is spent or untouched. The
/// geometry is the app's (`WavyBarGeometry`); the ink is the primary one, red when overspent.
struct WidgetWave: View {
    let progress: Double
    let isOverspent: Bool
    let size: WavyBarGeometry.Size

    private var isFlat: Bool { isOverspent || WavyBarGeometry.clamped(progress) >= 1 }

    var body: some View {
        GeometryReader { proxy in
            let geometry = WavyBarGeometry(size: size, progress: isOverspent ? 1 : progress, width: proxy.size.width)
            let style = StrokeStyle(lineWidth: size.thickness, lineCap: .round, lineJoin: .round)
            ZStack {
                if let track = geometry.trackRange {
                    Line(from: CGPoint(x: track.lowerBound, y: size.height / 2), to: CGPoint(x: track.upperBound, y: size.height / 2))
                        .stroke(style: style)
                        .opacity(WavyBarGeometry.trackOpacity)
                    // The stop mark at the end of the track, as in the app.
                    let dot = size.thickness / 2.6
                    Circle()
                        .frame(width: dot, height: dot)
                        .position(x: track.upperBound, y: size.height / 2)
                }
                Polyline(points: geometry.indicatorPoints(envelope: isFlat ? 0 : 1, phase: 0))
                    .stroke(style: style)
            }
        }
        .foregroundStyle(isOverspent ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
        .frame(height: size.height)
        .privacySensitive()
        .accessibilityHidden(true)
    }

    private struct Line: Shape {
        let from: CGPoint
        let to: CGPoint

        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: from)
                path.addLine(to: to)
            }
        }
    }

    private struct Polyline: Shape {
        let points: [CGPoint]

        func path(in rect: CGRect) -> Path {
            Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                for point in points.dropFirst() { path.addLine(to: point) }
            }
        }
    }
}
