import XCTest

/// The «Можно сегодня» widget's links: "+" (`golda://new`) opens the form for a new operation as
/// the toolbar's "+" does, and a tap beside the buttons (`golda://home`) opens Home.
final class AppLinkUITests: XCTestCase {
    private let plus = URL(string: "golda://new")!
    private let home = URL(string: "golda://home")!

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func app() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-golda.inMemory", "-golda.samples", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        return app
    }

    /// From outside the running app, as the widget opens it; `app.open` would relaunch it.
    @MainActor
    private func openFromOutside(_ link: URL, in app: XCUIApplication) {
        XCUIDevice.shared.system.open(link)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }

    /// A cold start waits for the books and the tabs, then shows the form.
    @MainActor
    func testPlusLaunchesTheAppOnTheNewOperationForm() {
        let app = app()
        app.open(plus)
        XCTAssertTrue(app.textFields["entry.amount"].waitForExistence(timeout: 30))
    }

    /// In the running app the form opens over the tab on screen.
    @MainActor
    func testPlusOpensTheFormInTheRunningApp() {
        let app = app()
        app.launch()
        let accounts = app.tabBars.buttons["Accounts"]
        XCTAssertTrue(accounts.waitForExistence(timeout: 30))
        accounts.tap()
        XCUIDevice.shared.press(.home)

        openFromOutside(plus, in: app)
        XCTAssertTrue(app.textFields["entry.amount"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testATapBesideTheButtonsOpensHome() {
        let app = app()
        app.launch()
        let accounts = app.tabBars.buttons["Accounts"]
        XCTAssertTrue(accounts.waitForExistence(timeout: 30))
        accounts.tap()
        XCTAssertFalse(app.descendants(matching: .any)["home.hero"].exists)
        XCUIDevice.shared.press(.home)

        openFromOutside(home, in: app)
        XCTAssertTrue(app.descendants(matching: .any)["home.hero"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Home"].isSelected)
    }
}
