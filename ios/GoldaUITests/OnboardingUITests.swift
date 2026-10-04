import XCTest

/// The first launch on a fresh install: income, currencies, accounts, then Home. What the steps set
/// up is there afterwards, the buttons at the bottom follow the step, and "Назад" keeps what was
/// chosen. The interface runs in English unless a test says otherwise, so elements are found by
/// their titles.
final class OnboardingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testTheThreeStepsSetUpTheBooksAndOpenHome() {
        let walk = Walk(samples: false, shotsName: "onboarding")
        let app = walk.app
        let next = app.buttons["onboarding.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["onboarding.back"].exists, "nothing is before the first step")
        walk.shoot("income")

        // Income: the first profile is made as the screen opens, so a sheet can change it at once.
        let payday = app.buttons["onboarding.payday"]
        XCTAssertTrue(payday.waitForExistence(timeout: 10))
        let hourNet = walk.any("onboarding.hourNet")
        XCTAssertTrue(hourNet.exists && hourNet.label.contains("₽"), hourNet.label)
        payday.tap()
        let day = app.buttons["dayGrid.20"]
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        day.tap()
        XCTAssertTrue(day.waitForNonExistence(timeout: 5))
        XCTAssertTrue(waitUntil { payday.label.contains("day 20") }, payday.label)
        next.tap()

        // Currencies: lari shown and local.
        let lari = app.switches["onboarding.shown.GEL"]
        XCTAssertTrue(lari.waitForExistence(timeout: 5))
        XCTAssertEqual(lari.value as? String, "0")
        XCTAssertFalse(app.switches["onboarding.shown.RUB"].isEnabled, "the ruble always stays")
        walk.flip(lari)
        XCTAssertTrue(waitUntil { lari.value as? String == "1" })
        let local = app.buttons["onboarding.local"]
        reveal(local, above: next, in: app)
        XCTAssertTrue(local.label.contains("₽ RUB"), local.label)
        local.tap()
        let lariChoice = app.buttons.matching(NSPredicate(format: "label == %@", "₾ GEL")).firstMatch
        XCTAssertTrue(lariChoice.waitForExistence(timeout: 5))
        lariChoice.tap()
        XCTAssertTrue(waitUntil { local.label.contains("₾ GEL") }, local.label)
        // The main currency, out of the shown ones too: the big numbers in lari from the first day.
        let main = app.buttons["onboarding.main"]
        reveal(main, above: next, in: app)
        XCTAssertTrue(main.label.contains("₽ RUB"), main.label)
        main.tap()
        let mainLari = app.buttons.matching(NSPredicate(format: "label == %@", "₾ GEL")).firstMatch
        XCTAssertTrue(mainLari.waitForExistence(timeout: 5))
        mainLari.tap()
        XCTAssertTrue(waitUntil { main.label.contains("₾ GEL") }, main.label)
        walk.shoot("currencies")
        next.tap()

        // Accounts: a card with 30 000 ₽, made with the account form of the Accounts tab.
        let add = app.buttons["onboarding.addAccount"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "onboarding.account").count, 0)
        add.tap()
        let name = app.textFields["accountForm.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        walk.type("Card", into: name)
        walk.type("30000", into: app.textFields["accountForm.opening"])
        app.buttons["accountForm.save"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5))
        let card = app.buttons.matching(identifier: "onboarding.account").matching(NSPredicate(format: "label BEGINSWITH %@", "Card,")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        walk.shoot("accounts")

        // "Назад" keeps the choices.
        app.buttons["onboarding.back"].tap()
        XCTAssertTrue(lari.waitForExistence(timeout: 5))
        XCTAssertEqual(lari.value as? String, "1")
        reveal(local, above: next, in: app)
        XCTAssertTrue(local.label.contains("₾ GEL"), local.label)
        next.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))

        // "Готово": Home, with something to spend today, and the choices in place.
        app.buttons["onboarding.done"].tap()
        XCTAssertTrue(walk.homeHero.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["onboarding.done"].exists)
        XCTAssertTrue(waitUntil { (firstWholeNumber(in: walk.homeHero.label) ?? 0) > 0 }, walk.homeHero.label)
        XCTAssertTrue(walk.homeHero.label.localizedCaseInsensitiveContains("lari"), walk.homeHero.label)
        walk.openTab("Accounts", "Счета", waitingFor: "accounts.hero")
        XCTAssertTrue(walk.accountRow("Card").waitForExistence(timeout: 5))
    }

    /// At the largest text size the bar with "Next" covers the first step's last row until the list
    /// is scrolled, as a toolbar over a list does; the row always scrolls clear of it. The text size
    /// is this launch's only, so the simulator's own setting stays.
    @MainActor
    func testAtTheLargestSizeTheLastRowScrollsClearOfTheBar() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-golda.inMemory",
        ]
        app.launch()
        let next = app.buttons["onboarding.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 30))
        let payday = app.buttons["onboarding.payday"]
        reveal(payday, above: next, in: app)
        XCTAssertTrue(payday.isHittable)
    }

    /// Scrolls the step's list until [element] stands clear of the bottom bar: the list draws only the
    /// rows near the screen, and a row under the bar would be tapped through it.
    @MainActor
    private func reveal(_ element: XCUIElement, above bar: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<6 where !(element.exists && element.frame.maxY < bar.frame.minY - 8) {
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(element.exists && element.frame.maxY < bar.frame.minY - 8, "\(element) is not clear of the bar", file: file, line: line)
    }

    /// "Дальше" on the first two steps, "Готово" on the last; "Назад" from the second on.
    @MainActor
    func testTheButtonsFollowTheStep() {
        let walk = Walk(samples: false, shotsName: "onboarding-buttons")
        let app = walk.app
        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 30))
        XCTAssertEqual(app.buttons["onboarding.next"].label, "Next")

        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.buttons["onboarding.back"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["onboarding.next"].label, "Next")

        app.buttons["onboarding.next"].tap()
        let done = app.buttons["onboarding.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertEqual(done.label, "Done")
        XCTAssertFalse(app.buttons["onboarding.next"].exists)

        app.buttons["onboarding.back"].tap()
        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 5))
        app.buttons["onboarding.back"].tap()
        XCTAssertTrue(app.buttons["onboarding.back"].waitForNonExistence(timeout: 5), "the first step has no way back")
    }

    @MainActor
    func testTheStepsSpeakRussian() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU", "-golda.inMemory"]
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 30))
        XCTAssertEqual(app.buttons["onboarding.next"].label, "Дальше")
        XCTAssertTrue(app.staticTexts["Доход"].exists)

        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.staticTexts["Валюты"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["onboarding.back"].label, "Назад")
        // The ruble is no longer said to be the main one: the main currency is picked here.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "итоги — в основной")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Рубль — основная")).firstMatch.exists)
        XCTAssertTrue(app.switches["onboarding.shown.GEL"].label.contains("Грузинский лари"), app.switches["onboarding.shown.GEL"].label)

        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.staticTexts["Счета"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["onboarding.done"].label, "Готово")
    }
}
