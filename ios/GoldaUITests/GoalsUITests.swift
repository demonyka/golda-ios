import XCTest

/// Goals on the made-up person's books: "Велосипед" is the main goal, "Подушка" (110 %) another,
/// "Наушники" wait for a decision and "Кроссовки" were skipped. Add a goal, make another one main,
/// reach a goal and buy it, take a wish away and bring it back, open a waiting wish. The sample
/// names stay Russian in both languages, as they are data.
final class GoalsUITests: XCTestCase {
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

    /// The Goals tab, once its hero is there.
    @MainActor
    @discardableResult
    private func openGoals(_ app: XCUIApplication, tab: String = "Goals") -> XCUIElement {
        let button = app.tabBars.buttons[tab]
        XCTAssertTrue(button.waitForExistence(timeout: 30))
        button.tap()
        let hero = app.buttons["goals.hero"]
        XCTAssertTrue(hero.waitForExistence(timeout: 10))
        return hero
    }

    @MainActor
    private func row(_ app: XCUIApplication, _ identifier: String, named name: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).matching(NSPredicate(format: "label BEGINSWITH %@", name + ",")).firstMatch
    }

    /// Swipes the list up until [element] can be tapped clear of the tab bar.
    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 where !(element.exists && element.isHittable) { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
    }

    @MainActor
    func testAddingAGoalPutsItAmongTheOthers() {
        let app = launch()
        openGoals(app)
        XCTAssertTrue(app.staticTexts["Other goals"].exists)
        let add = app.buttons["goals.add"]
        scrollTo(add, in: app)
        XCTAssertEqual(add.label, "Add goal")
        add.tap()

        let name = app.textFields["goalForm.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["New goal"].exists)
        let save = app.buttons["goalForm.save"]
        XCTAssertFalse(save.isEnabled, "nothing to save yet")
        // The first goal beside a main one starts without the star.
        XCTAssertEqual(app.switches["goalForm.main"].value as? String, "0")
        name.tap()
        name.typeText("Vacation")
        let target = app.textFields["goalForm.target"]
        target.tap()
        target.typeText("50000")
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5))

        let vacation = row(app, "goals.goal", named: "Vacation")
        XCTAssertTrue(vacation.waitForExistence(timeout: 5))
        XCTAssertTrue(vacation.label.contains("0\u{00A0}% · of 50000 US dollars"), vacation.label)
        XCTAssertTrue(app.buttons["goals.hero"].label.hasPrefix("Велосипед. "))
    }

    @MainActor
    func testTheStarMakesAnotherGoalTheMainOne() {
        let app = launch()
        let hero = openGoals(app)
        XCTAssertTrue(hero.label.hasPrefix("Велосипед. "), hero.label)
        XCTAssertFalse(app.buttons["goals.buy"].exists, "the bike is not reached")

        let cushion = row(app, "goals.goal", named: "Подушка")
        XCTAssertTrue(cushion.waitForExistence(timeout: 5))
        XCTAssertTrue(cushion.label.contains("110\u{00A0}%"), cushion.label)
        cushion.tap()

        let star = app.switches["goalForm.main"]
        XCTAssertTrue(star.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Goal"].exists)
        XCTAssertEqual(star.value as? String, "0")
        star.switches.firstMatch.tap()
        XCTAssertTrue(eventually { star.value as? String == "1" })
        XCTAssertTrue(app.staticTexts["“Велосипед” will no longer be the main goal."].exists)
        app.buttons["goalForm.save"].tap()
        XCTAssertTrue(star.waitForNonExistence(timeout: 5))

        // "Подушка" is the hero now, reached, with the screen's only "Buy"; the bike is a row.
        XCTAssertTrue(eventually { hero.label.hasPrefix("Подушка. ") }, hero.label)
        XCTAssertTrue(hero.label.contains("110\u{00A0}% of 300000 Russian rubles"), hero.label)
        XCTAssertTrue(app.buttons["goals.buy"].waitForExistence(timeout: 5))
        XCTAssertTrue(row(app, "goals.goal", named: "Велосипед").waitForExistence(timeout: 5))
        XCTAssertFalse(row(app, "goals.goal", named: "Подушка").exists)

        // The main goal's star cannot go off: another goal's star is what moves it.
        hero.tap()
        XCTAssertTrue(star.waitForExistence(timeout: 5))
        XCTAssertEqual(star.value as? String, "1")
        XCTAssertFalse(star.isEnabled)
        XCTAssertTrue(app.staticTexts["To change the main goal, star another one."].exists)
        app.buttons["goalForm.cancel"].tap()
        XCTAssertTrue(star.waitForNonExistence(timeout: 5))
    }

    /// The bike's target lowered to what is already saved: reached, bought from the card the
    /// question names, and gone; the cushion becomes the main goal.
    @MainActor
    func testAReachedGoalIsBoughtAfterTheQuestion() {
        let app = launch(language: "ru")
        let hero = openGoals(app, tab: "Цели")
        hero.tap()

        let target = app.textFields["goalForm.target"]
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        // At the end of "80 000", so the deletes take all of it.
        target.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        target.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10))
        XCTAssertTrue(eventually { (target.value as? String).map { $0.isEmpty || $0 == "0" } ?? true }, "\(target.value ?? "")")
        target.typeText("100")
        XCTAssertTrue(eventually { target.value as? String == "100" }, "\(target.value ?? "")")
        app.buttons["goalForm.save"].tap()
        XCTAssertTrue(target.waitForNonExistence(timeout: 5))

        let buy = app.buttons["goals.buy"]
        XCTAssertTrue(buy.waitForExistence(timeout: 5))
        XCTAssertEqual(buy.label, "Купить Велосипед · 100 ₽")
        // Well over the new target: everything put aside stays, the percent says by how much.
        XCTAssertTrue(hero.label.contains("\u{00A0}% из 100 российских рублей"), hero.label)
        buy.tap()

        let alert = app.alerts["Купить «Велосипед»?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts["Расход 100 ₽ с «Карта ₽». Цель закроется."].exists)
        // Changing one's mind leaves everything as it was.
        alert.buttons["Отмена"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
        XCTAssertTrue(hero.label.hasPrefix("Велосипед. "))

        buy.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Купить"].tap()

        // The toast says what was bought; the cushion is the main goal now.
        let toast = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Велосипед · 100\u{00A0}₽")).firstMatch
        XCTAssertTrue(toast.waitForExistence(timeout: 5))
        XCTAssertTrue(toast.label.contains("ч работы"), toast.label)
        XCTAssertTrue(eventually { hero.label.hasPrefix("Подушка. ") }, hero.label)
        XCTAssertFalse(row(app, "goals.goal", named: "Велосипед").exists)

        // The expense is on Home, the newest operation.
        app.tabBars.buttons["Главная"].tap()
        let newest = app.buttons.matching(identifier: "home.operation").firstMatch
        XCTAssertTrue(newest.waitForExistence(timeout: 5))
        XCTAssertTrue(newest.label.hasPrefix("Велосипед"), newest.label)
    }

    @MainActor
    func testAWishLeavesWithASwipeOrALongPressAndComesBack() {
        let app = launch()
        openGoals(app)
        let headphones = row(app, "goals.wish", named: "Наушники")
        scrollTo(headphones, in: app)
        XCTAssertTrue(app.staticTexts["Waiting for a decision"].exists)
        // The share depends on the rate of the day; the wait is three days from now.
        XCTAssertTrue(headphones.label.hasPrefix("Наушники, in 3 days · "), headphones.label)
        XCTAssertTrue(headphones.label.hasSuffix("\u{00A0}% of the goal, 120 US dollars"), headphones.label)

        headphones.swipeLeft()
        let remove = app.buttons["Remove"]
        if remove.waitForExistence(timeout: 2) { remove.tap() }
        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["“Наушники” removed"].exists)
        XCTAssertTrue(headphones.waitForNonExistence(timeout: 5))
        undo.tap()
        XCTAssertTrue(headphones.waitForExistence(timeout: 5))

        // The long press offers the same.
        headphones.press(forDuration: 1.2)
        let menuRemove = app.buttons["Remove"]
        XCTAssertTrue(menuRemove.waitForExistence(timeout: 5))
        menuRemove.tap()
        XCTAssertTrue(headphones.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Waiting for a decision"].exists)
    }

    @MainActor
    func testAWaitingWishOpensTheOperationForm() {
        let app = launch()
        openGoals(app)
        let headphones = row(app, "goals.wish", named: "Наушники")
        scrollTo(headphones, in: app)
        headphones.tap()

        let cancel = app.buttons["entry.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Goals"].isSelected)
    }

    @MainActor
    func testTheDecidedListUnfoldsAndFolds() {
        let app = launch()
        openGoals(app)
        let toggle = app.descendants(matching: .any).matching(identifier: "goals.decidedToggle").firstMatch
        scrollTo(toggle, in: app)
        XCTAssertEqual(toggle.label, "Decided · 1")
        let sneakers = row(app, "goals.decided", named: "Кроссовки")
        XCTAssertFalse(sneakers.exists)
        toggle.tap()
        // The row unfolds under the toggle, near the bottom of the screen.
        scrollTo(sneakers, in: app)
        XCTAssertTrue(sneakers.label.contains("skipped"), sneakers.label)
        toggle.tap()
        XCTAssertTrue(sneakers.waitForNonExistence(timeout: 5))
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
    /// (`TEST_RUNNER_GOLDA_SHOTS_DIR=/tmp/golda-shots/E2 xcodebuild test ...`); `GOLDA_SHOTS_LANG`
    /// and `GOLDA_SHOTS_NAME` choose the language and the file names. Appearance and text size are
    /// the simulator's (`simctl ui`). Shoots the tab, the decided list, the forms, the buy question
    /// and the toast after it.
    @MainActor
    func testScreenshotsForTheLead() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let directory = environment["GOLDA_SHOTS_DIR"] else { throw XCTSkip("Screenshots are taken on request only.") }
        let language = environment["GOLDA_SHOTS_LANG"] ?? "en"
        let russian = language == "ru"
        let name = environment["GOLDA_SHOTS_NAME"] ?? "goals-\(language)"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        var step = 0
        func shoot(_ suffix: String) throws {
            Thread.sleep(forTimeInterval: 1)
            step += 1
            let path = (directory as NSString).appendingPathComponent(String(format: "%@-%02d-%@.png", name, step, suffix))
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: path))
        }

        let app = launch(language: language)
        let hero = openGoals(app, tab: russian ? "Цели" : "Goals")
        try shoot("tab")
        let toggle = app.descendants(matching: .any).matching(identifier: "goals.decidedToggle").firstMatch
        scrollTo(toggle, in: app)
        toggle.tap()
        app.swipeUp(velocity: .slow)
        try shoot("tab-decided")
        for _ in 0..<8 { app.swipeDown(velocity: .fast) }

        let add = app.buttons["goals.add"]
        scrollTo(add, in: app)
        add.tap()
        XCTAssertTrue(app.textFields["goalForm.name"].waitForExistence(timeout: 5))
        try shoot("form-new")
        app.textFields["goalForm.name"].typeText(russian ? "Отпуск" : "Vacation")
        app.textFields["goalForm.target"].tap()
        app.textFields["goalForm.target"].typeText("150000")
        try shoot("form-new-filled")
        app.buttons["goalForm.cancel"].tap()
        for _ in 0..<8 { app.swipeDown(velocity: .fast) }

        let cushion = row(app, "goals.goal", named: "Подушка")
        scrollTo(cushion, in: app)
        cushion.tap()
        XCTAssertTrue(app.textFields["goalForm.name"].waitForExistence(timeout: 5))
        try shoot("form-edit")
        // At the largest text sizes the star is a screen or two down the form.
        let star = app.switches["goalForm.main"]
        scrollTo(star, in: app)
        star.switches.firstMatch.tap()
        try shoot("form-edit-star")
        app.buttons["goalForm.save"].tap()
        XCTAssertTrue(star.waitForNonExistence(timeout: 5))
        for _ in 0..<8 { app.swipeDown(velocity: .fast) }
        XCTAssertTrue(hero.waitForExistence(timeout: 5))
        // The wave settles once the goal is reached.
        Thread.sleep(forTimeInterval: 1.5)
        try shoot("tab-reached")

        let buy = app.buttons["goals.buy"]
        scrollTo(buy, in: app)
        buy.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        try shoot("buy-question")
        app.alerts.firstMatch.buttons[russian ? "Купить" : "Buy"].tap()
        // No swipe here: a swipe down over the toast sends it away.
        try shoot("bought-toast")
    }
}
