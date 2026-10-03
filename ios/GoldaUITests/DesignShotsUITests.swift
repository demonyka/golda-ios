import XCTest

/// Not a check: pictures of every button, alert and sheet for a human to judge the colours by (D34).
/// Runs only when `GOLDA_SHOTS_DIR` is set for the runner
/// (`TEST_RUNNER_GOLDA_SHOTS_DIR=/tmp/golda-shots/D xcodebuild test ...`); `GOLDA_SHOTS_LANG`
/// chooses the language and `GOLDA_SHOTS_NAME` prefixes the files. Appearance is the simulator's
/// (`simctl ui`).
final class DesignShotsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testScreenshotsForTheLead() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let directory = environment["GOLDA_SHOTS_DIR"] else { throw XCTSkip("Screenshots are taken on request only.") }
        let language = environment["GOLDA_SHOTS_LANG"] ?? "en"
        let russian = language == "ru"
        let prefix = environment["GOLDA_SHOTS_NAME"] ?? language
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        var step = 0
        func shoot(_ name: String) throws {
            Thread.sleep(forTimeInterval: 0.8)
            step += 1
            let path = (directory as NSString).appendingPathComponent(String(format: "%@-%02d-%@.png", prefix, step, name))
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: path))
        }
        func launch(samples: Bool) -> XCUIApplication {
            let app = XCUIApplication()
            // The voice stub, so the mic records and thinks without a microphone or a network.
            app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", russian ? "ru_RU" : "en_US", "-golda.inMemory", "-golda.voiceStub=shawarma"]
                + (samples ? ["-golda.samples"] : [])
            app.launch()
            return app
        }

        // A fresh install: the welcome screen and its one button.
        var app = launch(samples: false)
        XCTAssertTrue(app.buttons["welcome.start"].waitForExistence(timeout: 30))
        try shoot("welcome")
        app.terminate()

        // Home with the mic in its three states.
        app = launch(samples: true)
        let mic = app.buttons["mic"]
        XCTAssertTrue(mic.waitForExistence(timeout: 30))
        Thread.sleep(forTimeInterval: 1)
        try shoot("home-mic")
        mic.tap()
        try shoot("mic-recording")
        mic.tap()
        try shoot("mic-thinking")
        mic.tap()

        // The new-profile alert, empty and then with a name.
        app.navigationBars.buttons["profileMenu"].firstMatch.tap()
        try shoot("profile-menu")
        app.buttons["profileMenu.new"].tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        // A fresh simulator explains swipe typing once, over the keyboard.
        let tip = app.buttons[russian ? "Продолжить" : "Continue"]
        if tip.waitForExistence(timeout: 1) { tip.tap() }
        try shoot("profile-alert-empty")
        alert.textFields.firstMatch.typeText(russian ? "Семья" : "Family")
        try shoot("profile-alert-named")
        alert.buttons[russian ? "Отмена" : "Cancel"].tap()

        // The operation form and the settings stand-ins.
        app.navigationBars.buttons["add"].firstMatch.tap()
        XCTAssertTrue(app.buttons["entry.cancel"].waitForExistence(timeout: 5))
        try shoot("entry-new")
        app.buttons["entry.cancel"].tap()
        app.buttons.matching(identifier: "home.operation").firstMatch.tap()
        XCTAssertTrue(app.buttons["entry.cancel"].waitForExistence(timeout: 5))
        try shoot("entry-editing")
        app.buttons["entry.cancel"].tap()
        app.navigationBars.buttons["settings"].firstMatch.tap()
        XCTAssertTrue(app.buttons["settings.done"].waitForExistence(timeout: 5))
        try shoot("settings")
        app.buttons["settings.done"].tap()

        // Accounts: the list with "+ Account", the new form empty and filled, then an account's
        // page, its form with the trash, the delete question, and the reconcile sheet.
        app.tabBars.buttons[russian ? "Счета" : "Accounts"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["accounts.hero"].waitForExistence(timeout: 10))
        let add = app.buttons["accounts.add"]
        for _ in 0..<8 where !(add.exists && add.isHittable) { app.swipeUp(velocity: .slow) }
        try shoot("accounts-add-row")
        add.tap()
        let name = app.textFields["accountForm.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        try shoot("account-form-empty")
        name.typeText(russian ? "Альфа вклад" : "Alfa savings")
        try shoot("account-form-named")
        app.buttons["accountForm.cancel"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5))
        for _ in 0..<8 { app.swipeDown(velocity: .fast) }

        let card = app.buttons.matching(identifier: "accounts.account").matching(NSPredicate(format: "label BEGINSWITH %@", "Карта ₽,")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertTrue(app.descendants(matching: .any)["account.hero"].waitForExistence(timeout: 5))
        try shoot("account-page")
        app.buttons["account.edit"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        try shoot("account-form-edit")
        app.buttons["accountForm.delete"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        try shoot("account-delete-question")
        app.alerts.firstMatch.buttons[russian ? "Отмена" : "Cancel"].tap()
        app.buttons["accountForm.cancel"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5))

        app.buttons["account.reconcile"].tap()
        let amount = app.textFields["reconcile.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        try shoot("reconcile")
        amount.tap()
        amount.typeText("9000")
        try shoot("reconcile-typed")
        app.buttons["reconcile.cancel"].tap()
        XCTAssertTrue(amount.waitForNonExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // The loan's early-repayment calculator.
        let loan = app.buttons.matching(identifier: "accounts.account").matching(NSPredicate(format: "label BEGINSWITH %@", "Кредит,")).firstMatch
        for _ in 0..<8 where !(loan.exists && loan.isHittable) { app.swipeUp(velocity: .slow) }
        loan.tap()
        let prepay = app.buttons["debt.prepay"]
        for _ in 0..<8 where !(prepay.exists && prepay.isHittable) { app.swipeUp(velocity: .slow) }
        // Clear of the tab bar, which the row is still "hittable" under.
        app.swipeUp(velocity: .slow)
        try shoot("loan-terms")
        prepay.tap()
        let prepayAmount = app.textFields["prepay.amount"]
        XCTAssertTrue(prepayAmount.waitForExistence(timeout: 5))
        if app.keyboards.firstMatch.waitForExistence(timeout: 2) { prepayAmount.typeText("50000") }
        try shoot("prepay")
        app.buttons["prepay.done"].tap()
    }
}
