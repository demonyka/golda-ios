import XCTest

/// The profiles screens on the made-up person's books: a profile is created, renamed, opened and
/// deleted; its payday moves "days to payday" on Home; a payment is set aside on Home and its
/// delete can be undone. The interface runs in English so elements can be found by their titles;
/// the sample names stay Russian, as they are data.
final class ProfilesUITests: XCTestCase {
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
    private func openProfiles(_ app: XCUIApplication, line: UInt = #line) {
        let menu = app.buttons["profileMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 30), line: line)
        menu.tap()
        app.buttons["profileMenu.manage"].tap()
        XCTAssertTrue(app.navigationBars["Profiles"].waitForExistence(timeout: 5), line: line)
    }

    @MainActor
    private func closeProfiles(_ app: XCUIApplication, line: UInt = #line) {
        let done = app.buttons["profiles.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), line: line)
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5), line: line)
    }

    /// A profile's row in the list by its label: the name, and ", active" for the active one.
    @MainActor
    private func row(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(identifier: "profiles.row").matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    @MainActor
    private func back(_ app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    // MARK: Scenarios

    @MainActor
    func testAProfileIsCreatedRenamedOpenedOnItsOwnAndDeleted() {
        let app = launch()
        XCTAssertTrue(hero(app).waitForExistence(timeout: 30))
        let samplesHero = hero(app).label
        openProfiles(app)
        XCTAssertTrue(row("Personal, active", in: app).exists)
        XCTAssertTrue(app.descendants(matching: .any)["profiles.lastProfileReason"].exists, "the only profile says why it stays")

        // Created from the list, it opens to be set up; the active profile stays.
        app.buttons["profiles.add"].tap()
        let alert = app.alerts["New profile"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertFalse(alert.buttons["Create"].firstMatch.isEnabled, "no name yet")
        alert.textFields.firstMatch.typeText("Trip")
        alert.buttons["Create"].tap()
        XCTAssertTrue(app.navigationBars["Trip"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["profile.makeActive"].exists)

        // Renamed from its screen.
        app.buttons["profile.name"].tap()
        let rename = app.alerts["Rename profile"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5))
        let field = rename.textFields.firstMatch
        XCTAssertEqual(field.value as? String, "Trip")
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "Travel")
        rename.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Travel"].waitForExistence(timeout: 5))

        // Made active: the whole app opens it.
        app.buttons["profile.makeActive"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["profile.active"].waitForExistence(timeout: 5))
        back(app)
        XCTAssertTrue(row("Travel, active", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(row("Personal", in: app).exists)
        XCTAssertFalse(app.descendants(matching: .any)["profiles.lastProfileReason"].exists)
        closeProfiles(app)

        // Its own books: nothing in them, and the other profile's are untouched.
        XCTAssertTrue(app.descendants(matching: .any)["home.empty"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["profileMenu"].label, "Profile: Travel")
        XCTAssertEqual(app.buttons.matching(identifier: "home.operation").count, 0)
        app.buttons["profileMenu"].tap()
        app.buttons["Personal"].tap()
        XCTAssertTrue(app.buttons.matching(identifier: "home.operation").firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(hero(app).label, samplesHero)

        // Deleted with a swipe: the question says it is empty, and the last profile cannot go.
        openProfiles(app)
        let travel = row("Travel", in: app)
        XCTAssertTrue(travel.waitForExistence(timeout: 5))
        travel.swipeLeft()
        app.buttons["Delete profile"].tap()
        let question = app.alerts["Delete “Travel”?"]
        XCTAssertTrue(question.waitForExistence(timeout: 5))
        XCTAssertTrue(question.staticTexts["There is nothing in it yet."].exists)
        question.buttons["Delete"].tap()
        XCTAssertTrue(travel.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["profiles.lastProfileReason"].waitForExistence(timeout: 5))

        // The only one left: its delete is off, and its screen says why.
        row("Personal, active", in: app).tap()
        let delete = app.buttons["profile.delete"]
        for _ in 0..<6 where !(delete.exists && delete.isHittable) { app.swipeUp() }
        XCTAssertFalse(delete.isEnabled)
        XCTAssertTrue(app.descendants(matching: .any)["profile.lastProfileReason"].exists)
    }

    /// The simulator has no iCloud: the profile's screen offers no invitation and says why, the
    /// books work as ever, and there is nothing to leave or stop (stage 5c).
    @MainActor
    func testWithoutICloudSharingIsOffAndSaysWhy() {
        let app = launch()
        XCTAssertTrue(hero(app).waitForExistence(timeout: 30))
        openProfiles(app)
        row("Personal, active", in: app).tap()

        let invite = app.buttons["profile.invite"]
        reveal(invite, in: app)
        XCTAssertTrue(invite.exists)
        XCTAssertFalse(invite.isEnabled, "no iCloud, no invitation")
        XCTAssertEqual(invite.label, "Invite…")
        let note = app.staticTexts["profile.sharingNote"]
        XCTAssertTrue(note.exists)
        XCTAssertTrue(note.label.contains("sign in to iCloud"), note.label)
        XCTAssertFalse(app.buttons["profile.stopSharing"].exists)
        XCTAssertFalse(app.buttons["profile.leave"].exists)
        XCTAssertTrue(app.buttons["profile.delete"].exists)
    }

    @MainActor
    func testANewPaydayChangesTheDaysToPaydayOnHome() {
        let app = launch()
        XCTAssertTrue(hero(app).waitForExistence(timeout: 30))
        // The samples are paid on the 10th.
        XCTAssertTrue(hero(app).label.contains(Self.daysToPayday(10)), hero(app).label)
        let payday = [Self.today.day, Self.today.day % 28 + 1, 20, 5].first { Self.daysLeft(to: $0) != Self.daysLeft(to: 10) } ?? 20

        openProfiles(app)
        row("Personal, active", in: app).tap()
        let paydayRow = app.buttons["profile.payday"]
        XCTAssertTrue(paydayRow.waitForExistence(timeout: 5))
        XCTAssertTrue(paydayRow.label.contains("day 10"), paydayRow.label)
        paydayRow.tap()
        let day = app.buttons["dayGrid.\(payday)"]
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dayGrid.10"].isSelected)
        day.tap()
        XCTAssertTrue(day.waitForNonExistence(timeout: 5), "a tap picks and closes")
        XCTAssertTrue(waitFor(paydayRow, labelContaining: "day \(payday)"), paydayRow.label)
        back(app)
        closeProfiles(app)

        XCTAssertTrue(waitFor(hero(app), labelContaining: Self.daysToPayday(payday)), hero(app).label)
    }

    @MainActor
    func testACategoryOfOnesOwnIsOfferedInTheFormAndGoesAfterAsking() {
        let app = launch()
        XCTAssertTrue(hero(app).waitForExistence(timeout: 30))
        openProfiles(app)
        row("Personal, active", in: app).tap()
        XCTAssertTrue(app.buttons["profile.name"].waitForExistence(timeout: 5))
        let add = app.buttons["profile.addCategory"]
        add.swipeUpUntilHittable(in: app)
        add.tap()
        let name = app.textFields["categoryForm.name"]
        // A tap while the list still glides after the swipes can miss.
        if !name.waitForExistence(timeout: 3) { add.tap() }
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let save = app.buttons["categoryForm.save"]
        XCTAssertFalse(save.isEnabled)
        name.typeText("Cat")
        let hint = app.textFields["categoryForm.hint"]
        hint.tap()
        hint.typeText("food, vet")
        app.buttons["cat"].tap()
        save.tap()
        let category = app.buttons["profile.category"]
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        XCTAssertTrue(category.label.contains("Cat"), category.label)
        XCTAssertTrue(category.label.contains("food, vet"), category.label)
        back(app)
        closeProfiles(app)

        // The form offers it beside the built-in ones.
        let buttons = app.navigationBars.buttons.matching(identifier: "add")
        buttons.allElementsBoundByIndex.first { $0.exists && $0.isHittable }?.tap()
        let own = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "entry.category.custom.")).firstMatch
        XCTAssertTrue(own.waitForExistence(timeout: 5))
        XCTAssertEqual(own.label, "Cat")
        app.buttons["entry.cancel"].tap()

        // Deleting it asks first.
        openProfiles(app)
        row("Personal, active", in: app).tap()
        XCTAssertTrue(app.buttons["profile.name"].waitForExistence(timeout: 5))
        category.swipeUpUntilHittable(in: app)
        category.tap()
        let delete = app.buttons["categoryForm.delete"]
        if !delete.waitForExistence(timeout: 3) { category.tap() }
        delete.tap()
        let alert = app.alerts["Delete “Cat”?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts["There are no operations in it."].exists)
        alert.buttons["Delete category"].tap()
        XCTAssertTrue(category.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testAPaymentIsSetAsideOnHomeAndItsDeleteCanBeUndone() {
        let app = launch()
        XCTAssertTrue(hero(app).waitForExistence(timeout: 30))
        // A new profile from the menu opens at once, with nothing set aside.
        app.buttons["profileMenu"].tap()
        app.buttons["profileMenu.new"].tap()
        let alert = app.alerts["New profile"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.textFields.firstMatch.typeText("Trip")
        alert.buttons["Create"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["home.empty"].waitForExistence(timeout: 5))
        XCTAssertFalse(hero(app).label.contains("Set aside for payments"), hero(app).label)

        // A payment due today is due before any payday.
        openProfiles(app)
        row("Trip, active", in: app).tap()
        let add = app.buttons["profile.addPayment"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let name = app.textFields["obligationForm.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let save = app.buttons["obligationForm.save"]
        XCTAssertFalse(save.isEnabled)
        name.tap()
        name.typeText("Rent")
        let amount = app.textFields["obligationForm.amount"]
        amount.tap()
        amount.typeText("500")
        app.buttons["dayGrid.\(Self.today.day)"].tap()
        XCTAssertTrue(save.isEnabled)
        save.tap()

        let payment = app.buttons.matching(identifier: "profile.payment").firstMatch
        XCTAssertTrue(payment.waitForExistence(timeout: 5))
        XCTAssertTrue(payment.label.hasPrefix("Rent, 500 "), payment.label)
        back(app)
        closeProfiles(app)
        XCTAssertTrue(waitFor(hero(app), labelContaining: "Set aside for payments"), hero(app).label)

        // Deleted with a swipe, then back with "Undo".
        openProfiles(app)
        row("Trip, active", in: app).tap()
        XCTAssertTrue(payment.waitForExistence(timeout: 5))
        deleteBySwiping(payment, in: app)
        XCTAssertTrue(payment.waitForNonExistence(timeout: 5))
        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        // A deleted payment's toast stays 10 s, as on Android, not the 4 s of a confirmation: still
        // there after 6, so a slow runner has time to reach it (it did not, at 4).
        Thread.sleep(forTimeInterval: 6)
        XCTAssertTrue(undo.exists, "the toast of a deletion is gone after 6 s")
        undo.tap()
        XCTAssertTrue(payment.waitForExistence(timeout: 5))
        XCTAssertTrue(payment.label.hasPrefix("Rent, 500 "), payment.label)

        // Deleted for good this time: nothing is set aside any more.
        deleteBySwiping(payment, in: app)
        XCTAssertTrue(payment.waitForNonExistence(timeout: 5))
        back(app)
        closeProfiles(app)
        XCTAssertTrue(waitFor(hero(app)) { !$0.contains("Set aside for payments") }, hero(app).label)
    }

    /// Not a check: pictures of both screens, every sheet and alert, for a human. Runs only when
    /// `GOLDA_SHOTS_DIR` is set for the runner (`TEST_RUNNER_GOLDA_SHOTS_DIR=/tmp/golda-shots/P1
    /// xcodebuild test ...`); `GOLDA_SHOTS_LANG` chooses the language and `GOLDA_SHOTS_NAME`
    /// prefixes the files. Appearance and text size are the simulator's (`simctl ui`).
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
        let cancel = russian ? "Отмена" : "Cancel"
        let app = launch(language: language)
        XCTAssertTrue(hero(app).waitForExistence(timeout: 30))
        app.buttons["profileMenu"].tap()
        app.buttons["profileMenu.manage"].tap()
        XCTAssertTrue(app.buttons["profiles.done"].waitForExistence(timeout: 5))
        try shoot("profiles-one")

        // A second profile: the alert, then its own screen, fresh.
        reveal(app.buttons["profiles.add"], in: app)
        app.buttons["profiles.add"].tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        // A fresh simulator explains swipe typing once, over the keyboard.
        let tip = app.buttons[russian ? "Продолжить" : "Continue"]
        if tip.waitForExistence(timeout: 1) { tip.tap() }
        try shoot("alert-new-profile")
        alert.textFields.firstMatch.typeText(russian ? "Семья" : "Family")
        alert.buttons[russian ? "Создать" : "Create"].firstMatch.tap()
        XCTAssertTrue(app.buttons["profile.makeActive"].waitForExistence(timeout: 5))
        try shoot("profile-new")
        back(app)
        try shoot("profiles-two")

        // Its delete question, from the row's swipe.
        let family = app.buttons.matching(identifier: "profiles.row").element(boundBy: 1)
        reveal(family, in: app)
        family.swipeLeft()
        try shoot("profiles-swipe")
        app.buttons.matching(NSPredicate(format: "label == %@", russian ? "Удалить профиль" : "Delete profile")).firstMatch.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        try shoot("alert-delete-profile")
        app.alerts.firstMatch.buttons[cancel].tap()

        // The active profile's screen with the samples' income and payments.
        let personal = app.buttons.matching(identifier: "profiles.row").element(boundBy: 0)
        for _ in 0..<6 where !(personal.exists && personal.isHittable) { app.swipeDown(velocity: .slow) }
        personal.tap()
        XCTAssertTrue(app.buttons["profile.name"].waitForExistence(timeout: 5))
        try shoot("profile")
        app.buttons["profile.name"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        try shoot("alert-rename")
        app.alerts.firstMatch.buttons[cancel].tap()

        for (row, name, cancelButton) in [
            ("profile.rate", "sheet-rate", "rateSheet.cancel"),
            ("profile.taxHours", "sheet-tax-hours", "taxHoursSheet.cancel"),
            ("profile.payday", "sheet-payday", "paydaySheet.cancel"),
            ("profile.markup", "sheet-markup", "markupSheet.cancel"),
        ] {
            reveal(app.buttons[row], in: app)
            app.buttons[row].tap()
            XCTAssertTrue(app.buttons[cancelButton].waitForExistence(timeout: 5), name)
            try shoot(name)
            app.buttons[cancelButton].tap()
            XCTAssertTrue(app.buttons[cancelButton].waitForNonExistence(timeout: 5), name)
        }

        let add = app.buttons["profile.addPayment"]
        reveal(add, in: app)
        try shoot("profile-payments")
        add.tap()
        XCTAssertTrue(app.buttons["obligationForm.cancel"].waitForExistence(timeout: 5))
        try shoot("sheet-payment-new")
        app.buttons["obligationForm.cancel"].tap()
        XCTAssertTrue(app.buttons["obligationForm.cancel"].waitForNonExistence(timeout: 5))
        let payment = app.buttons.matching(identifier: "profile.payment").firstMatch
        reveal(payment, in: app)
        payment.tap()
        XCTAssertTrue(app.buttons["obligationForm.delete"].waitForExistence(timeout: 5))
        try shoot("sheet-payment-edit")
        app.buttons["obligationForm.delete"].tap()
        let undo = app.buttons[russian ? "Отменить" : "Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        try shoot("payment-undo-toast")

        for _ in 0..<8 { app.swipeUp(velocity: .slow) }
        try shoot("profile-bottom")
    }

    // MARK: Helpers

    /// Scrolls until [element] can be tapped clear of the bars: at the largest text sizes a list
    /// keeps only the rows on screen. Down first; back up only past content above the element, since
    /// a swipe down at the very top would close the sheet.
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let screen = app.frame
        func clear() -> Bool {
            element.exists && element.isHittable && element.frame.minY > screen.minY + 140 && element.frame.maxY < screen.maxY - 60
        }
        for _ in 0..<12 where !clear() {
            if element.exists, element.frame.minY <= screen.minY + 140 {
                app.swipeDown(velocity: .slow)
            } else {
                app.swipeUp(velocity: .slow)
            }
        }
    }

    /// A swipe shows the delete button; a long swipe may delete at once.
    @MainActor
    private func deleteBySwiping(_ row: XCUIElement, in app: XCUIApplication) {
        row.swipeLeft()
        let delete = app.buttons["Delete payment"]
        if delete.waitForExistence(timeout: 2) { delete.tap() }
    }

    @MainActor
    private func waitFor(_ element: XCUIElement, labelContaining text: String, timeout: TimeInterval = 5) -> Bool {
        waitFor(element, timeout: timeout) { $0.contains(text) }
    }

    /// Polls the element's label until [condition] holds: the screens follow the database a moment later.
    @MainActor
    private func waitFor(_ element: XCUIElement, timeout: TimeInterval = 5, _ condition: (String) -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !(element.exists && condition(element.label)) {
            if Date() > deadline { return false }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return true
    }

    // MARK: The calendar, as the app counts it

    /// Today where the simulator is, the zone the app counts its days in.
    private static var today: (year: Int, month: Int, day: Int) {
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: Date())
        return (parts.year!, parts.month!, parts.day!)
    }

    /// Days from today to the next [payday], as `Settings.nextPayday` counts them: the payday of a
    /// shorter month is its last day, and a payday of today means the next month's.
    private static func daysLeft(to payday: Int) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let start = calendar.startOfDay(for: Date())
        func paydayDate(monthOffset: Int) -> Date {
            let first = calendar.date(byAdding: .month, value: monthOffset, to: calendar.date(from: calendar.dateComponents([.year, .month], from: start))!)!
            let length = calendar.range(of: .day, in: .month, for: first)!.count
            return calendar.date(byAdding: .day, value: min(payday, length) - 1, to: first)!
        }
        let thisMonth = paydayDate(monthOffset: 0)
        let next = thisMonth > start ? thisMonth : paydayDate(monthOffset: 1)
        return max(calendar.dateComponents([.day], from: start, to: next).day!, 1)
    }

    /// "8 days to payday", as the hero says it in English.
    private static func daysToPayday(_ payday: Int) -> String {
        let days = daysLeft(to: payday)
        return days == 1 ? "1 day to payday" : "\(days) days to payday"
    }
}

private extension XCUIElement {
    /// Scrolls the list up until the element can be tapped: the profile screen is longer than a phone.
    @MainActor
    func swipeUpUntilHittable(in app: XCUIApplication, tries: Int = 10) {
        var left = tries
        while !(exists && isHittable), left > 0 {
            app.swipeUp()
            left -= 1
        }
    }
}
