import XCTest

/// The account form and the debt screens on the made-up person's books, the way a person reaches
/// them: "+ Account" at the end of the Accounts tab, "Edit" on an account's page, and a debt's page
/// with its terms and the early-repayment calculator. The list and the page read the saved account
/// back. The interface runs in English; the sample names stay Russian, as they are data.
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
            "-golda.inMemory", "-golda.samples",
        ]
        app.launch()
        return app
    }

    /// The Accounts tab, once its hero is there.
    @MainActor
    private func openAccounts(_ app: XCUIApplication, language: String = "en") {
        let tab = app.tabBars.buttons[language == "ru" ? "Счета" : "Accounts"]
        XCTAssertTrue(tab.waitForExistence(timeout: 30))
        tab.tap()
        XCTAssertTrue(app.descendants(matching: .any)["accounts.hero"].waitForExistence(timeout: 10))
    }

    /// An account's row on the Accounts tab: its VoiceOver label starts with the name.
    @MainActor
    private func row(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.buttons.matching(identifier: "accounts.account").matching(NSPredicate(format: "label BEGINSWITH %@", name + ",")).firstMatch
    }

    /// "+ Account", at the end of the list.
    @MainActor
    private func openNewAccountForm(_ app: XCUIApplication) -> XCUIElement {
        let add = app.buttons["accounts.add"]
        scrollTo(add, in: app)
        add.tap()
        let name = app.textFields["accountForm.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        return name
    }

    @MainActor
    private func page(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["account.hero"]
    }

    /// Any currency, searched for in the full list: pesos, whose rate the offline samples lack, so the
    /// account also shows how a currency without a rate behaves.
    @MainActor
    func testANewAccountCanBeInAnyCurrency() {
        let app = launch()
        openAccounts(app)
        let name = openNewAccountForm(app)
        name.tap()
        name.typeText("Pesos")

        let currency = app.buttons["accountForm.currency"]
        XCTAssertTrue(currency.label.contains("₾ GEL"), currency.label)
        currency.tap()
        // The person's own currencies first, the local one ticked.
        let lari = app.buttons["accountForm.currency.GEL"]
        XCTAssertTrue(lari.waitForExistence(timeout: 5))
        XCTAssertTrue(lari.isSelected)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("peso")
        let pesos = app.buttons["accountForm.currency.ARS"]
        XCTAssertTrue(pesos.waitForExistence(timeout: 5))
        XCTAssertTrue(pesos.label.contains("Argentine Peso"), pesos.label)
        XCTAssertTrue(app.buttons["accountForm.currency.MXN"].exists)
        XCTAssertFalse(lari.exists, "the search narrows the list")
        pesos.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5), "a pick goes back to the form")
        XCTAssertTrue(eventually { currency.label.contains("ARS") }, currency.label)

        let opening = app.textFields["accountForm.opening"]
        opening.tap()
        opening.typeText("1000")
        app.buttons["accountForm.save"].tap()
        XCTAssertTrue(eventually { !name.exists }, "the form closes")
        let created = row(app, "Pesos")
        scrollTo(created, in: app)
        XCTAssertTrue(created.label.contains("Argentine pesos"), created.label)
    }

    @MainActor
    func testAddAnAccountThenEditAndDeleteItFromItsPage() {
        let app = launch()
        openAccounts(app)

        // A new savings account in lari (the local currency), outside the budget by default.
        let name = openNewAccountForm(app)
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
        XCTAssertTrue(eventually { !name.exists }, "the form closes")

        // In the list with its opening balance and the month's interest; a group of one is no group.
        let created = row(app, "Alfa savings")
        scrollTo(created, in: app)
        XCTAssertTrue(created.label.hasSuffix(", 150000 Georgian laris"), created.label)
        XCTAssertTrue(created.label.contains("Georgian laris for "), created.label)
        XCTAssertFalse(created.label.contains("Counts in"), created.label)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "Alfa", "·")).firstMatch.exists)

        // Its page, then the form from there: a new name, a new rate and into the budget. The
        // balance stays, and the currency is shown but cannot change.
        created.tap()
        XCTAssertTrue(page(app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Alfa savings"].exists)
        XCTAssertTrue(page(app).label.hasPrefix("Savings · Alfa. 150000 Georgian laris."), page(app).label)
        app.buttons["account.edit"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Account"].exists)
        XCTAssertFalse(app.textFields["accountForm.opening"].exists, "an existing account books no opening balance")
        XCTAssertFalse(app.buttons["accountForm.currency"].exists, "the currency is not a picker once the account exists")
        XCTAssertEqual(name.value as? String, "Alfa savings")
        // Return puts the keyboard away; while it is up, it covers the rate.
        replaceText(of: name, with: "Alfa deposit\n")
        replaceText(of: rate, with: "13")
        scrollTo(budget, in: app)
        flip(budget)
        XCTAssertEqual(budget.value as? String, "1")
        XCTAssertEqual(save.label, "Save")
        save.tap()
        XCTAssertTrue(eventually { !name.exists }, "the form closes")
        XCTAssertTrue(eventually { app.navigationBars["Alfa deposit"].exists }, "the page follows the new name")
        XCTAssertTrue(page(app).label.hasPrefix("Savings · Alfa. 150000 Georgian laris."), page(app).label)

        // Deleted after the question that warns its operations go too: the page goes with it.
        app.buttons["account.edit"].tap()
        let delete = app.buttons["accountForm.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        let question = app.alerts["Delete “Alfa deposit”?"]
        XCTAssertTrue(question.waitForExistence(timeout: 5))
        XCTAssertTrue(question.staticTexts["All operations with this account go too, transfers included."].exists)
        question.buttons["Delete"].tap()
        XCTAssertTrue(eventually { !self.page(app).exists && !app.navigationBars["Alfa deposit"].exists }, "the page pops")
        XCTAssertTrue(eventually { app.buttons["accounts.add"].exists }, "back on the list")
        XCTAssertFalse(row(app, "Alfa deposit").exists)
        XCTAssertFalse(row(app, "Alfa savings").exists)
        XCTAssertTrue(row(app, "Кредит").exists, "the other accounts stay")
    }

    @MainActor
    func testANewDebtIsOwedAndCancelSavesNothing() {
        let app = launch()
        openAccounts(app)

        let name = openNewAccountForm(app)
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
        XCTAssertTrue(eventually { !name.exists }, "the form closes")

        // What is owed is typed as is and kept as a negative balance; the page shows the terms.
        let loan = row(app, "Car loan")
        scrollTo(loan, in: app)
        XCTAssertTrue(loan.label.hasPrefix("Car loan, Loan, about "), loan.label)
        XCTAssertTrue(loan.label.hasSuffix("-1000 Georgian laris") || loan.label.hasSuffix("−1000 Georgian laris"), loan.label)
        loan.tap()
        XCTAssertTrue(page(app).waitForExistence(timeout: 5))
        let terms = app.descendants(matching: .any)["debt.payment"]
        XCTAssertTrue(terms.waitForExistence(timeout: 5))
        XCTAssertEqual(terms.value as? String, "100 Georgian laris")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        _ = openNewAccountForm(app)
        name.tap()
        name.typeText("Never saved")
        app.buttons["accountForm.cancel"].tap()
        XCTAssertTrue(eventually { !name.exists })
        XCTAssertFalse(row(app, "Never saved").exists)
    }

    /// D62: a credit card with nothing owed is added with its limit alone and says what is available.
    @MainActor
    func testACreditCardWithNothingOwedIsAddedWithItsLimit() {
        let app = launch()
        openAccounts(app)

        let name = openNewAccountForm(app)
        name.tap()
        name.typeText("Visa")
        app.buttons["accountForm.type.credit"].tap()
        XCTAssertTrue(app.staticTexts["Nothing owed? Leave it empty."].exists)
        let limit = app.textFields["accountForm.limit"]
        scrollTo(limit, in: app)
        limit.tap()
        limit.typeText("50000")
        app.buttons["accountForm.save"].tap()
        XCTAssertTrue(eventually { !name.exists }, "the form closes")

        let card = row(app, "Visa")
        scrollTo(card, in: app)
        XCTAssertTrue(card.label.contains("Credit card, 50000 Georgian laris available"), card.label)
        XCTAssertTrue(card.label.hasSuffix(", 0 Georgian laris"), card.label)
    }

    @MainActor
    func testTheLoanPageShowsItsTermsAndOpensTheEarlyRepaymentCalculator() {
        let app = launch()
        openAccounts(app)
        let loan = row(app, "Кредит")
        scrollTo(loan, in: app)
        loan.tap()

        // 200 000 ₽ at 19,9 % paid 10 000 ₽ a month: 24,5 payments.
        XCTAssertTrue(page(app).waitForExistence(timeout: 5))
        let months = app.descendants(matching: .any)["debt.monthsLeft"]
        XCTAssertTrue(months.waitForExistence(timeout: 5))
        XCTAssertEqual(months.label, "Left to pay")
        XCTAssertEqual(months.value as? String, "about 25 months")

        let prepay = app.buttons["debt.prepay"]
        scrollTo(prepay, in: app)
        prepay.tap()
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
        XCTAssertTrue(page(app).exists, "back on the loan's page")
    }

    @MainActor
    func testTheCreditCardPageShowsItsTermsWithoutTheCalculator() {
        let app = launch()
        openAccounts(app)
        let card = row(app, "Кредитка")
        scrollTo(card, in: app)
        XCTAssertTrue(card.label.contains("Credit card, 135000 Russian rubles available"), card.label)
        card.tap()

        XCTAssertTrue(page(app).waitForExistence(timeout: 5))
        // The samples' card lends 150 000 ₽ and 15 000 ₽ of it is owed (D62).
        let limit = app.descendants(matching: .any)["debt.limit"]
        XCTAssertTrue(limit.waitForExistence(timeout: 5))
        XCTAssertEqual(limit.label, "Credit limit")
        XCTAssertEqual(app.descendants(matching: .any)["debt.available"].value as? String, "135000 Russian rubles")
        let rate = app.descendants(matching: .any)["debt.rate"]
        XCTAssertTrue(rate.waitForExistence(timeout: 5))
        XCTAssertEqual(rate.value as? String, "29,9 % a year")
        XCTAssertTrue(app.descendants(matching: .any)["debt.payment"].exists)
        XCTAssertEqual(app.descendants(matching: .any)["debt.payment"].label, "Minimum payment")
        XCTAssertTrue(app.descendants(matching: .any)["debt.grace"].exists, "the samples' card is interest-free for 40 days")
        // A card's minimum payment has no annuity to work out.
        XCTAssertFalse(app.buttons["debt.prepay"].exists)
    }

    // MARK: The keyboard

    /// A tap on the page beside the cards puts the keyboard away; a tap on another field moves the
    /// keyboard there, and one on a field's row beside its text leaves it with the field.
    @MainActor
    func testATapBesideTheCardsPutsTheKeyboardAway() {
        let app = launch()
        openAccounts(app)
        let keyboard = app.keyboards.firstMatch
        let name = openNewAccountForm(app)
        // Typed into first, so the software keyboard is really on screen (`Walk.dismissKeyboard`).
        name.tap()
        name.typeText("Wallet")
        let opening = app.textFields["accountForm.opening"]
        opening.tap()
        XCTAssertTrue(eventually { self.hasKeyboardFocus(opening) }, "the amount takes the keyboard from the name")
        XCTAssertFalse(hasKeyboardFocus(name))
        XCTAssertTrue(keyboard.exists)
        opening.typeText("500")

        // The amount's row, far to the side of its digits.
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 40, dy: opening.frame.midY)).tap()
        XCTAssertFalse(eventually(timeout: 1) { !keyboard.exists }, "a tap on the field's row keeps the keyboard")
        XCTAssertTrue(hasKeyboardFocus(opening))

        // The page's margin beside the amount's card.
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 6, dy: opening.frame.midY)).tap()
        XCTAssertTrue(eventually { !keyboard.exists }, "a tap beside the cards puts the keyboard away")
        XCTAssertFalse(hasKeyboardFocus(opening))
        XCTAssertEqual(opening.value as? String, "500")
        XCTAssertEqual(name.value as? String, "Wallet")
    }

    // MARK: Screenshots

    /// Not a check: pictures of the whole flow for a human. Runs only when `GOLDA_SHOTS_DIR` is set
    /// for the runner (`TEST_RUNNER_GOLDA_SHOTS_DIR=/tmp/golda-shots/B1b xcodebuild test ...`);
    /// `GOLDA_SHOTS_LANG` chooses the language and `GOLDA_SHOTS_NAME` prefixes the files.
    /// Appearance and text size are the simulator's (`simctl ui`).
    @MainActor
    func testScreenshotsForTheLead() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let directory = environment["GOLDA_SHOTS_DIR"] else { throw XCTSkip("Screenshots are taken on request only.") }
        let language = environment["GOLDA_SHOTS_LANG"] ?? "en"
        let russian = language == "ru"
        let prefix = environment["GOLDA_SHOTS_NAME"] ?? language
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let app = launch(language: language)
        var step = 0
        func shoot(_ name: String) throws {
            Thread.sleep(forTimeInterval: 0.8)
            step += 1
            let path = (directory as NSString).appendingPathComponent(String(format: "%@-%02d-%@.png", prefix, step, name))
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: path))
        }

        // "+ Счёт" at the end of the list, and the form it opens.
        openAccounts(app, language: language)
        scrollTo(app.buttons["accounts.add"], in: app)
        try shoot("list-add-row")
        let name = openNewAccountForm(app)
        try shoot("form-new")
        name.typeText(russian ? "Альфа вклад" : "Alfa savings")
        app.buttons["accountForm.type.savings"].tap()
        let opening = app.textFields["accountForm.opening"]
        opening.tap()
        opening.typeText("150000")
        let rate = app.textFields["accountForm.rate"]
        rate.tap()
        rate.typeText("12")
        dismissKeyboard(app)
        try shoot("form-filled")
        app.buttons["accountForm.save"].tap()
        XCTAssertTrue(eventually { !name.exists })

        // The list with it, its page, the form from the page, and the delete question.
        let created = row(app, russian ? "Альфа вклад" : "Alfa savings")
        scrollTo(created, in: app)
        try shoot("list-with-new")
        created.tap()
        XCTAssertTrue(page(app).waitForExistence(timeout: 5))
        try shoot("page-new")
        app.buttons["account.edit"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        try shoot("form-edit")
        app.buttons["accountForm.delete"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        try shoot("form-delete-question")
        app.alerts.firstMatch.buttons[russian ? "Удалить" : "Delete"].tap()
        XCTAssertTrue(eventually { !self.page(app).exists })
        try shoot("list-after-delete")

        // The debts: the credit card's terms, the loan's, and the calculator.
        for debt in ["Кредитка", "Кредит"] {
            let account = row(app, debt)
            scrollTo(account, in: app, orBack: true)
            account.tap()
            XCTAssertTrue(page(app).waitForExistence(timeout: 5))
            try shoot(debt == "Кредит" ? "page-loan" : "page-credit")
            app.swipeUp()
            try shoot(debt == "Кредит" ? "page-loan-terms" : "page-credit-terms")
            if debt == "Кредит" {
                let prepay = app.buttons["debt.prepay"]
                scrollTo(prepay, in: app)
                prepay.tap()
                let amount = app.textFields["prepay.amount"]
                XCTAssertTrue(amount.waitForExistence(timeout: 5))
                amount.tap()
                if app.keyboards.firstMatch.waitForExistence(timeout: 2) { amount.typeText("50000") }
                try shoot("prepay")
                dismissKeyboard(app)
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

    @MainActor
    private func hasKeyboardFocus(_ element: XCUIElement) -> Bool {
        (element.value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }

    /// A toggle in a form flips at its switch, not at its label.
    @MainActor
    private func flip(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    }

    /// Swipes until [element] can be tapped, down the list first and, when [orBack], then back up;
    /// a list keeps rows out of sight unloaded. Only a plain screen may swipe back: in a sheet at its
    /// top that swipe closes the sheet. The keyboard goes away first, since it covers the rows it passes.
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

    /// A short drag on the upper part of the form, where the keyboard is not: the forms
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
