import XCTest

/// The account form and the debt screens on the made-up person's books, reached through the debug
/// host (`-golda.screen=accountForm`) until the Accounts tab brings the real entry points. Each row
/// of the host reads back everything the form saved, so a change can be seen landing in the model.
/// The interface runs in English; the sample names stay Russian, as they are data.
final class AccountFormUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// The language arguments go first: the defaults system reads arguments in pairs, and the
    /// single `-golda.*` flags after them must not take a language away.
    @MainActor
    private func launch(language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(\(language))", "-AppleLocale", language == "ru" ? "ru_RU" : "en_US",
            "-golda.inMemory", "-golda.samples", "-golda.screen=accountForm",
        ]
        app.launch()
        return app
    }

    @MainActor
    private func row(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.buttons["debugHost.account.\(name)"]
    }

    @MainActor
    func testCreateAnAccountThenEditItThenDeleteIt() {
        let app = launch()
        let add = app.buttons["debugHost.new"]
        XCTAssertTrue(add.waitForExistence(timeout: 30))
        add.tap()

        // A new savings account in lari (the local currency), outside the budget by default.
        let name = app.textFields["accountForm.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["New account"].exists)
        let save = app.buttons["accountForm.save"]
        XCTAssertFalse(save.isEnabled, "no name yet")
        name.tap()
        name.typeText("Alfa savings")
        XCTAssertTrue(save.isEnabled)
        app.buttons["accountForm.type.savings"].tap()
        XCTAssertTrue(app.buttons["accountForm.type.savings"].isSelected)
        let budget = app.switches["accountForm.includeInFree"]
        XCTAssertEqual(budget.value as? String, "0")

        let opening = app.textFields["accountForm.opening"]
        opening.tap()
        opening.typeText("150000")
        XCTAssertEqual(opening.value as? String, "150\u{202F}000")
        let rate = app.textFields["accountForm.rate"]
        rate.tap()
        rate.typeText("12.5")

        // A group of its own, next to the samples' "Мультивалютная".
        scrollTo(app.buttons["accountForm.group"], in: app)
        app.buttons["accountForm.group"].tap()
        app.buttons["New group…"].tap()
        let group = app.textFields["accountForm.newGroup"]
        XCTAssertTrue(group.waitForExistence(timeout: 5))
        group.tap()
        group.typeText("Alfa")
        XCTAssertEqual(save.label, "Add")
        save.tap()

        let created = row(app, "Alfa savings")
        XCTAssertTrue(created.waitForExistence(timeout: 5))
        XCTAssertEqual(created.label, "Alfa savings · SAVINGS · GEL · 150\u{202F}000 ₾ · outside · Alfa · 12.5 %")

        // Edited: a new name, a new rate and into the budget. The balance stays, and the currency
        // is shown but cannot change.
        created.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Account"].exists)
        XCTAssertFalse(app.textFields["accountForm.opening"].exists, "an existing account books no opening balance")
        XCTAssertFalse(app.buttons["accountForm.currency"].exists, "the currency is not a picker once the account exists")
        XCTAssertEqual(name.value as? String, "Alfa savings")
        // Return puts the keyboard away; while it is up, the pinned action above it covers the rate.
        replaceText(of: name, with: "Alfa deposit\n")
        replaceText(of: rate, with: "13")
        scrollTo(budget, in: app)
        flip(budget)
        XCTAssertEqual(budget.value as? String, "1")
        XCTAssertEqual(save.label, "Save")
        save.tap()

        let edited = row(app, "Alfa deposit")
        XCTAssertTrue(edited.waitForExistence(timeout: 5))
        XCTAssertEqual(edited.label, "Alfa deposit · SAVINGS · GEL · 150\u{202F}000 ₾ · in budget · Alfa · 13.0 %")
        XCTAssertFalse(row(app, "Alfa savings").exists)

        // Deleted, after the question that warns its operations go too.
        edited.tap()
        let delete = app.buttons["accountForm.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        let question = app.alerts["Delete “Alfa deposit”?"]
        XCTAssertTrue(question.waitForExistence(timeout: 5))
        XCTAssertTrue(question.staticTexts["All operations with this account go too, transfers included."].exists)
        question.buttons["Delete"].tap()
        XCTAssertTrue(eventually { !self.row(app, "Alfa deposit").exists })
        XCTAssertTrue(row(app, "Кредит").exists, "the other accounts stay")
    }

    @MainActor
    func testANewDebtIsOwedAndCancelSavesNothing() {
        let app = launch()
        let add = app.buttons["debugHost.new"]
        XCTAssertTrue(add.waitForExistence(timeout: 30))

        add.tap()
        let name = app.textFields["accountForm.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Car loan")
        app.buttons["accountForm.type.loan"].tap()
        let opening = app.textFields["accountForm.opening"]
        opening.tap()
        opening.typeText("1000")
        let payment = app.textFields["accountForm.payment"]
        payment.tap()
        payment.typeText("100")
        app.buttons["accountForm.save"].tap()

        let loan = row(app, "Car loan")
        XCTAssertTrue(loan.waitForExistence(timeout: 5))
        // What is owed is typed as is and kept as a negative balance.
        XCTAssertTrue(loan.label.hasPrefix("Car loan · LOAN · GEL · −1\u{202F}000 ₾ · outside · 100 ₾ on -"), loan.label)

        add.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Never saved")
        app.buttons["accountForm.cancel"].tap()
        XCTAssertTrue(eventually { !name.exists })
        XCTAssertFalse(row(app, "Never saved").exists)
    }

    @MainActor
    func testTheLoanPageOpensTheEarlyRepaymentCalculator() {
        let app = launch()
        let loan = app.buttons["debugHost.debt.Кредит"]
        XCTAssertTrue(loan.waitForExistence(timeout: 30))
        loan.tap()

        // 200 000 ₽ at 19,9 % paid 10 000 ₽ a month: 24,5 payments.
        let months = app.descendants(matching: .any)["debt.monthsLeft"]
        XCTAssertTrue(months.waitForExistence(timeout: 5))
        XCTAssertEqual(months.label, "Left to pay")
        XCTAssertEqual(months.value as? String, "about 25 months")

        app.buttons["debt.prepay"].tap()
        let amount = app.textFields["prepay.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        amount.typeText("50000")
        XCTAssertEqual(amount.value as? String, "50\u{202F}000")
        let sooner = app.descendants(matching: .any)["prepay.sooner"]
        XCTAssertTrue(sooner.waitForExistence(timeout: 5))
        XCTAssertEqual(sooner.value as? String, "7 months sooner")
        XCTAssertTrue(app.descendants(matching: .any)["prepay.comparison"].exists, "the samples have savings at 12 %")
        app.buttons["prepay.done"].tap()
        XCTAssertTrue(eventually { !amount.exists })
    }

    // MARK: Screenshots

    /// Not a check: pictures for a human. Runs only when `GOLDA_SHOTS_DIR` is set for the runner
    /// (`TEST_RUNNER_GOLDA_SHOTS_DIR=/tmp/golda-shots/B2 xcodebuild test ...`); `GOLDA_SHOTS_LANG`
    /// chooses the language and `GOLDA_SHOTS_NAME` prefixes the files. Appearance and text size are
    /// the simulator's (`simctl ui`).
    @MainActor
    func testScreenshotsForTheLead() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let directory = environment["GOLDA_SHOTS_DIR"] else { throw XCTSkip("Screenshots are taken on request only.") }
        let language = environment["GOLDA_SHOTS_LANG"] ?? "en"
        let prefix = environment["GOLDA_SHOTS_NAME"] ?? language
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let app = launch(language: language)
        func shoot(_ name: String) throws {
            Thread.sleep(forTimeInterval: 0.8)
            let path = (directory as NSString).appendingPathComponent("\(prefix)-\(name).png")
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: path))
        }

        let add = app.buttons["debugHost.new"]
        XCTAssertTrue(add.waitForExistence(timeout: 30))
        let cancel = app.buttons["accountForm.cancel"]

        for type in ["card", "cash", "savings", "credit", "loan"] {
            add.tap()
            let name = app.textFields["accountForm.name"]
            XCTAssertTrue(name.waitForExistence(timeout: 5))
            // Off the keyboard, which would cover half the form.
            name.typeText("\n")
            app.buttons["accountForm.type.\(type)"].tap()
            try shoot("new-\(type)")
            if type == "loan" || type == "credit" {
                let opening = app.textFields["accountForm.opening"]
                scrollTo(opening, in: app)
                // Clear of the pinned action, which the largest text sizes make tall.
                if opening.frame.maxY > app.frame.maxY - 160 { app.swipeUp(velocity: .slow) }
                opening.tap()
                if app.keyboards.firstMatch.waitForExistence(timeout: 2) { opening.typeText("150000") }
            }
            // A scroll takes the keyboard away too.
            app.swipeUp()
            try shoot("new-\(type)-more")
            if type == "credit" {
                let grace = app.switches["accountForm.grace"]
                scrollTo(grace, in: app)
                flip(grace)
                try shoot("new-credit-grace")
            }
            cancel.tap()
            XCTAssertTrue(eventually { !name.exists })
        }

        for name in ["Карта ₽", "Наличные ₾", "Накопительный", "Кредитка", "Кредит"] {
            let row = row(app, name)
            scrollTo(row, in: app, orBack: true)
            row.tap()
            XCTAssertTrue(cancel.waitForExistence(timeout: 5))
            let file = "edit-" + String(name.split(separator: " ")[0])
            try shoot(file)
            if name == "Кредит" {
                app.buttons["accountForm.delete"].tap()
                try shoot("edit-delete")
                app.alerts.firstMatch.buttons[language == "ru" ? "Отмена" : "Cancel"].tap()
            }
            app.swipeUp()
            try shoot(file + "-more")
            cancel.tap()
            XCTAssertTrue(eventually { !cancel.exists })
        }

        for name in ["Кредит", "Кредитка"] {
            let debt = app.buttons["debugHost.debt.\(name)"]
            scrollTo(debt, in: app, orBack: true)
            debt.tap()
            try shoot("debt-\(name)")
            if name == "Кредит" {
                let prepay = app.buttons["debt.prepay"]
                scrollTo(prepay, in: app)
                try shoot("debt-\(name)-more")
                prepay.tap()
                let amount = app.textFields["prepay.amount"]
                XCTAssertTrue(amount.waitForExistence(timeout: 5))
                try shoot("prepay-empty")
                amount.tap()
                if app.keyboards.firstMatch.waitForExistence(timeout: 2) { amount.typeText("50000") }
                app.swipeUp()
                try shoot("prepay")
                app.swipeUp()
                try shoot("prepay-more")
                app.buttons["prepay.done"].tap()
            }
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }

    // MARK: Helpers

    /// Clears the field from its end, then types [text]. A tap near the right edge puts the cursor
    /// after the text, wherever the field aligns it.
    @MainActor
    private func replaceText(of field: XCUIElement, with text: String) {
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        let current = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + text)
    }

    /// A toggle in a form flips at its switch, not at its label.
    @MainActor
    private func flip(_ toggle: XCUIElement) {
        // The checks read the switch's value afterwards; a screenshot run goes on without it.
        guard toggle.exists else { return }
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    }

    /// Swipes until [element] can be tapped, down the list first and, when [orBack], then back up;
    /// a list keeps rows out of sight unloaded. Only a plain screen may swipe back: in a sheet at its
    /// top that swipe closes the sheet. The keyboard goes away first, since the pinned action riding
    /// on it covers the rows it passes.
    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, orBack: Bool = false) {
        dismissKeyboard(app)
        for _ in 0..<12 where !(element.exists && element.isHittable) {
            app.swipeUp(velocity: .slow)
        }
        guard orBack else { return }
        for _ in 0..<16 where !(element.exists && element.isHittable) {
            app.swipeDown(velocity: .slow)
        }
    }

    /// A short drag on the upper part of the form, where no pinned action or keyboard is: the forms
    /// put the keyboard away as soon as they are dragged, even when there is nothing to scroll.
    @MainActor
    private func dismissKeyboard(_ app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22)))
        _ = eventually { !app.keyboards.firstMatch.exists }
    }

    /// Polls [condition] until it holds or [timeout] runs out: sheets animate away.
    @MainActor
    private func eventually(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return true
    }
}
