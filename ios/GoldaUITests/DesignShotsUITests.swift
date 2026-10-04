import XCTest

/// Not a check: pictures of every button, alert and sheet for a human to judge the colours by (D34).
/// Runs only when `GOLDA_SHOTS_DIR` is set for the runner
/// (`TEST_RUNNER_GOLDA_SHOTS_DIR=/tmp/golda-shots/D xcodebuild test ...`); `GOLDA_SHOTS_LANG`
/// chooses the language and `GOLDA_SHOTS_NAME` prefixes the files. Appearance is the simulator's
/// (`simctl ui`).
final class DesignShotsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

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
        func launch(samples: Bool) -> XCUIApplication {
            let app = XCUIApplication()
            // The voice stub, so the mic records and thinks without a microphone or a network.
            app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", russian ? "ru_RU" : "en_US", "-golda.inMemory", "-golda.voiceStub=shawarma"]
                + (samples ? ["-golda.samples"] : [])
            app.launch()
            return app
        }

        // A fresh install: the three steps of onboarding.
        var app = launch(samples: false)
        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 30))
        try shoot("onboarding-income")
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.switches["onboarding.shown.USD"].waitForExistence(timeout: 5))
        try shoot("onboarding-currencies")
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.buttons["onboarding.addAccount"].waitForExistence(timeout: 5))
        try shoot("onboarding-accounts")
        app.terminate()

        // Home with the mic in its three states.
        app = launch(samples: true)
        let mic = app.buttons["mic"]
        XCTAssertTrue(mic.waitForExistence(timeout: 30))
        Thread.sleep(forTimeInterval: 1)
        try shoot("home-mic")
        mic.tap()
        try shoot("mic-recording")
        mic.tap()
        try shoot("mic-thinking")
        mic.tap()

        // The new-profile alert, empty and then with a name.
        app.navigationBars.buttons["profileMenu"].firstMatch.tap()
        try shoot("profile-menu")
        app.buttons["profileMenu.new"].tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        // A fresh simulator explains swipe typing once, over the keyboard.
        let tip = app.buttons[russian ? "Продолжить" : "Continue"]
        if tip.waitForExistence(timeout: 1) { tip.tap() }
        try shoot("profile-alert-empty")
        alert.textFields.firstMatch.typeText(russian ? "Семья" : "Family")
        try shoot("profile-alert-named")
        alert.buttons[russian ? "Отмена" : "Cancel"].tap()

        // The operation form and the settings stand-ins.
        app.navigationBars.buttons["add"].firstMatch.tap()
        XCTAssertTrue(app.buttons["entry.cancel"].waitForExistence(timeout: 5))
        try shoot("entry-new")
        app.buttons["entry.cancel"].tap()
        app.buttons.matching(identifier: "home.operation").firstMatch.tap()
        XCTAssertTrue(app.buttons["entry.cancel"].waitForExistence(timeout: 5))
        try shoot("entry-editing")
        app.buttons["entry.cancel"].tap()
        app.navigationBars.buttons["settings"].firstMatch.tap()
        XCTAssertTrue(app.buttons["settings.done"].waitForExistence(timeout: 5))
        try shoot("settings")
        app.buttons["settings.done"].tap()

        // Accounts: the list with "+ Account", the new form empty and filled, then an account's
        // page, its form with the trash, the delete question, and the reconcile sheet.
        app.tabBars.buttons[russian ? "Счета" : "Accounts"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["accounts.hero"].waitForExistence(timeout: 10))
        let add = app.buttons["accounts.add"]
        for _ in 0..<8 where !(add.exists && add.isHittable) { app.swipeUp(velocity: .slow) }
        try shoot("accounts-add-row")
        add.tap()
        let name = app.textFields["accountForm.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        try shoot("account-form-empty")
        name.typeText(russian ? "Альфа вклад" : "Alfa savings")
        try shoot("account-form-named")
        app.buttons["accountForm.cancel"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5))
        for _ in 0..<8 { app.swipeDown(velocity: .fast) }

        let card = app.buttons.matching(identifier: "accounts.account").matching(NSPredicate(format: "label BEGINSWITH %@", "Карта ₽,")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertTrue(app.descendants(matching: .any)["account.hero"].waitForExistence(timeout: 5))
        try shoot("account-page")
        app.buttons["account.edit"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        try shoot("account-form-edit")
        app.buttons["accountForm.delete"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        try shoot("account-delete-question")
        app.alerts.firstMatch.buttons[russian ? "Отмена" : "Cancel"].tap()
        app.buttons["accountForm.cancel"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5))

        app.buttons["account.reconcile"].tap()
        let amount = app.textFields["reconcile.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        try shoot("reconcile")
        amount.tap()
        amount.typeText("9000")
        try shoot("reconcile-typed")
        app.buttons["reconcile.cancel"].tap()
        XCTAssertTrue(amount.waitForNonExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // The loan's early-repayment calculator.
        let loan = app.buttons.matching(identifier: "accounts.account").matching(NSPredicate(format: "label BEGINSWITH %@", "Кредит,")).firstMatch
        for _ in 0..<8 where !(loan.exists && loan.isHittable) { app.swipeUp(velocity: .slow) }
        loan.tap()
        let prepay = app.buttons["debt.prepay"]
        for _ in 0..<8 where !(prepay.exists && prepay.isHittable) { app.swipeUp(velocity: .slow) }
        // Clear of the tab bar, which the row is still "hittable" under.
        app.swipeUp(velocity: .slow)
        try shoot("loan-terms")
        prepay.tap()
        let prepayAmount = app.textFields["prepay.amount"]
        XCTAssertTrue(prepayAmount.waitForExistence(timeout: 5))
        if app.keyboards.firstMatch.waitForExistence(timeout: 2) { prepayAmount.typeText("50000") }
        try shoot("prepay")
        app.buttons["prepay.done"].tap()
    }

    /// Not a check either: every screen of `DESIGN.md` → «Экраны» for the stage 2 audit, run once
    /// per language, appearance and text size (`simctl ui … appearance` / `content_size`). Beside
    /// each picture lies the accessibility tree (`.txt`), so a button without a spoken label shows
    /// up in a search. A screen that cannot be reached is recorded and the walk goes on, so one
    /// run at a large size still pictures the rest.
    @MainActor
    func testEveryScreenForTheAudit() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let directory = environment["GOLDA_SHOTS_DIR"] else { throw XCTSkip("Screenshots are taken on request only.") }
        continueAfterFailure = true
        let prefix = (environment["GOLDA_SHOTS_NAME"] ?? environment["GOLDA_SHOTS_LANG"] ?? "en") + "-audit"
        var step = 0
        func shoot(_ walk: Walk, _ name: String) {
            Thread.sleep(forTimeInterval: 0.8)
            step += 1
            let base = (directory as NSString).appendingPathComponent(String(format: "%@-%02d-%@", prefix, step, name))
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: base + ".png"))
            try? walk.app.debugDescription.write(toFile: base + ".txt", atomically: true, encoding: .utf8)
        }
        func appear(_ element: XCUIElement, _ name: String) -> Bool {
            if element.waitForExistence(timeout: 8) { return true }
            XCTFail("not reached: \(name)")
            return false
        }
        func toTop(_ walk: Walk) {
            for _ in 0..<6 { walk.app.swipeDown(velocity: .fast) }
        }

        // Onboarding, on a fresh install.
        var walk = Walk(samples: false, shotsName: "audit")
        for (index, name) in ["onboarding-income", "onboarding-currencies", "onboarding-accounts"].enumerated() {
            let next = walk.app.buttons[index == 2 ? "onboarding.done" : "onboarding.next"]
            guard appear(next, name) else { break }
            shoot(walk, name)
            // The step's last row clears the bar with "Next" over the list.
            walk.app.swipeUp(velocity: .fast)
            walk.app.swipeUp(velocity: .fast)
            shoot(walk, name + "-bottom")
            if index < 2 { next.tapIfThere() }
        }
        walk.app.terminate()

        // The voice consent, on the made-up person's books.
        walk = Walk(extra: ["-golda.voiceStub=shawarma", "-golda.voiceStub.noConsent"], shotsName: "audit")
        let app = walk.app
        if appear(walk.homeHero, "home") {
            shoot(walk, "home")
            app.swipeUp(velocity: .slow)
            shoot(walk, "home-scrolled")
            toTop(walk)
        }
        walk.mic.tapIfThere()
        if appear(app.buttons["voiceConsent.notNow"], "consent") {
            shoot(walk, "voice-consent")
            app.buttons["voiceConsent.notNow"].tapIfThere()
        }

        // The operation form: an operation of Home, then a new one in each type, then "Not sure".
        // At the largest sizes the hero fills Home and the first row is below the screen.
        let operation = walk.operations.firstMatch
        walk.reveal(operation)
        if appear(operation, "operation") {
            operation.tapIfThere()
            if appear(app.buttons["entry.cancel"], "entry-edit") {
                shoot(walk, "entry-edit")
                app.buttons["entry.cancel"].tapIfThere()
            }
        }
        toTop(walk)
        walk.tapToolbar("add")
        let amount = app.textFields["entry.amount"]
        if appear(amount, "entry-new") {
            amount.typeText("12")
            shoot(walk, "entry-new")
            walk.dismissKeyboard()
            shoot(walk, "entry-new-no-keyboard")
            // The last category clears "Not sure" over the form.
            app.swipeUp(velocity: .fast)
            app.swipeUp(velocity: .fast)
            shoot(walk, "entry-new-bottom")
            let types = app.segmentedControls["entry.type"]
            walk.reveal(types)
            for (english, russian) in [("Income", "Доход"), ("Transfer", "Перевод")] {
                types.buttons[walk.text(english, russian)].tapIfThere()
                shoot(walk, "entry-" + english.lowercased())
            }
            types.buttons[walk.text("Expense", "Расход")].tapIfThere()
            let consider = app.buttons["entry.consider"]
            walk.reveal(consider)
            consider.tapIfThere()
            if appear(app.buttons["entry.buy"], "entry-not-sure") {
                shoot(walk, "entry-not-sure")
                // The note at the end clears the three answers over the facts.
                app.swipeUp(velocity: .fast)
                app.swipeUp(velocity: .fast)
                shoot(walk, "entry-not-sure-bottom")
            }
            app.buttons["entry.back"].tapIfThere()
            app.buttons["entry.cancel"].tapIfThere()
        }

        // Accounts, a new account's form, an account's page with its form and reconcile, the
        // bookkeeping sheet of the adjustment, and the loan with its calculator.
        walk.openTab("Accounts", "Счета", waitingFor: "accounts.hero")
        shoot(walk, "accounts")
        app.swipeUp(velocity: .slow)
        shoot(walk, "accounts-scrolled")
        let add = app.buttons["accounts.add"]
        walk.reveal(add)
        shoot(walk, "accounts-bottom")
        add.tapIfThere()
        if appear(app.buttons["accountForm.cancel"], "account-form-new") {
            walk.dismissKeyboard()
            shoot(walk, "account-form-new")
            app.buttons["accountForm.cancel"].tapIfThere()
        }
        toTop(walk)
        let card = walk.accountRow("Карта ₽")
        walk.reveal(card)
        card.tapIfThere()
        if appear(walk.any("account.hero"), "account-page") {
            shoot(walk, "account-page")
            app.buttons["account.edit"].tapIfThere()
            if appear(app.buttons["accountForm.cancel"], "account-form-edit") {
                shoot(walk, "account-form-edit")
                app.buttons["accountForm.cancel"].tapIfThere()
            }
            app.buttons["account.reconcile"].tapIfThere()
            let actual = app.textFields["reconcile.amount"]
            if appear(actual, "reconcile") {
                walk.type("9000", into: actual)
                shoot(walk, "reconcile")
                app.buttons["reconcile.save"].tapIfThere()
                let adjustment = app.buttons.matching(identifier: "account.operation").firstMatch
                if appear(adjustment, "bookkeeping") {
                    walk.reveal(adjustment)
                    adjustment.tapIfThere()
                    if appear(app.buttons["bookkeeping.delete"], "bookkeeping") {
                        shoot(walk, "bookkeeping")
                        app.buttons["entry.cancel"].tapIfThere()
                    }
                }
            }
            walk.back()
        }
        let loan = walk.accountRow("Кредит")
        walk.reveal(loan)
        loan.tapIfThere()
        if appear(walk.any("account.hero"), "loan") {
            shoot(walk, "loan")
            let prepay = app.buttons["debt.prepay"]
            walk.reveal(prepay)
            shoot(walk, "loan-terms")
            prepay.tapIfThere()
            if appear(app.buttons["prepay.done"], "prepay") {
                shoot(walk, "prepay")
                app.buttons["prepay.done"].tapIfThere()
            }
            walk.back()
        }

        // Goals with the goal form.
        walk.openTab("Goals", "Цели", waitingFor: "goals.hero")
        shoot(walk, "goals")
        app.swipeUp(velocity: .slow)
        shoot(walk, "goals-scrolled")
        let addGoal = app.buttons["goals.add"]
        walk.reveal(addGoal)
        shoot(walk, "goals-bottom")
        addGoal.tapIfThere()
        if appear(app.buttons["goalForm.cancel"], "goal-form") {
            walk.dismissKeyboard()
            shoot(walk, "goal-form")
            app.buttons["goalForm.cancel"].tapIfThere()
        }

        // Insights down to its last card, and a range of one's own.
        walk.openTab("Insights", "Аналитика", waitingFor: "insights.ring")
        shoot(walk, "insights")
        for index in 1...3 {
            app.swipeUp(velocity: .slow)
            shoot(walk, "insights-scrolled-\(index)")
        }
        toTop(walk)
        let period = app.segmentedControls["insights.period"]
        if appear(period, "insights-range") {
            period.buttons.element(boundBy: period.buttons.count - 1).tapIfThere()
            if appear(app.buttons["insights.range.cancel"], "insights-range") {
                shoot(walk, "insights-range")
                app.buttons["insights.range.cancel"].tapIfThere()
            }
        }

        // The settings, a pick sheet and the licences.
        walk.openTab("Home", "Главная", waitingFor: "home.hero")
        walk.tapToolbar("settings")
        if appear(app.buttons["settings.done"], "settings") {
            shoot(walk, "settings")
            app.buttons["settings.main"].tapIfThere()
            if appear(app.buttons["settings.pick.done"], "settings-pick") {
                shoot(walk, "settings-pick")
                app.buttons["settings.pick.done"].tapIfThere()
            }
            app.swipeUp(velocity: .slow)
            shoot(walk, "settings-scrolled")
            let licences = app.buttons["settings.licences.row"]
            walk.reveal(licences)
            shoot(walk, "settings-bottom")
            licences.tapIfThere()
            if appear(walk.any("settings.licences"), "licences") {
                shoot(walk, "licences")
                walk.back()
            }
            app.buttons["settings.done"].tapIfThere()
        }

        // The profiles and a profile's screen.
        app.buttons["profileMenu"].tapIfThere()
        if appear(app.buttons["profileMenu.manage"], "profile-menu") {
            shoot(walk, "profile-menu")
            app.buttons["profileMenu.manage"].tapIfThere()
        }
        if appear(app.buttons["profiles.done"], "profiles") {
            shoot(walk, "profiles")
            app.buttons.matching(identifier: "profiles.row").firstMatch.tapIfThere()
            if appear(app.buttons["profile.name"], "profile") {
                shoot(walk, "profile")
                app.swipeUp(velocity: .slow)
                shoot(walk, "profile-scrolled")
            }
        }
    }
}

private extension XCUIElement {
    /// A tap that records a miss instead of ending the walk: a tap on a missing element stops a
    /// test even with `continueAfterFailure`, and the audit should picture the rest.
    @MainActor
    func tapIfThere(file: StaticString = #filePath, line: UInt = #line) {
        guard waitForExistence(timeout: 5), isHittable else {
            return XCTFail("not tappable: \(self)", file: file, line: line)
        }
        tap()
    }
}
