import XCTest

/// Data that cannot be opened shows a calm screen with "Try again" rather than a blank page or a
/// crash, and trying again opens the app. `-golda.failDatabase` makes the first opening fail.
final class DataFailureUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launchFailing(language: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(\(language))", "-AppleLocale", language == "ru" ? "ru_RU" : "en_US",
            "-golda.inMemory", "-golda.samples", "-golda.failDatabase",
        ]
        app.launch()
        return app
    }

    @MainActor
    func testTheFailureScreenOffersTryAgainAndItOpensTheApp() {
        let app = launchFailing(language: "en")

        let retry = app.buttons["failure.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 30))
        XCTAssertEqual(retry.label, "Try again")
        XCTAssertTrue(app.staticTexts["Couldn’t open your data"].exists)
        XCTAssertTrue(app.staticTexts["Your records couldn’t be read. Nothing was deleted."].exists)
        // A debug build says what went wrong.
        XCTAssertTrue(app.staticTexts["failure.reason"].label.contains("-golda.failDatabase"))
        XCTAssertFalse(app.tabBars.firstMatch.exists)

        retry.tap()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))
        XCTAssertFalse(retry.exists)
    }

    @MainActor
    func testTheFailureScreenSpeaksRussian() {
        let app = launchFailing(language: "ru")

        let retry = app.buttons["failure.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 30))
        XCTAssertEqual(retry.label, "Повторить")
        XCTAssertTrue(app.staticTexts["Не удалось открыть данные"].exists)
        XCTAssertTrue(app.staticTexts["Записи не удалось прочитать. Ничего не удалено."].exists)
    }
}
