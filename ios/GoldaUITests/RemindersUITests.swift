import XCTest

/// The reminders as the person meets them: a tap on the Sunday one opens Accounts in reconcile mode,
/// a tap on a wish's opens it in «Сомневаюсь» again. The first two simulate the tap
/// (`-golda.tapReminder.*` reads the planned notification back as a real tap does); the last lets a
/// real notification come on the simulator and taps it.
final class RemindersUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-golda.inMemory", "-golda.samples"] + extra
        app.launch()
        return app
    }

    @MainActor
    func testTheSundayReminderOpensAccountsInReconcileMode() {
        let app = launch(["-golda.tapReminder.reconcile"])
        XCTAssertTrue(app.descendants(matching: .any)["accounts.reconcileHint"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.tabBars.buttons["Accounts"].isSelected)
    }

    @MainActor
    func testAPaymentReminderOpensAccounts() {
        let app = launch(["-golda.tapReminder.payment"])
        XCTAssertTrue(app.descendants(matching: .any)["accounts.hero"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.tabBars.buttons["Accounts"].isSelected)
        XCTAssertFalse(app.descendants(matching: .any)["accounts.reconcileHint"].exists, "not in reconcile mode")
    }

    /// SPEC 6.4: when the time is up, the purchase opens in «Сомневаюсь» again, without «Подумаю».
    @MainActor
    func testAWishReminderOpensThePurchaseInNotSureAgain() {
        let app = launch(["-golda.tapReminder.wish"])
        XCTAssertTrue(app.navigationBars["Not sure"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["entry.skip"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["entry.think"].exists, "it has been thought about")
        app.buttons["entry.cancel"].tap()
        XCTAssertTrue(app.tabBars.buttons["Goals"].isSelected)
    }

    /// A real delivery: `-golda.remindSoon` asks for notifications at launch (allowed here) and
    /// brings the samples' waiting wish to a few seconds ahead. Its banner comes over the home
    /// screen, and tapping it opens the wish.
    @MainActor
    func testARealReminderComesAndItsTapOpensTheWish() throws {
        // The hosted CI simulator never shows the banner or Notification Center (three tries out
        // of three on each run); the scheduling and the tap have their own tests that run there.
        try XCTSkipIf(ProcessInfo.processInfo.environment["GOLDA_CI"] != nil, "no notification UI on the CI runner")
        let app = launch(["-golda.remindSoon"])
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        // Asked once per install; a run after an earlier one finds the answer given. The alert is in
        // the simulator's language, not the app's.
        let allow = springboard.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Allow", "Разрешить"])).firstMatch
        if allow.waitForExistence(timeout: 5) { allow.tap() }
        XCUIDevice.shared.press(.home)

        let notification = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Still want “Наушники”")).firstMatch
        // The banner leaves within seconds, sometimes as the tap lands; the notification stays in
        // Notification Center, pulled down from the top, where the tap is certain.
        if notification.waitForExistence(timeout: 20) { _ = notification.waitForNonExistence(timeout: 15) }
        let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.005))
        top.press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.7)))
        XCTAssertTrue(notification.waitForExistence(timeout: 10), "no notification came")
        notification.tap()
        // Notification Center is the lock screen's: a tap may first offer "Open".
        let open = springboard.buttons.matching(NSPredicate(format: "label IN %@", ["Open", "Открыть"])).firstMatch
        if open.waitForExistence(timeout: 3) { open.tap() }

        XCTAssertTrue(app.navigationBars["Not sure"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["entry.think"].exists)
    }
}
