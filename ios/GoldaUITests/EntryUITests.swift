import XCTest

/// The operation form on the made-up person's books, the way a person uses it: "+" for a new
/// expense, income or transfer, a row to edit or delete one, and "Not sure" with each of its three
/// answers. Home, Accounts and the undo toast read the result back. The interface runs in English;
/// the sample names stay Russian, as they are data.
final class EntryUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: New operations

    @MainActor
    func testAnExpenseShowsOnHomeAndTheHeroFalls() {
        let app = launch()
        let hero = app.descendants(matching: .any)["home.hero"]
        XCTAssertTrue(hero.waitForExistence(timeout: 30))
        let before = safeToday(hero.label)

        let amount = openNewEntry(app)
        XCTAssertTrue(app.navigationBars["New operation"].exists)
        let save = app.buttons["entry.save"]
        XCTAssertFalse(save.isEnabled, "no amount yet")
        // Before an amount, the line under it says what is safe today.
        XCTAssertTrue(app.staticTexts["entry.underLine"].label.hasPrefix("Safe today "), app.staticTexts["entry.underLine"].label)
        amount.typeText("25")
        XCTAssertEqual(amount.value as? String, "25")
        // Lari, the local currency, from the lari card: what it comes to in rubles and dollars.
        XCTAssertEqual(app.buttons["entry.currency"].value as? String, "₾ GEL")
        XCTAssertTrue(app.buttons["entry.account"].value as? String == "Мультивалютная GEL")
        XCTAssertTrue(app.staticTexts["entry.underLine"].label.hasPrefix("about "), app.staticTexts["entry.underLine"].label)
        let note = app.textFields["entry.note"]
        note.tap()
        note.typeText("Pizza")
        dismissKeyboard(app)
        app.buttons["entry.category.eating_out"].tap()
        XCTAssertTrue(app.buttons["entry.category.eating_out"].isSelected)
        XCTAssertEqual(save.label, "Save")
        save.tap()
        XCTAssertTrue(amount.waitForNonExistence(timeout: 5), "the form closes")

        // The toast says what was recorded, what it cost in work and what is left; "Undo" is there.
        let toast = toastText(app, containing: "Pizza · 25 ₾")
        XCTAssertTrue(toast.waitForExistence(timeout: 5))
        XCTAssertTrue(toast.label.contains("h of work"), toast.label)
        XCTAssertTrue(toast.label.contains("left for today") || toast.label.contains("over budget by"), toast.label)
        XCTAssertTrue(app.buttons["Undo"].exists)

        XCTAssertTrue(eventually { self.firstOperation(app).label.hasPrefix("Pizza, ") }, firstOperation(app).label)
        XCTAssertTrue(eventually { self.safeToday(hero.label) < before }, "the hero falls: \(before) → \(safeToday(hero.label))")
    }

    @MainActor
    func testIncomeIsRecordedInTheAccountsCurrency() {
        let app = launch()
        let amount = openNewEntry(app)
        app.segmentedControls["entry.type"].buttons["Income"].tap()
        XCTAssertFalse(app.buttons["entry.currency"].exists, "income is in the account's currency")
        XCTAssertFalse(app.staticTexts["entry.underLine"].exists, "income has no line under the number")
        XCTAssertFalse(app.buttons["entry.consider"].exists)
        amount.tap()
        amount.typeText("1000")
        XCTAssertEqual(amount.value as? String, "1\u{202F}000")
        dismissKeyboard(app)
        app.buttons["entry.category.salary"].tap()
        app.buttons["entry.save"].tap()
        XCTAssertTrue(amount.waitForNonExistence(timeout: 5))

        XCTAssertTrue(toastText(app, containing: "Salary · 1\u{202F}000 ₾").waitForExistence(timeout: 5))
        XCTAssertTrue(eventually { self.firstOperation(app).label.hasPrefix("Salary, ") }, firstOperation(app).label)
        XCTAssertTrue(firstOperation(app).label.contains("1000 Georgian laris"), firstOperation(app).label)
    }

    @MainActor
    func testATransferMovesMoneyBetweenTwoAccounts() {
        let app = launch()
        openAccounts(app)
        XCTAssertTrue(accountRow(app, "Карта ₽").label.contains("9101 Russian rubles"), accountRow(app, "Карта ₽").label)
        XCTAssertTrue(accountRow(app, "Накопительный").label.contains("330000 Russian rubles"), accountRow(app, "Накопительный").label)

        let amount = openNewEntry(app)
        app.segmentedControls["entry.type"].buttons["Transfer"].tap()
        // The last transfer's route: from the dollars to the lari cash.
        let from = app.buttons["entry.from"], to = app.buttons["entry.to"]
        XCTAssertTrue((from.value as? String ?? "").hasPrefix("Мультивалютная USD, "), from.value as? String ?? "")
        XCTAssertTrue((to.value as? String ?? "").hasPrefix("Наличные ₾, "))
        from.tap()
        menuItem(app, startingWith: "Карта ₽ · ").tap()
        to.tap()
        menuItem(app, startingWith: "Накопительный · ").tap()
        XCTAssertTrue((from.value as? String ?? "").hasPrefix("Карта ₽, "))
        XCTAssertTrue((to.value as? String ?? "").hasPrefix("Накопительный, "))
        amount.tap()
        amount.typeText("1000")
        XCTAssertFalse(app.buttons["entry.second"].exists, "rubles to rubles: what arrives is what left")
        let note = app.textFields["entry.note"]
        note.tap()
        note.typeText("Into the cushion")
        app.buttons["entry.save"].tap()
        XCTAssertTrue(amount.waitForNonExistence(timeout: 5))

        XCTAssertTrue(eventually { self.accountRow(app, "Карта ₽").label.contains("8101 Russian rubles") }, accountRow(app, "Карта ₽").label)
        XCTAssertTrue(accountRow(app, "Накопительный").label.contains("331000 Russian rubles"), accountRow(app, "Накопительный").label)
    }

    @MainActor
    func testATransferBetweenCurrenciesEstimatesWhatArrivesUntilCorrected() {
        let app = launch()
        let amount = openNewEntry(app)
        app.segmentedControls["entry.type"].buttons["Transfer"].tap()
        amount.tap()
        amount.typeText("10")
        // Dollars to lari: what arrives is an estimate until the bank's figure is typed.
        let second = app.buttons["entry.second"]
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        XCTAssertTrue(second.label.hasPrefix("Receives about "), second.label)
        second.tap()
        let field = app.textFields["entry.second.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: ((field.value as? String) ?? "").count) + "27")
        dismissKeyboard(app)
        XCTAssertTrue(eventually { second.exists })
        XCTAssertEqual(second.label, "Receives 27 Georgian laris")
        app.buttons["entry.cancel"].tap()
        XCTAssertTrue(amount.waitForNonExistence(timeout: 5))
    }

    // MARK: Existing operations

    @MainActor
    func testAnOperationIsEditedFromItsRow() {
        let app = launch()
        let coffee = firstOperation(app)
        XCTAssertTrue(coffee.waitForExistence(timeout: 30))
        XCTAssertTrue(coffee.label.hasPrefix("Кофе, "), coffee.label)
        coffee.tap()

        let amount = app.textFields["entry.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Operation"].exists)
        XCTAssertEqual(amount.value as? String, "8")
        let note = app.textFields["entry.note"]
        XCTAssertEqual(note.value as? String, "Кофе")
        XCTAssertTrue(app.buttons["entry.category.eating_out"].isSelected)
        XCTAssertFalse(app.buttons["entry.consider"].exists, "an edit is not weighed up")
        XCTAssertEqual(app.buttons["entry.save"].label, "Save")

        replaceText(of: amount, with: "9")
        replaceText(of: note, with: "Coffee to go")
        dismissKeyboard(app)
        app.buttons["entry.save"].tap()
        XCTAssertTrue(amount.waitForNonExistence(timeout: 5))

        XCTAssertTrue(eventually { self.firstOperation(app).label.hasPrefix("Coffee to go, ") }, firstOperation(app).label)
        XCTAssertTrue(firstOperation(app).label.contains("9 Georgian laris"), firstOperation(app).label)
        XCTAssertFalse(app.buttons["Undo"].exists, "an edit is not announced")
    }

    @MainActor
    func testDeletingAsksNothingAndUndoBringsItBack() {
        let app = launch()
        let first = firstOperation(app)
        XCTAssertTrue(first.waitForExistence(timeout: 30))
        let coffee = first.label
        let count = app.buttons.matching(identifier: "home.operation").count
        first.tap()
        let delete = app.buttons["entry.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        XCTAssertTrue(delete.waitForNonExistence(timeout: 5), "gone at once, no question")

        XCTAssertTrue(toastText(app, containing: "“Кофе” deleted").waitForExistence(timeout: 5))
        XCTAssertTrue(eventually { self.firstOperation(app).label.hasPrefix("Шаурма, ") }, firstOperation(app).label)
        app.buttons["Undo"].tap()
        XCTAssertTrue(eventually { self.firstOperation(app).label == coffee }, firstOperation(app).label)
        XCTAssertEqual(app.buttons.matching(identifier: "home.operation").count, count)
    }

    @MainActor
    func testAReconciliationOpensAsBookkeepingWithOnlyDelete() {
        let app = launch()
        openAccounts(app)
        accountRow(app, "Карта ₽").tap()
        XCTAssertTrue(app.descendants(matching: .any)["account.hero"].waitForExistence(timeout: 5))
        app.buttons["account.reconcile"].tap()
        let actual = app.textFields["reconcile.amount"]
        XCTAssertTrue(actual.waitForExistence(timeout: 5))
        actual.tap()
        actual.typeText("9000")
        app.buttons["reconcile.save"].tap()
        XCTAssertTrue(actual.waitForNonExistence(timeout: 5))

        let adjustment = app.buttons.matching(identifier: "account.operation").firstMatch
        XCTAssertTrue(eventually { adjustment.label.hasPrefix("Reconciliation, ") }, adjustment.label)
        adjustment.tap()
        XCTAssertTrue(app.navigationBars["Reconciliation adjustment"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["entry.amount"].exists, "nothing to edit")
        XCTAssertTrue(app.staticTexts["bookkeeping.detail"].label.hasPrefix("Карта ₽ · Today"), app.staticTexts["bookkeeping.detail"].label)
        app.buttons["bookkeeping.delete"].tap()
        XCTAssertTrue(app.navigationBars["Reconciliation adjustment"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(toastText(app, containing: "“Entry” deleted").waitForExistence(timeout: 5))
        XCTAssertTrue(eventually { !adjustment.label.hasPrefix("Reconciliation, ") }, adjustment.label)
    }

    // MARK: "Not sure"

    @MainActor
    func testNotSureThenSkipPutsTheMoneyTowardsTheMainGoal() {
        let app = launch()
        weighUp(app, amount: "50", note: "Sneakers")
        // Back to the form and in again: the amount stays.
        app.buttons["entry.back"].tap()
        XCTAssertTrue(app.segmentedControls["entry.type"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["entry.amount"].value as? String, "50")
        app.buttons["entry.consider"].tap()
        XCTAssertTrue(app.buttons["entry.skip"].waitForExistence(timeout: 5))
        app.buttons["entry.skip"].tap()
        XCTAssertTrue(app.buttons["entry.skip"].waitForNonExistence(timeout: 5))
        // The price in rubles goes towards the bike.
        let toast = toastText(app, containing: " ₽ to “Велосипед”")
        XCTAssertTrue(toast.waitForExistence(timeout: 5))
        XCTAssertTrue(toast.label.hasPrefix("+"), toast.label)
    }

    @MainActor
    func testNotSureThenThinkPutsItOnTheWishlist() {
        let app = launch()
        weighUp(app, amount: "50", note: "Sneakers")
        let think = app.buttons["entry.think"]
        // 50 ₾ is under 2 % of a month's pay: a day to think.
        XCTAssertTrue(eventually { think.label.contains("24 hours") }, think.label)
        think.tap()
        XCTAssertTrue(think.waitForNonExistence(timeout: 5))
        XCTAssertTrue(toastText(app, containing: "“Sneakers”: decide in 24 hours").waitForExistence(timeout: 5))
        XCTAssertFalse(firstOperation(app).label.hasPrefix("Sneakers, "), "nothing is spent yet")
    }

    @MainActor
    func testNotSureThenBuyRecordsTheExpense() {
        let app = launch()
        weighUp(app, amount: "50", note: "Sneakers")
        app.buttons["entry.buy"].tap()
        XCTAssertTrue(app.buttons["entry.buy"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(toastText(app, containing: "Sneakers · 50 ₾").waitForExistence(timeout: 5))
        XCTAssertTrue(eventually { self.firstOperation(app).label.hasPrefix("Sneakers, ") }, firstOperation(app).label)
    }

    // MARK: Screenshots

    /// Not a check: pictures for a human. Runs only when `GOLDA_SHOTS_DIR` is set for the runner
    /// (`TEST_RUNNER_GOLDA_SHOTS_DIR=/tmp/golda-shots/E1 xcodebuild test ...`); `GOLDA_SHOTS_LANG`
    /// chooses the language and `GOLDA_SHOTS_NAME` prefixes the files. Appearance and text size are
    /// the simulator's (`simctl ui`).
    @MainActor
    func testScreenshotsOfTheForm() throws {
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
        let app = launch(language: language)

        // A new expense: empty, then typed with a category.
        let amount = openNewEntry(app)
        try shoot("expense-empty")
        amount.typeText("24")
        dismissKeyboard(app)
        app.buttons["entry.category.eating_out"].tap()
        try shoot("expense-typed")

        // Charged to the dollar card: the estimate under the number, then the bank's figure.
        app.buttons["entry.account"].tap()
        menuItem(app, startingWith: "Мультивалютная USD").tap()
        app.buttons["entry.currency"].tap()
        try shoot("currency-menu")
        menuItem(app, startingWith: "₾ GEL").tap()
        try shoot("expense-second-amount")
        app.buttons["entry.second"].tap()
        XCTAssertTrue(app.textFields["entry.second.field"].waitForExistence(timeout: 5))
        try shoot("expense-second-editing")
        dismissKeyboard(app)

        // "Not sure", once the facts are in.
        app.buttons["entry.consider"].tap()
        XCTAssertTrue(app.buttons["entry.skip"].waitForExistence(timeout: 5))
        let hours = app.descendants(matching: .any)["entry.fact.hoursOfWork"]
        _ = eventually { hours.exists && !hours.label.hasPrefix("—") }
        try shoot("not-sure")
        app.buttons["entry.back"].tap()

        // Income and a transfer between currencies.
        app.segmentedControls["entry.type"].buttons[russian ? "Доход" : "Income"].tap()
        try shoot("income")
        app.segmentedControls["entry.type"].buttons[russian ? "Перевод" : "Transfer"].tap()
        try shoot("transfer")
        app.buttons["entry.from"].tap()
        try shoot("transfer-from-menu")
        menuItem(app, startingWith: "Карта ₽").tap()
        app.buttons["entry.date"].tap()
        let dateBar = app.navigationBars[russian ? "Дата" : "Date"]
        XCTAssertTrue(dateBar.waitForExistence(timeout: 5))
        try shoot("date-picker")
        // A tap above the calendar's sheet closes it.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        XCTAssertTrue(dateBar.waitForNonExistence(timeout: 5))
        app.buttons["entry.cancel"].tap()
        XCTAssertTrue(amount.waitForNonExistence(timeout: 5))

        // Editing a row, the toast after a delete. At the largest sizes the rows start below the hero.
        scrollTo(firstOperation(app), in: app)
        firstOperation(app).tap()
        XCTAssertTrue(app.buttons["entry.delete"].waitForExistence(timeout: 5))
        try shoot("editing")
        app.buttons["entry.delete"].tap()
        try shoot("deleted-toast")

        // A reconciliation's adjustment, read-only.
        app.tabBars.buttons[russian ? "Счета" : "Accounts"].tap()
        let card = accountRow(app, "Карта ₽")
        scrollTo(card, in: app)
        card.tap()
        scrollTo(app.buttons["account.reconcile"], in: app)
        app.buttons["account.reconcile"].tap()
        let actual = app.textFields["reconcile.amount"]
        XCTAssertTrue(actual.waitForExistence(timeout: 5))
        actual.tap()
        actual.typeText("9000")
        app.buttons["reconcile.save"].tap()
        XCTAssertTrue(actual.waitForNonExistence(timeout: 5))
        let adjustment = app.buttons.matching(identifier: "account.operation").firstMatch
        scrollTo(adjustment, in: app)
        adjustment.tap()
        XCTAssertTrue(app.buttons["bookkeeping.delete"].waitForExistence(timeout: 5))
        try shoot("bookkeeping")
    }

    // MARK: Helpers

    /// The language arguments go first: the defaults system reads arguments in pairs, and the
    /// single `-golda.*` flags after them must not take a language away.
    @MainActor
    private func launch(language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(\(language))", "-AppleLocale", language == "ru" ? "ru_RU" : "en_US",
            "-golda.inMemory", "-golda.samples",
        ]
        app.launch()
        return app
    }

    /// "+" on the open tab; returns the amount field, which has the keyboard.
    @MainActor
    @discardableResult
    private func openNewEntry(_ app: XCUIApplication) -> XCUIElement {
        let buttons = app.navigationBars.buttons.matching(identifier: "add")
        XCTAssertTrue(buttons.firstMatch.waitForExistence(timeout: 30))
        guard let add = buttons.allElementsBoundByIndex.first(where: { $0.exists && $0.isHittable }) else {
            XCTFail("no tappable +")
            return buttons.firstMatch
        }
        add.tap()
        let amount = app.textFields["entry.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "the amount has the keyboard")
        return amount
    }

    /// A new expense typed and turned into "Not sure", once its facts are in.
    @MainActor
    private func weighUp(_ app: XCUIApplication, amount text: String, note noteText: String) {
        let amount = openNewEntry(app)
        let consider = app.buttons["entry.consider"]
        XCTAssertFalse(consider.isEnabled, "nothing to weigh up without a price")
        amount.typeText(text)
        let note = app.textFields["entry.note"]
        note.tap()
        note.typeText(noteText)
        consider.tap()
        XCTAssertTrue(app.navigationBars["Not sure"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.segmentedControls["entry.type"].exists, "no type while deciding")
        XCTAssertFalse(app.buttons["entry.save"].exists)
        XCTAssertEqual(app.textFields["entry.amount"].value as? String, text, "the same amount on top")
        XCTAssertEqual(app.textFields["entry.note"].value as? String, noteText)
        let hours = app.descendants(matching: .any)["entry.fact.hoursOfWork"]
        XCTAssertTrue(eventually { hours.exists && !hours.label.hasPrefix("—") }, hours.label)
        // Hours of work at 900 ₽ on hand, a share of the bike, days of the budget.
        XCTAssertTrue(hours.label.hasSuffix(" h of work"), hours.label)
        XCTAssertTrue(app.descendants(matching: .any)["entry.fact.goalShare"].label.hasSuffix("of the goal"))
        XCTAssertTrue(app.descendants(matching: .any)["entry.fact.daysOfBudget"].exists)
    }

    @MainActor
    private func openAccounts(_ app: XCUIApplication) {
        let tab = app.tabBars.buttons["Accounts"]
        XCTAssertTrue(tab.waitForExistence(timeout: 30))
        tab.tap()
        XCTAssertTrue(app.descendants(matching: .any)["accounts.hero"].waitForExistence(timeout: 10))
    }

    /// An account's row on the Accounts tab: its VoiceOver label starts with the name.
    @MainActor
    private func accountRow(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.buttons.matching(identifier: "accounts.account").matching(NSPredicate(format: "label BEGINSWITH %@", name + ",")).firstMatch
    }

    @MainActor
    private func firstOperation(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(identifier: "home.operation").firstMatch
    }

    @MainActor
    private func menuItem(_ app: XCUIApplication, startingWith prefix: String) -> XCUIElement {
        let item = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), prefix)
        return item
    }

    @MainActor
    private func toastText(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// "Safe to spend today. 1849 Russian rubles. …": the whole rubles left, signed.
    private func safeToday(_ label: String) -> Int {
        let rest = label.drop { !$0.isNumber && $0 != "-" && $0 != "−" }
        let negative = rest.first == "-" || rest.first == "−"
        let digits = rest.drop { !$0.isNumber }.prefix { $0.isNumber }
        return (Int(digits) ?? 0) * (negative ? -1 : 1)
    }

    /// Swipes the screen up until [element] can be tapped; a list keeps rows out of sight unloaded.
    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 where !(element.exists && element.isHittable) {
            app.swipeUp(velocity: .slow)
        }
    }

    /// Clears the field from its end and types [text]. Moving the keyboard from the UIKit amount
    /// field to a SwiftUI one can take a second tap.
    @MainActor
    private func replaceText(of field: XCUIElement, with text: String) {
        let end = field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5))
        end.tap()
        if !eventually(timeout: 2, { self.hasKeyboardFocus(field) }) { end.tap() }
        XCTAssertTrue(eventually { self.hasKeyboardFocus(field) }, "the field has the keyboard")
        let current = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + text)
    }

    /// A short drag on the form puts the keyboard away: it goes as soon as the form scrolls.
    @MainActor
    private func dismissKeyboard(_ app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42))
        from.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48)))
        _ = eventually { !app.keyboards.firstMatch.exists }
    }

    @MainActor
    private func hasKeyboardFocus(_ element: XCUIElement) -> Bool {
        (element.value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }

    private func eventually(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return true
    }
}
