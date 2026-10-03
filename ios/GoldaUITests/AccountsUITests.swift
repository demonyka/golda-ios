import XCTest

/// Accounts on the made-up person's books: open an account, reconcile it to a different balance and
/// see the balance move, and "Сходится", which only closes the sheet. The sample names stay Russian
/// in both languages, as they are data.
final class AccountsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-golda.inMemory", "-golda.samples", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "ru" ? "ru_RU" : "en_US"]
        app.launch()
        return app
    }

    /// The Accounts tab, once its hero is there.
    @MainActor
    private func openAccounts(_ app: XCUIApplication, tab: String = "Accounts") -> XCUIElement {
        let button = app.tabBars.buttons[tab]
        XCTAssertTrue(button.waitForExistence(timeout: 30))
        button.tap()
        let hero = app.descendants(matching: .any)["accounts.hero"]
        XCTAssertTrue(hero.waitForExistence(timeout: 10))
        return hero
    }

    @MainActor
    private func account(_ app: XCUIApplication, named name: String) -> XCUIElement {
        app.buttons.matching(identifier: "accounts.account").matching(NSPredicate(format: "label BEGINSWITH %@", name + ",")).firstMatch
    }

    @MainActor
    func testReconcilingToADifferentBalanceMovesIt() {
        let app = launch()
        let hero = openAccounts(app)
        XCTAssertTrue(hero.label.hasPrefix("Total. "), hero.label)
        XCTAssertTrue(hero.label.contains("Spare money does more paying it off."), hero.label)

        let card = account(app, named: "Карта ₽")
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(card.label.contains("Counts in “Safe to spend today”, Card, 9101 Russian rubles"), card.label)
        card.tap()

        // The page: the name as the title, the balance, the account's own operations.
        let page = app.descendants(matching: .any)["account.hero"]
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Карта ₽"].exists)
        XCTAssertTrue(page.label.hasPrefix("Card. 9101 Russian rubles."), page.label)
        let operations = app.buttons.matching(identifier: "account.operation")
        XCTAssertGreaterThan(operations.count, 2)
        XCTAssertTrue(app.buttons["account.edit"].exists)

        // The bank shows 9 000 ₽: the sheet says what goes in, and the balance follows.
        app.buttons["account.reconcile"].tap()
        let field = app.textFields["reconcile.amount"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let save = app.buttons["reconcile.save"]
        XCTAssertEqual(save.label, "It matches")
        field.tap()
        field.typeText("9000")
        // VoiceOver hears the amount in words.
        XCTAssertTrue(save.label.hasPrefix("Record ") && save.label.hasSuffix("101 Russian rubles"), save.label)
        XCTAssertTrue(app.staticTexts["reconcile.difference"].label.hasPrefix("Difference "))
        save.tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))

        XCTAssertTrue(eventually { page.label.hasPrefix("Card. 9000 Russian rubles.") }, page.label)
        XCTAssertTrue(eventually { operations.firstMatch.label.hasPrefix("Reconciliation, ") }, operations.firstMatch.label)
        XCTAssertTrue(operations.firstMatch.label.contains("-101 Russian rubles") || operations.firstMatch.label.contains("−101 Russian rubles"), operations.firstMatch.label)

        // Back on the list, the row shows it too.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(eventually { card.exists && card.label.contains("9000 Russian rubles") }, card.label)
    }

    /// "Сходится" records nothing: the sheet closes, the balance and the operations stay.
    @MainActor
    func testItMatchesOnlyClosesTheSheet() {
        let app = launch(language: "ru")
        _ = openAccounts(app, tab: "Счета")
        let gel = account(app, named: "Мультивалютная GEL")
        XCTAssertTrue(gel.waitForExistence(timeout: 5))
        gel.tap()

        let page = app.descendants(matching: .any)["account.hero"]
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        XCTAssertTrue(page.label.hasPrefix("Карта · Мультивалютная. "), page.label)
        let before = page.label
        let operations = app.buttons.matching(identifier: "account.operation")
        let count = operations.count
        let newest = operations.firstMatch.label

        let reconcile = app.buttons["account.reconcile"]
        XCTAssertEqual(reconcile.label, "Сверить")
        reconcile.tap()
        let save = app.buttons["reconcile.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertEqual(save.label, "Сходится")
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 5))

        // Give a stray adjustment the time to show up, then check none did.
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertEqual(page.label, before)
        XCTAssertEqual(operations.count, count)
        XCTAssertEqual(operations.firstMatch.label, newest)
        XCTAssertFalse(newest.hasPrefix("Сверка"))
    }

    /// Polls `condition` until it holds or `timeout` runs out: the list follows the database.
    @MainActor
    private func eventually(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return true
    }

    /// Not a check: pictures for a human. Runs only when `GOLDA_SHOTS_DIR` is set for the runner
    /// (`TEST_RUNNER_GOLDA_SHOTS_DIR=/tmp/golda-shots/B1 xcodebuild test ...`); `GOLDA_SHOTS_LANG`
    /// and `GOLDA_SHOTS_NAME` choose the language and the file names. Appearance and text size are
    /// the simulator's (`simctl ui`). Shoots the tab, a foreign card's page, and its reconcile sheet
    /// with a different balance typed in.
    @MainActor
    func testScreenshotsForTheLead() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let directory = environment["GOLDA_SHOTS_DIR"] else { throw XCTSkip("Screenshots are taken on request only.") }
        let language = environment["GOLDA_SHOTS_LANG"] ?? "en"
        let name = environment["GOLDA_SHOTS_NAME"] ?? "accounts-\(language)"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        func shoot(_ suffix: String) throws {
            let path = (directory as NSString).appendingPathComponent("\(name)\(suffix).png")
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: path))
        }

        let app = launch(language: language)
        _ = openAccounts(app, tab: language == "ru" ? "Счета" : "Accounts")
        // Let the numbers roll in.
        Thread.sleep(forTimeInterval: 1.5)
        try shoot("-tab")
        app.swipeUp()
        Thread.sleep(forTimeInterval: 1)
        try shoot("-tab-scrolled")
        app.swipeDown()
        app.swipeDown()

        // At the largest text sizes the card is a few screens down, and the list builds rows lazily.
        let usd = account(app, named: "Мультивалютная USD")
        for _ in 0..<8 where !usd.waitForExistence(timeout: 1) || !usd.isHittable { app.swipeUp() }
        XCTAssertTrue(usd.waitForExistence(timeout: 5))
        usd.tap()
        XCTAssertTrue(app.descendants(matching: .any)["account.hero"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1)
        try shoot("-page")

        app.buttons["account.reconcile"].tap()
        let field = app.textFields["reconcile.amount"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1)
        try shoot("-sheet")
        field.tap()
        field.typeText("150")
        Thread.sleep(forTimeInterval: 1)
        try shoot("-sheet-typed")
    }
}
