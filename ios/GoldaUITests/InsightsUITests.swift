import XCTest

/// Insights on the made-up person's books: the ring with the week's total, the categories under it,
/// the day bars with their pill, the periods and the range of your own. The interface runs in
/// English so the controls can be found by their titles; the sample data stays what it is.
final class InsightsUITests: XCTestCase {
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

    /// The Insights tab, once its ring is there.
    @MainActor
    @discardableResult
    private func openInsights(_ app: XCUIApplication, tab: String = "Insights") -> XCUIElement {
        let button = app.tabBars.buttons[tab]
        XCTAssertTrue(button.waitForExistence(timeout: 30))
        button.tap()
        let ring = app.descendants(matching: .any)["insights.ring"]
        XCTAssertTrue(ring.waitForExistence(timeout: 10))
        return ring
    }

    @MainActor
    private func period(_ app: XCUIApplication) -> XCUIElement {
        app.segmentedControls["insights.period"]
    }

    @MainActor
    private func categories(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "insights.category")
    }

    @MainActor
    func testTheWeekIsThereWithItsRingAndItsCategories() {
        let app = launch()
        let ring = openInsights(app)

        // The middle as one sentence: the total and the daily average, in words.
        XCTAssertTrue(ring.label.hasPrefix("Spent "), ring.label)
        XCTAssertTrue(ring.label.contains("a day"), ring.label)
        XCTAssertTrue(app.staticTexts["insights.total"].exists)
        XCTAssertTrue(period(app).buttons["Week"].isSelected)
        XCTAssertEqual(period(app).buttons.count, 4)

        XCTAssertTrue(categories(app).firstMatch.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(categories(app).count, 3)
        // The biggest first: a label of the name, the amount in words and the share.
        let first = categories(app).firstMatch.label
        XCTAssertTrue(first.contains("Russian rubles"), first)
        XCTAssertTrue(first.hasSuffix("%"), first)
    }

    @MainActor
    func testACategoryPicksItsSliceAndTheMiddleSpeaksForIt() {
        let app = launch()
        let ring = openInsights(app)
        let total = ring.label
        let row = categories(app).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let name = row.label.components(separatedBy: ",").first ?? ""

        row.tap()
        // The middle is the category now: its name first, then its amount and share.
        XCTAssertTrue(ring.label.hasPrefix(name + ","), "\(ring.label) vs \(name)")
        XCTAssertNotEqual(ring.label, total)
        XCTAssertTrue(row.isSelected)

        // A second tap on the same row puts the whole back.
        row.tap()
        XCTAssertEqual(ring.label, total)
        XCTAssertFalse(row.isSelected)
    }

    @MainActor
    func testTheRingAnswersToTouchAndItsMiddleBringsTheWholeBack() {
        let app = launch()
        let ring = openInsights(app)
        let total = ring.label

        // The biggest slice starts at twelve o'clock and runs clockwise: the right of the ring is
        // inside it. The ring is a square in the middle of a row that is wider.
        let frame = ring.frame
        let side = frame.height
        func point(_ dx: CGFloat, _ dy: CGFloat) -> XCUICoordinate {
            ring.coordinate(withNormalizedOffset: CGVector(dx: 0.5 + dx * side / frame.width, dy: 0.5 + dy))
        }
        point(0.41, 0).tap()
        XCTAssertNotEqual(ring.label, total, "a tap on the ring picks a slice")
        XCTAssertFalse(ring.label.hasPrefix("Spent "), ring.label)

        point(0, 0).tap()
        XCTAssertEqual(ring.label, total, "a tap on the middle puts it back")
    }

    @MainActor
    func testAnotherPeriodChangesWhatIsShown() {
        let app = launch()
        let ring = openInsights(app)
        let week = ring.label
        let weekRows = categories(app).count

        period(app).buttons["Month"].tap()
        XCTAssertTrue(period(app).buttons["Month"].isSelected)
        // A month holds more of the sample's spending (the rent, among it).
        XCTAssertTrue(ring.waitForExistence(timeout: 5))
        XCTAssertNotEqual(ring.label, week)
        XCTAssertGreaterThan(categories(app).count, weekRows)

        let payday = period(app).buttons.matching(NSPredicate(format: "label BEGINSWITH 'Since'")).firstMatch
        XCTAssertTrue(payday.exists)
        payday.tap()
        XCTAssertTrue(payday.isSelected)
        XCTAssertNotEqual(ring.label, week)
    }

    @MainActor
    func testTheDayBarsShowTodayAndFollowAFinger() {
        let app = launch()
        openInsights(app)
        let days = app.descendants(matching: .any)["insights.days"]
        for _ in 0..<8 where !(days.exists && days.isHittable) { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(days.waitForExistence(timeout: 5))

        // Today is picked to begin with, its pill over the bars: the chart's value says so.
        XCTAssertTrue((days.value as? String ?? "").hasPrefix("Today · "), "\(days.value ?? "")")

        // A tap on the first bar of the week picks that day instead.
        days.coordinate(withNormalizedOffset: CGVector(dx: 0.07, dy: 0.5)).tap()
        let picked = days.value as? String ?? ""
        XCTAssertFalse(picked.hasPrefix("Today"), picked)
        XCTAssertTrue(picked.contains(" · "), picked)

        // A finger dragged across the bars follows them to the last one: today again.
        days.coordinate(withNormalizedOffset: CGVector(dx: 0.07, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: days.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)))
        XCTAssertTrue((days.value as? String ?? "").hasPrefix("Today · "), "\(days.value ?? "")")
    }

    @MainActor
    func testIncomeAndExchangeLossesCloseTheScreen() {
        let app = launch()
        openInsights(app)
        let income = app.descendants(matching: .any)["insights.income"]
        for _ in 0..<8 where !(income.exists && income.isHittable) { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(income.waitForExistence(timeout: 5))
        XCTAssertTrue(income.label.hasPrefix("Income"), income.label)
        let exchange = app.descendants(matching: .any)["insights.exchange"]
        XCTAssertTrue(exchange.exists)
        XCTAssertTrue(exchange.label.hasPrefix("Lost on exchange"), exchange.label)
    }

    @MainActor
    func testARangeOfYourOwnOpensTheDatesAndCancelLeavesTheScreenAsItWas() {
        let app = launch()
        let ring = openInsights(app)
        let week = ring.label

        period(app).buttons["Custom range"].tap()
        let done = app.buttons["insights.range.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        // VoiceOver hears which end each day is, not "Date Picker".
        let from = app.buttons["insights.range.from"]
        XCTAssertEqual(from.label, "From")
        XCTAssertFalse((from.value as? String ?? "").isEmpty)
        XCTAssertEqual(app.buttons["insights.range.to"].label, "To")
        // Each opens its calendar in a sheet of its own, and "Done" there goes back to the dates.
        from.tap()
        let calendarDone = app.buttons["insights.range.from.done"]
        XCTAssertTrue(calendarDone.waitForExistence(timeout: 5))
        XCTAssertTrue(app.datePickers["insights.range.fromPicker"].exists)
        calendarDone.tap()
        XCTAssertTrue(calendarDone.waitForNonExistence(timeout: 5))
        XCTAssertTrue(done.exists)
        app.buttons["insights.range.cancel"].tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))

        // Nothing changed: the week is still picked, there is no line of dates.
        XCTAssertTrue(period(app).buttons["Week"].isSelected)
        XCTAssertFalse(app.buttons["insights.range"].exists)
        XCTAssertEqual(ring.label, week)
    }

    @MainActor
    func testTakingARangeShowsItsDatesAndTheyOpenAgain() {
        let app = launch()
        openInsights(app)

        period(app).buttons["Custom range"].tap()
        let done = app.buttons["insights.range.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))

        // The sheet began on the week, so the range is the week, now the picked choice, with its dates.
        XCTAssertTrue(period(app).buttons["Custom range"].isSelected)
        let range = app.buttons["insights.range"]
        XCTAssertTrue(range.waitForExistence(timeout: 5))
        XCTAssertTrue(range.label.contains("–"), range.label)

        // The dates open the sheet again; cancelling it keeps the range.
        range.tap()
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        app.buttons["insights.range.cancel"].tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))
        XCTAssertTrue(period(app).buttons["Custom range"].isSelected)
        XCTAssertTrue(range.exists)

        // Another choice drops the line of dates.
        period(app).buttons["Month"].tap()
        XCTAssertTrue(range.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testRussianNamesTheChoicesAndTheTiles() {
        let app = launch(language: "ru")
        let ring = openInsights(app, tab: "Аналитика")
        XCTAssertTrue(ring.label.hasPrefix("Потрачено "), ring.label)
        XCTAssertTrue(period(app).buttons["Неделя"].isSelected)
        XCTAssertTrue(period(app).buttons["Месяц"].exists)
        XCTAssertTrue(period(app).buttons["Свой период"].exists)
        XCTAssertTrue(period(app).buttons.matching(NSPredicate(format: "label BEGINSWITH 'С '")).firstMatch.exists)
    }
}
