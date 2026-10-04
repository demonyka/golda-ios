import SwiftUI
import UIKit

/// A tap on anything but text puts the keyboard away, in every screen and sheet; SwiftUI itself only
/// puts it away on a drag (`scrollDismissesKeyboard`). One tap recognizer on the window
/// (`KeyboardDismissingTap`) sees every tap beside the views' own gestures, so a button or a switch
/// still does its job. A tap on a control ends the typing too: a tap outside the field says the
/// person is done with it, and a control that left the keyboard up would keep half the screen
/// covered with nothing to type.
@MainActor
enum KeyboardTaps {
    /// Whether a tap on [view] at [point], in the view's own coordinates, leaves the keyboard up. In a
    /// text field or a text view it moves the caret or the focus there, which UIKit does without the
    /// keyboard going down and up again. In an alert it stays with the alert's own field. In a form's
    /// row that holds a field it is a tap on the field that missed: the row is the field's card, and
    /// the field inside is a line of text in it. Within one of [keepers] on the same screen
    /// (`keepsKeyboardOnTap`) the tap hands the keyboard to a field itself.
    static func keepsKeyboard(touching view: UIView, at point: CGPoint, keepers: some Sequence<UIView>) -> Bool {
        let chain = sequence(first: view as UIResponder) { $0.next }
        for responder in chain {
            switch responder {
            case is UITextField, is UITextView, is UIAlertController:
                return true
            case let row as UICollectionViewCell where row.contentView.holdsTextInput:
                return true
            case let row as UITableViewCell where row.contentView.holdsTextInput:
                return true
            default:
                continue
            }
        }
        let screen = view.screenController
        return keepers.contains { keeper in
            // A sheet over a keeper is another screen: its taps are its own, wherever they land.
            keeper.window === view.window && keeper.screenController === screen
                && keeper.bounds.contains(keeper.convert(point, from: view))
        }
    }
}

extension View {
    /// A tap here hands the keyboard to a field (the card around a field, a button that opens one):
    /// the window's tap leaves the keyboard up rather than put it away a moment before the field
    /// takes it. SwiftUI draws a button or a card without a view of its own, so the place is found by
    /// its frame (`KeyboardKeeper`).
    func keepsKeyboardOnTap() -> some View {
        background(KeyboardKeeper().allowsHitTesting(false).accessibilityHidden(true))
    }
}

/// The window's tap that ends editing. It holds no touch back and gives way to no gesture, so what
/// was tapped acts as it did before.
final class KeyboardDismissingTap: UITapGestureRecognizer, UIGestureRecognizerDelegate {
    init() {
        super.init(target: nil, action: nil)
        // A recognizer keeps its target unretained; this one is its own.
        addTarget(self, action: #selector(endEditing))
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    /// Puts one on [window]; a second call finds it there.
    static func install(on window: UIWindow) {
        guard !(window.gestureRecognizers ?? []).contains(where: { $0 is KeyboardDismissingTap }) else { return }
        window.addGestureRecognizer(KeyboardDismissingTap())
    }

    /// Puts away the keyboard of the field typed into when the tap ended, once the tap's own actions
    /// have run. Put away at once, the keyboard going down moved a sheet held up by it under the
    /// finger, and the tapped button did nothing. A field the tap gave the keyboard to meanwhile
    /// keeps it, and with no field typed into nothing happens, so a form a tap opens keeps its
    /// focused field. The SwiftUI fields hear their field resign and clear their focus; the big
    /// amount's flag follows its field (`GroupedAmountField`).
    @objc func endEditing() {
        guard let editing = UIResponder.first as? UIView & UITextInput, editing.window === view else { return }
        DispatchQueue.main.async {
            if editing.isFirstResponder { editing.resignFirstResponder() }
        }
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let touched = touch.view else { return false }
        return !KeyboardTaps.keepsKeyboard(
            touching: touched, at: touch.location(in: touched), keepers: KeyboardKeeper.Marker.onScreen.allObjects
        )
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

/// Puts `KeyboardDismissingTap` on the window the app's views are in, as soon as there is one.
struct KeyboardDismissingTapInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> Installer {
        let installer = Installer()
        installer.isUserInteractionEnabled = false
        return installer
    }

    func updateUIView(_ view: Installer, context: Context) {}

    final class Installer: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { KeyboardDismissingTap.install(on: window) }
        }
    }
}

/// The frame of a `keepsKeyboardOnTap` place, as an invisible view that takes no touches.
struct KeyboardKeeper: UIViewRepresentable {
    func makeUIView(context: Context) -> Marker {
        let marker = Marker()
        marker.isUserInteractionEnabled = false
        marker.isAccessibilityElement = false
        return marker
    }

    func updateUIView(_ marker: Marker, context: Context) {}

    final class Marker: UIView {
        /// The markers in a window now; the table forgets one that is gone.
        static let onScreen = NSHashTable<Marker>.weakObjects()

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { Self.onScreen.remove(self) } else { Self.onScreen.add(self) }
        }
    }
}

private extension UIResponder {
    private static weak var reported: UIResponder?

    /// The first responder now: an action sent to no one goes to it. UIKit has no other way to ask.
    static var first: UIResponder? {
        reported = nil
        UIApplication.shared.sendAction(#selector(goldaReportAsFirst), to: nil, from: nil, for: nil)
        return reported
    }

    // Prefixed: a method added to a UIKit class must not meet one of UIKit's own.
    @objc private func goldaReportAsFirst() {
        UIResponder.reported = self
    }
}

private extension UIView {
    /// The view controller whose screen this view is part of.
    var screenController: UIViewController? {
        sequence(first: self as UIResponder) { $0.next }.lazy.compactMap { $0 as? UIViewController }.first
    }

    /// A text field or a text view is among the subviews, however deep.
    var holdsTextInput: Bool {
        subviews.contains { $0 is UITextField || $0 is UITextView || $0.holdsTextInput }
    }
}
