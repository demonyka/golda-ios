import Testing
import UIKit

@testable import Golda

/// Which taps leave the keyboard up: those in text, in an alert, or on a place that hands the
/// keyboard to a field; every other one puts it away (`KeyboardDismissingTap`).
@Suite @MainActor struct KeyboardTapsTests {
    private let point = CGPoint(x: 10, y: 10)

    @Test func aTapInATextFieldOrTextViewKeepsTheKeyboard() {
        let field = UITextField(frame: CGRect(x: 0, y: 0, width: 200, height: 44))
        let inner = UIView(frame: field.bounds)
        field.addSubview(inner)
        #expect(KeyboardTaps.keepsKeyboard(touching: field, at: point, keepers: []))
        // The caret and the text are views inside the field.
        #expect(KeyboardTaps.keepsKeyboard(touching: inner, at: point, keepers: []))
        #expect(KeyboardTaps.keepsKeyboard(touching: UITextView(), at: point, keepers: []))
        #expect(KeyboardTaps.keepsKeyboard(touching: UISearchTextField(), at: point, keepers: []))
    }

    @Test func aTapOnAnythingElsePutsItAway() {
        let page = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let button = UIButton(type: .system)
        let toggle = UISwitch()
        page.addSubview(button)
        page.addSubview(toggle)
        for view in [page, button, toggle] {
            #expect(!KeyboardTaps.keepsKeyboard(touching: view, at: point, keepers: []))
        }
        // A field beside the tapped view is not the tapped view.
        page.addSubview(UITextField(frame: page.bounds))
        #expect(!KeyboardTaps.keepsKeyboard(touching: page, at: point, keepers: []))
    }

    @Test func aTapInAFormRowWithAFieldMissedTheField() {
        let row = UICollectionViewListCell(frame: CGRect(x: 0, y: 0, width: 358, height: 52))
        let content = UIView(frame: row.contentView.bounds)
        row.contentView.addSubview(content)
        #expect(!KeyboardTaps.keepsKeyboard(touching: content, at: point, keepers: []), "a row of a switch or a menu")
        let field = UITextField(frame: CGRect(x: 16, y: 14, width: 326, height: 24))
        content.addSubview(field)
        #expect(KeyboardTaps.keepsKeyboard(touching: content, at: point, keepers: []))
        let tableRow = UITableViewCell(style: .default, reuseIdentifier: nil)
        tableRow.contentView.addSubview(UITextView())
        #expect(KeyboardTaps.keepsKeyboard(touching: tableRow.contentView, at: point, keepers: []))
    }

    @Test func aTapInAnAlertStaysWithTheAlertsField() {
        let alert = UIAlertController(title: "New profile", message: nil, preferredStyle: .alert)
        alert.addTextField()
        #expect(KeyboardTaps.keepsKeyboard(touching: alert.view, at: point, keepers: []))
    }

    @Test func aTapWithinAKeeperOnTheSameScreenKeepsIt() {
        let screen = UIViewController()
        screen.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let card = UIView(frame: CGRect(x: 16, y: 300, width: 358, height: 52))
        screen.view.addSubview(card)
        #expect(KeyboardTaps.keepsKeyboard(touching: screen.view, at: CGPoint(x: 30, y: 320), keepers: [card]))
        #expect(!KeyboardTaps.keepsKeyboard(touching: screen.view, at: CGPoint(x: 30, y: 200), keepers: [card]))
        #expect(!KeyboardTaps.keepsKeyboard(touching: screen.view, at: CGPoint(x: 30, y: 320), keepers: []))
    }

    @Test func aKeeperUnderAnotherScreenDoesNotCount() {
        let below = UIViewController()
        below.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let card = UIView(frame: CGRect(x: 16, y: 300, width: 358, height: 52))
        below.view.addSubview(card)
        let sheet = UIViewController()
        sheet.view.frame = below.view.frame
        #expect(!KeyboardTaps.keepsKeyboard(touching: sheet.view, at: CGPoint(x: 30, y: 320), keepers: [card]))
    }

    @Test func theWindowGetsOneTapThatHoldsNothingBack() throws {
        // A hosted test bundle runs inside the app and has a scene.
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        KeyboardDismissingTap.install(on: window)
        KeyboardDismissingTap.install(on: window)
        let taps = (window.gestureRecognizers ?? []).compactMap { $0 as? KeyboardDismissingTap }
        #expect(taps.count == 1)
        let tap = try #require(taps.first)
        #expect(!tap.cancelsTouchesInView && !tap.delaysTouchesBegan && !tap.delaysTouchesEnded)
        #expect(tap.gestureRecognizer(tap, shouldRecognizeSimultaneouslyWith: UIPanGestureRecognizer()))
    }

    /// A window over the app's scene with two fields, the first being typed into.
    private func windowWithFields() throws -> (UIWindow, UITextField, UITextField) {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = UIViewController()
        let first = UITextField(frame: CGRect(x: 0, y: 100, width: 390, height: 44))
        let second = UITextField(frame: CGRect(x: 0, y: 200, width: 390, height: 44))
        window.rootViewController?.view.addSubview(first)
        window.rootViewController?.view.addSubview(second)
        window.makeKeyAndVisible()
        KeyboardDismissingTap.install(on: window)
        first.becomeFirstResponder()
        return (window, first, second)
    }

    @Test func theTapEndsTheTypingOnceItsOwnActionsHaveRun() async throws {
        let (window, field, _) = try windowWithFields()
        defer { window.isHidden = true }
        #expect(field.isFirstResponder)
        let tap = try #require(window.gestureRecognizers?.compactMap { $0 as? KeyboardDismissingTap }.first)
        tap.endEditing()
        #expect(field.isFirstResponder, "a button under the finger acts first")
        try await Task.sleep(for: .milliseconds(100))
        #expect(!field.isFirstResponder)
    }

    @Test func aFieldTheTapFocusedKeepsTheKeyboard() async throws {
        let (window, first, second) = try windowWithFields()
        defer { window.isHidden = true }
        let tap = try #require(window.gestureRecognizers?.compactMap { $0 as? KeyboardDismissingTap }.first)
        tap.endEditing()
        second.becomeFirstResponder()
        try await Task.sleep(for: .milliseconds(100))
        #expect(second.isFirstResponder)
        #expect(!first.isFirstResponder)
    }
}
