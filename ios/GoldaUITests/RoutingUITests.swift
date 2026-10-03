import XCTest

/// The ways into the screens over the tabs, on the made-up person's books: "+" on every tab opens
/// the operation form, the gear the settings, "Manage profiles" the profiles, and an operation's
/// row the form with that operation, on Home and over an account's page. Some screens are
/// stand-ins until their steps fill them in; what is checked here is that each way leads there.
final class RoutingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-golda.inMemory", "-golda.samples"]
        app.launch()
        return app
    }

    /// The open tab's toolbar button: each tab has its own toolbar, and only the open one can be tapped.
    @MainActor
    private func tapToolbarButton(_ identifier: String, in app: XCUIApplication, line: UInt = #line) {
        let buttons = app.navigationBars.buttons.matching(identifier: identifier)
        XCTAssertTrue(buttons.firstMatch.waitForExistence(timeout: 10), identifier, line: line)
        guard let button = buttons.allElementsBoundByIndex.first(where: { $0.exists && $0.isHittable }) else {
            return XCTFail("no tappable \(identifier)", line: line)
        }
        button.tap()
    }

    @MainActor
    func testPlusOpensTheOperationFormFromEveryTab() {
        let app = launch()
        for tab in ["Home", "Accounts", "Goals", "Insights"] {
            let tabButton = app.tabBars.buttons[tab]
            XCTAssertTrue(tabButton.waitForExistence(timeout: 30), tab)
            tabButton.tap()
            tapToolbarButton("add", in: app)

            XCTAssertTrue(app.navigationBars["New operation"].waitForExistence(timeout: 5), "the form from \(tab)")
            XCTAssertFalse(app.descendants(matching: .any)["entry.editing"].exists, "a new operation from \(tab)")
            let cancel = app.buttons["entry.cancel"]
            XCTAssertEqual(cancel.label, "Cancel")
            cancel.tap()
            XCTAssertTrue(cancel.waitForNonExistence(timeout: 5), "the form closes over \(tab)")
            XCTAssertTrue(tabButton.isSelected, "still on \(tab)")
        }
    }

    @MainActor
    func testTheGearOpensSettingsAndTheProfileMenuOpensProfiles() {
        let app = launch()
        XCTAssertTrue(app.tabBars.buttons["Accounts"].waitForExistence(timeout: 30))
        app.tabBars.buttons["Accounts"].tap()
        tapToolbarButton("settings", in: app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let done = app.buttons["settings.done"]
        XCTAssertEqual(done.label, "Done")
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))

        let menu = app.navigationBars.buttons.matching(identifier: "profileMenu").allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(menu)
        menu?.tap()
        app.buttons["Manage profiles"].tap()
        XCTAssertTrue(app.navigationBars["Profiles"].waitForExistence(timeout: 5))
        app.buttons["profiles.done"].tap()
        XCTAssertTrue(app.buttons["profiles.done"].waitForNonExistence(timeout: 5))
    }

    /// A tap on an operation opens the form with that very operation: its note is in the form.
    @MainActor
    func testAnOperationOnHomeOpensTheFormWithIt() {
        let app = launch()
        let operations = app.buttons.matching(identifier: "home.operation")
        XCTAssertTrue(operations.firstMatch.waitForExistence(timeout: 30))
        let second = operations.element(boundBy: 1)
        let title = String(second.label.prefix { $0 != "," })
        second.tap()

        XCTAssertTrue(app.navigationBars["Operation"].waitForExistence(timeout: 5))
        let note = app.textFields["entry.note"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertEqual(note.value as? String, title)
        app.buttons["entry.cancel"].tap()
        XCTAssertTrue(note.waitForNonExistence(timeout: 5))
    }

    /// The same over a page pushed on the Accounts tab: the form opens over the page, and the page
    /// is still there when it closes.
    @MainActor
    func testAnOperationOnAnAccountPageOpensTheFormOverThePage() {
        let app = launch()
        let tab = app.tabBars.buttons["Accounts"]
        XCTAssertTrue(tab.waitForExistence(timeout: 30))
        tab.tap()
        let card = app.buttons.matching(identifier: "accounts.account").matching(NSPredicate(format: "label BEGINSWITH %@", "Карта ₽,")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        let page = app.descendants(matching: .any)["account.hero"]
        XCTAssertTrue(page.waitForExistence(timeout: 5))

        let operation = app.buttons.matching(identifier: "account.operation").firstMatch
        XCTAssertTrue(operation.waitForExistence(timeout: 5))
        // The page shows the card's own side and Home the whole operation, so only the title
        // (the label up to its first comma) is the same in both.
        let title = String(operation.label.prefix { $0 != "," })
        operation.tap()

        let note = app.textFields["entry.note"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertEqual(note.value as? String, title)
        XCTAssertTrue(app.navigationBars["Operation"].exists)
        app.buttons["entry.cancel"].tap()
        XCTAssertTrue(note.waitForNonExistence(timeout: 5))
        XCTAssertTrue(page.exists, "back on the account's page")
        XCTAssertTrue(app.navigationBars["Карта ₽"].exists)
    }
}
