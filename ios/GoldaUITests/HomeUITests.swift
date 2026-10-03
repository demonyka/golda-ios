import XCTest

/// Home on the made-up person's books: the hero and the operations are there, and the profile menu
/// switches what they show. The interface runs in English so the menu and the alert can be found by
/// their titles; the sample notes stay Russian, as they are data.
final class HomeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ extra: [String] = [], language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-golda.inMemory", "-golda.samples", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "ru" ? "ru_RU" : "en_US"] + extra
        app.launch()
        return app
    }

    @MainActor
    private func hero(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["home.hero"]
    }

    @MainActor
    private func operations(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(identifier: "home.operation")
    }

    @MainActor
    func testTheHeroAndTheOperationsFollowTheProfile() {
        let app = launch()
        let hero = hero(app)
        XCTAssertTrue(hero.waitForExistence(timeout: 30))
        // One sentence for VoiceOver, opening with the caption and the amount in words.
        XCTAssertTrue(hero.label.hasPrefix("Safe to spend today. "), hero.label)
        XCTAssertTrue(hero.label.localizedCaseInsensitiveContains("rubles"), hero.label)
        let samplesHero = hero.label

        XCTAssertTrue(operations(app).firstMatch.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(operations(app).count, 3)
        // The newest one: the coffee an hour ago, paid in cash.
        XCTAssertTrue(operations(app).firstMatch.label.hasPrefix("Кофе, Наличные ₾, "), operations(app).firstMatch.label)
        XCTAssertFalse(app.descendants(matching: .any)["home.empty"].exists)

        // A second profile through the menu's alert opens at once, with nothing in it.
        let menu = app.buttons["profileMenu"]
        XCTAssertEqual(menu.label, "Profile: Personal")
        menu.tap()
        app.buttons["New profile"].tap()
        let alert = app.alerts["New profile"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.textFields.firstMatch.typeText("Family")
        alert.buttons["Create"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["home.empty"].waitForExistence(timeout: 5))
        XCTAssertEqual(menu.label, "Profile: Family")
        XCTAssertEqual(operations(app).count, 0)
        XCTAssertNotEqual(hero.label, samplesHero)
        XCTAssertTrue(hero.label.hasPrefix("Safe to spend today. 0 "), hero.label)

        // And back: the same books as before.
        menu.tap()
        app.buttons["Personal"].tap()
        XCTAssertTrue(operations(app).firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(menu.label, "Profile: Personal")
        XCTAssertEqual(hero.label, samplesHero)
        XCTAssertFalse(app.descendants(matching: .any)["home.empty"].exists)
    }

    @MainActor
    func testTheMicCyclesThroughItsStatesInBothLayouts() {
        for layout in ["accessory", "floating"] {
            let app = launch(["-golda.mic", layout])
            let mic = app.buttons["mic"]
            XCTAssertTrue(mic.waitForExistence(timeout: 30), layout)
            XCTAssertEqual(mic.label, "Say it", layout)
            mic.tap()
            XCTAssertEqual(mic.label, "Listening. Tap when done", layout)
            mic.tap()
            XCTAssertEqual(mic.label, "Working it out…", layout)
            mic.tap()
            XCTAssertEqual(mic.label, "Say it", layout)
            app.terminate()
        }
    }

    /// Not a check: pictures for a human. Runs only when `GOLDA_SHOTS_DIR` is set for the runner
    /// (`TEST_RUNNER_GOLDA_SHOTS_DIR=/tmp/golda-shots/H xcodebuild test ...`); `GOLDA_SHOTS_LANG`,
    /// `GOLDA_SHOTS_MIC` and `GOLDA_SHOTS_NAME` choose the language, the mic layout and the file names;
    /// `GOLDA_SHOTS_MENU=1` adds the profile menu open, `GOLDA_SHOTS_SCROLL=<swipes>` a shot further down.
    /// Appearance and text size are the simulator's (`simctl ui`).
    @MainActor
    func testScreenshotsForTheLead() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let directory = environment["GOLDA_SHOTS_DIR"] else { throw XCTSkip("Screenshots are taken on request only.") }
        let language = environment["GOLDA_SHOTS_LANG"] ?? "en"
        let layout = environment["GOLDA_SHOTS_MIC"] ?? "accessory"
        let name = environment["GOLDA_SHOTS_NAME"] ?? "home-\(language)-\(layout)"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        func shoot(_ suffix: String) throws {
            let path = (directory as NSString).appendingPathComponent("\(name)\(suffix).png")
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: path))
        }

        let app = launch(["-golda.mic", layout], language: language)
        XCTAssertTrue(hero(app).waitForExistence(timeout: 30))
        // Let the numbers roll in and the wave start.
        Thread.sleep(forTimeInterval: 1.5)
        try shoot("")
        if environment["GOLDA_SHOTS_MENU"] != nil {
            app.buttons["profileMenu"].tap()
            Thread.sleep(forTimeInterval: 1)
            try shoot("-menu")
        }
        if let swipes = environment["GOLDA_SHOTS_SCROLL"].flatMap(Int.init) {
            for _ in 0..<swipes { app.swipeUp() }
            Thread.sleep(forTimeInterval: 1)
            try shoot("-scrolled")
        }
    }
}
