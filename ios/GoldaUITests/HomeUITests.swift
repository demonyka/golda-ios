import XCTest

/// Home on the made-up person's books: the hero and the operations are there, and the profile menu
/// switches what they show. The interface runs in English so the menu and the alert can be found by
/// their titles; the sample notes stay Russian, as they are data.
final class HomeUITests: XCTestCase {
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
    func testTheMicCyclesThroughItsStates() {
        let app = launch()
        let mic = app.buttons["mic"]
        XCTAssertTrue(mic.waitForExistence(timeout: 30))
        XCTAssertEqual(mic.label, "Say it")
        mic.tap()
        XCTAssertEqual(mic.label, "Listening. Tap when done")
        mic.tap()
        XCTAssertEqual(mic.label, "Working it out…")
        mic.tap()
        XCTAssertEqual(mic.label, "Say it")
    }

    /// The tab bar stays whole through a scroll down and back. With `.onScrollDown` iOS 26.2 folds it
    /// on the way down and brings it back only at the very top, so after a short scroll up three of
    /// the four tabs were gone. The large title still folds on the way down and opens at the top.
    @MainActor
    func testTheTabBarStaysWholeWhileTheListScrolls() {
        let app = launch()
        XCTAssertTrue(hero(app).waitForExistence(timeout: 30))
        let titleBar = app.navigationBars.firstMatch
        let tallTitle = titleBar.frame.height
        assertEveryTabIsReachable(app, "at the top")

        for _ in 0..<3 { app.swipeUp() }
        assertEveryTabIsReachable(app, "scrolled down")
        XCTAssertTrue(eventually { titleBar.frame.height < tallTitle }, "the large title folds on the way down")

        // A short slow drag back up, the way a reader backs up a few rows: not to the top.
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertFalse(isOnScreen(hero(app)), "still below the top")
        assertEveryTabIsReachable(app, "scrolled back up a little")

        for _ in 0..<4 { app.swipeDown() }
        XCTAssertTrue(eventually { self.isOnScreen(self.hero(app)) }, "back at the top")
        XCTAssertTrue(eventually { abs(titleBar.frame.height - tallTitle) < 1 }, "the large title opens again at the top")
        assertEveryTabIsReachable(app, "back at the top")
    }

    /// The mic sits in the bottom safe area of the tab's screen, so the list ends above it: at the
    /// very bottom the last operation is clear of the button, not under it. With the inset around
    /// the navigation stack instead, the last row stopped under the mic.
    @MainActor
    func testTheLastOperationScrollsClearOfTheMic() {
        let app = launch()
        let mic = app.buttons["mic"]
        XCTAssertTrue(mic.waitForExistence(timeout: 30))
        XCTAssertTrue(operations(app).firstMatch.waitForExistence(timeout: 5))

        // Down to the end: until a swipe no longer brings a new last row.
        var lastLabel = ""
        for _ in 0..<15 {
            app.swipeUp()
            let label = lowestOperation(app)?.label ?? ""
            if label == lastLabel { break }
            lastLabel = label
        }
        guard let last = lowestOperation(app) else { return XCTFail("no operation on screen") }
        XCTAssertTrue(isOnScreen(last), last.label)
        XCTAssertLessThanOrEqual(last.frame.maxY, mic.frame.minY, "the last operation ends under the mic: \(last.frame) vs \(mic.frame)")
    }

    @MainActor
    private func lowestOperation(_ app: XCUIApplication) -> XCUIElement? {
        operations(app).allElementsBoundByIndex.filter(\.exists).max { $0.frame.maxY < $1.frame.maxY }
    }

    /// All four tabs are on the bar and can be tapped, not folded into the selected one.
    @MainActor
    private func assertEveryTabIsReachable(_ app: XCUIApplication, _ moment: String, line: UInt = #line) {
        for title in ["Home", "Accounts", "Goals", "Insights"] {
            let tab = app.tabBars.buttons[title]
            XCTAssertTrue(eventually { self.isOnScreen(tab) }, "\(title) tab, \(moment)", line: line)
        }
    }

    /// A list drops the rows it scrolled away from, and asking a missing element whether it is
    /// hittable fails the test, so existence comes first.
    @MainActor
    private func isOnScreen(_ element: XCUIElement) -> Bool {
        element.exists && element.isHittable
    }

    /// Polls `condition` until it holds or `timeout` runs out: bars and titles animate after a swipe.
    @MainActor
    private func eventually(timeout: TimeInterval = 3, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return true
    }

    /// Not a check: pictures for a human. Runs only when `GOLDA_SHOTS_DIR` is set for the runner
    /// (`TEST_RUNNER_GOLDA_SHOTS_DIR=/tmp/golda-shots/H xcodebuild test ...`); `GOLDA_SHOTS_LANG` and
    /// `GOLDA_SHOTS_NAME` choose the language and the file names; `GOLDA_SHOTS_MENU=1` adds the
    /// profile menu open, `GOLDA_SHOTS_SCROLL=<swipes>` a shot further down.
    /// Appearance and text size are the simulator's (`simctl ui`).
    @MainActor
    func testScreenshotsForTheLead() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let directory = environment["GOLDA_SHOTS_DIR"] else { throw XCTSkip("Screenshots are taken on request only.") }
        let language = environment["GOLDA_SHOTS_LANG"] ?? "en"
        let name = environment["GOLDA_SHOTS_NAME"] ?? "home-\(language)"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        func shoot(_ suffix: String) throws {
            let path = (directory as NSString).appendingPathComponent("\(name)\(suffix).png")
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: path))
        }

        let app = launch(language: language)
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
