import SwiftUI
import UIKit

/// A transparent layer over a chart that reports where a finger taps and where it slides sideways.
/// A slide that goes up or down does not begin here, so the list under the chart keeps scrolling
/// when a swipe starts on it. SwiftUI's own drag cannot be told to give up a vertical swipe, and
/// `chartXSelection` inside a list waits for a long press.
struct HorizontalTouchLayer: UIViewRepresentable {
    /// Called with the finger's position in the layer's own coordinates.
    var onTouch: (CGPoint) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        // The chart under it speaks for itself to VoiceOver.
        view.isAccessibilityElement = false
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.onTouch = onTouch
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTouch: onTouch)
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTouch: (CGPoint) -> Void

        init(onTouch: @escaping (CGPoint) -> Void) {
            self.onTouch = onTouch
        }

        @objc func tap(_ recognizer: UITapGestureRecognizer) {
            onTouch(recognizer.location(in: recognizer.view))
        }

        @objc func pan(_ recognizer: UIPanGestureRecognizer) {
            if recognizer.state == .began || recognizer.state == .changed {
                onTouch(recognizer.location(in: recognizer.view))
            }
        }

        /// Only a slide that is more sideways than up or down is a scrub.
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            let move = pan.translation(in: pan.view)
            return abs(move.x) > abs(move.y)
        }

        /// Beside the list's own scrolling, not instead of it.
        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
