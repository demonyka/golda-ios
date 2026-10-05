import XCTest

/// The settings on the made-up person's books (shown ₽ $ ₾, local ₾, main ₽), offline: the main
/// currency reaches Home's big number, the shown currencies flip with their fallbacks, the key is
/// saved and removed, a refresh without network says so, the rows lead where they say, and
/// "Стереть всё" goes back to onboarding.
final class SettingsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-golda.inMemory", "-golda.samples"] + extra
        app.launch()
        return app
    }

    /// The gear of the open tab: each tab has its own toolbar, and only the open one can be tapped.
    @MainActor
    private func openSettings(_ app: XCUIApplication, line: UInt = #line) {
        let gears = app.navigationBars.buttons.matching(identifier: "settings")
        XCTAssertTrue(gears.firstMatch.waitForExistence(timeout: 30), "the gear", line: line)
        guard let gear = gears.allElementsBoundByIndex.first(where: { $0.exists && $0.isHittable }) else {
            return XCTFail("no tappable gear", line: line)
        }
        gear.tap()
        XCTAssertTrue(app.buttons["settings.done"].waitForExistence(timeout: 5), "the settings", line: line)
    }

    /// Scrolls the settings until [element] can be tapped: down the list first, then back up, since
    /// at the largest text sizes a row above can be screens away too.
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, line: UInt = #line) {
        for _ in 0..<25 where !(element.exists && element.isHittable) {
            app.swipeUp(velocity: .slow)
        }
        for _ in 0..<25 where !(element.exists && element.isHittable) {
            app.swipeDown(velocity: .slow)
        }
        XCTAssertTrue(element.isHittable, "\(element) is not on screen", line: line)
    }

    /// A SwiftUI switch flips on its knob, not on its label. A tap that lands while the list still
    /// settles after a scroll is lost, so one more is made when the value has not moved.
    @MainActor
    private func flip(_ toggle: XCUIElement) {
        let before = toggle.value as? String
        for _ in 0..<2 {
            let knob = toggle.switches.firstMatch
            if knob.exists { knob.tap() } else { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
            if waitFor({ toggle.value as? String != before }, timeout: 2) { return }
        }
    }

    @MainActor
    private func waitFor(_ condition: @escaping () -> Bool, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }

    @MainActor
    func testTheMainCurrencyChangesHomesBigNumber() {
        let app = launch()
        let hero = app.descendants(matching: .any)["home.hero"]
        XCTAssertTrue(hero.waitForExistence(timeout: 30))
        XCTAssertTrue(hero.label.localizedCaseInsensitiveContains("rubles"), hero.label)

        openSettings(app)
        let main = app.buttons["settings.main"]
        XCTAssertTrue(main.label.contains("₽ RUB"), main.label)
        main.tap()
        let gel = app.buttons["settings.pick.GEL"]
        XCTAssertTrue(gel.waitForExistence(timeout: 5))
        // The main currency is picked out of the shown ones.
        XCTAssertTrue(app.buttons["settings.pick.USD"].exists)
        XCTAssertFalse(app.buttons["settings.pick.EUR"].exists)
        gel.tap()
        XCTAssertTrue(gel.waitForNonExistence(timeout: 5), "a pick closes the sheet")
        XCTAssertTrue(waitFor { main.label.contains("₾ GEL") }, main.label)

        app.buttons["settings.done"].tap()
        XCTAssertTrue(app.buttons["settings.done"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(waitFor { hero.label.localizedCaseInsensitiveContains("lari") }, hero.label)
        XCTAssertFalse(hero.label.localizedCaseInsensitiveContains("Safe to spend today. 0 "), hero.label)
    }

    @MainActor
    func testHidingTheLocalCurrencyFallsBackToTheRuble() {
        let app = launch()
        openSettings(app)
        let shown = app.buttons["settings.shown"]
        let local = app.buttons["settings.local"]
        XCTAssertTrue(shown.label.contains("₽ $ ₾"), shown.label)
        XCTAssertTrue(local.label.contains("₾ GEL"), local.label)
        XCTAssertTrue(app.descendants(matching: .any)["settings.rate.GEL"].exists)

        shown.tap()
        let ruble = app.switches["settings.shown.RUB"]
        XCTAssertTrue(ruble.waitForExistence(timeout: 5))
        XCTAssertFalse(ruble.isEnabled, "the ruble always stays")
        let lari = app.switches["settings.shown.GEL"], euro = app.switches["settings.shown.EUR"]
        XCTAssertEqual(lari.value as? String, "1")
        XCTAssertEqual(euro.value as? String, "0")
        flip(lari)
        flip(euro)
        XCTAssertTrue(waitFor { lari.value as? String == "0" && euro.value as? String == "1" })
        app.buttons["settings.shown.done"].tap()
        XCTAssertTrue(lari.waitForNonExistence(timeout: 5))

        XCTAssertTrue(waitFor { shown.label.contains("₽ $ €") }, shown.label)
        XCTAssertTrue(local.label.contains("₽ RUB"), "a hidden local currency becomes the ruble: \(local.label)")
        XCTAssertFalse(app.descendants(matching: .any)["settings.rate.GEL"].exists)
    }

    /// Every currency is there, found by searching: Argentine pesos, which the twelve of Android
    /// lacked, are shown and can then be the main currency.
    @MainActor
    func testARareCurrencyIsFoundBySearchingAndShown() {
        let app = launch()
        openSettings(app)
        let shown = app.buttons["settings.shown"]
        XCTAssertFalse(shown.label.contains("ARS"), shown.label)
        shown.tap()
        XCTAssertTrue(app.switches["settings.shown.RUB"].waitForExistence(timeout: 5))

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("ARS")
        let pesos = app.switches["settings.shown.ARS"]
        XCTAssertTrue(pesos.waitForExistence(timeout: 5))
        XCTAssertTrue(pesos.label.contains("Argentine Peso"), pesos.label)
        XCTAssertTrue(app.switches["settings.shown.RUB"].waitForNonExistence(timeout: 5), "the search narrows the list")
        XCTAssertEqual(pesos.value as? String, "0")
        flip(pesos)
        XCTAssertTrue(waitFor { pesos.value as? String == "1" })

        // The search ends first: while it is open, the bar holds its field and the system's "Close"
        // (an xmark on iOS 26), not "Done".
        let done = app.buttons["settings.shown.done"]
        if !done.isHittable { app.navigationBars.buttons["Close"].firstMatch.tap() }
        XCTAssertTrue(waitFor { done.isHittable })
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))
        XCTAssertTrue(waitFor { shown.label.contains("ARS") }, shown.label)

        let main = app.buttons["settings.main"]
        reveal(main, in: app)
        main.tap()
        XCTAssertTrue(app.buttons["settings.pick.ARS"].waitForExistence(timeout: 5), "shown, so it can be the main currency")
    }

    @MainActor
    func testTheKeyIsSavedAndRemoved() {
        let app = launch()
        openSettings(app)
        let key = app.buttons["settings.key"]
        reveal(key, in: app)
        XCTAssertTrue(key.label.contains("None"), key.label)

        key.tap()
        let field = app.secureTextFields["settings.key.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let save = app.buttons["settings.key.save"]
        XCTAssertFalse(save.isEnabled, "nothing to save yet")
        XCTAssertFalse(app.buttons["settings.key.remove"].exists, "no key to remove")
        if !app.keyboards.firstMatch.waitForExistence(timeout: 2) { field.tap() }
        field.typeText("AIza-test-key")
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        XCTAssertTrue(waitFor { key.label.contains("Saved") }, key.label)
        XCTAssertTrue(app.staticTexts["Key saved"].waitForExistence(timeout: 5))

        key.tap()
        let remove = app.buttons["settings.key.remove"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        XCTAssertTrue(remove.waitForNonExistence(timeout: 5))
        XCTAssertTrue(waitFor { key.label.contains("None") }, key.label)
        XCTAssertTrue(app.staticTexts["Key removed"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTheModelAndTheSwitchesAreKept() {
        let app = launch()
        openSettings(app)
        let model = app.buttons["settings.model"]
        reveal(model, in: app)
        XCTAssertTrue(model.label.contains("gemini-3.5-flash-lite · default"), model.label)
        model.tap()
        let field = app.textFields["settings.model.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["settings.model.default"].exists, "already the default")
        field.tap()
        field.typeText("-next")
        XCTAssertTrue(app.buttons["settings.model.default"].waitForExistence(timeout: 5))
        app.buttons["settings.model.save"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        XCTAssertTrue(waitFor { model.label.contains("gemini-3.5-flash-lite-next") }, model.label)
        XCTAssertFalse(model.label.contains("default"), model.label)

        let consent = app.switches["settings.voiceConsent"]
        reveal(consent, in: app)
        XCTAssertEqual(consent.value as? String, "0")
        flip(consent)
        XCTAssertTrue(waitFor { consent.value as? String == "1" })

        let reminder = app.switches["settings.reminder"]
        reveal(reminder, in: app)
        XCTAssertEqual(reminder.value as? String, "1")
        flip(reminder)
        XCTAssertTrue(waitFor { reminder.value as? String == "0" })

        // Closed and opened again, the settings show what was kept.
        app.buttons["settings.done"].tap()
        XCTAssertTrue(app.buttons["settings.done"].waitForNonExistence(timeout: 5))
        openSettings(app)
        reveal(app.switches["settings.reminder"], in: app)
        XCTAssertEqual(app.switches["settings.voiceConsent"].value as? String, "1")
        XCTAssertEqual(app.switches["settings.reminder"].value as? String, "0")
    }

    /// In a sheet over the settings, a tap on the page beside the field puts the keyboard away; one
    /// on the field's row, or on the menu over the text, leaves it with the field.
    @MainActor
    func testATapBesideTheModelsFieldPutsTheKeyboardAway() {
        let app = launch()
        openSettings(app)
        let model = app.buttons["settings.model"]
        reveal(model, in: app)
        model.tap()
        let field = app.textFields["settings.model.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let keyboard = app.keyboards.firstMatch
        // Typed into first, so the software keyboard is really on screen (`Walk.dismissKeyboard`).
        field.tap()
        field.typeText("-next")
        XCTAssertTrue(keyboard.exists)

        // The text's own menu works on the text: "Select All", then "Cut".
        field.press(forDuration: 1)
        let selectAll = app.menuItems["Select All"]
        XCTAssertTrue(selectAll.waitForExistence(timeout: 5))
        selectAll.tap()
        let cut = app.menuItems["Cut"]
        XCTAssertTrue(cut.waitForExistence(timeout: 5))
        cut.tap()
        XCTAssertTrue(waitFor { (field.value as? String) != "gemini-3.5-flash-lite-next" }, "the menu cut the text")
        XCTAssertTrue(keyboard.exists)
        XCTAssertTrue(hasKeyboardFocus(field))
        field.typeText("gemini-next")

        // The field's row, above its text.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()
        XCTAssertFalse(waitFor({ !keyboard.exists }, timeout: 1), "a tap on the field's row keeps the keyboard")

        // The page's margin beside the field's card.
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 6, dy: field.frame.midY)).tap()
        XCTAssertTrue(waitFor { !keyboard.exists }, "a tap beside the card puts the keyboard away")
        XCTAssertFalse(hasKeyboardFocus(field))
        XCTAssertEqual(field.value as? String, "gemini-next")
        app.buttons["settings.model.cancel"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
    }

    @MainActor
    private func hasKeyboardFocus(_ element: XCUIElement) -> Bool {
        (element.value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }

    @MainActor
    func testRatesShowTheDisplayRateAndARefreshWithoutNetworkSaysSo() {
        let app = launch()
        openSettings(app)
        let dollar = app.descendants(matching: .any)["settings.rate.USD"]
        XCTAssertTrue(dollar.waitForExistence(timeout: 5))
        // The samples bought dollars at 92 ₽, and the markup learned there brings the shown rate to
        // it; the official one is the built-in 83,2454.
        XCTAssertTrue(dollar.label.contains("1 $ = 92 ₽"), dollar.label)
        XCTAssertTrue(dollar.label.contains("CBR 83,25"), dollar.label)
        let refresh = app.buttons["settings.refreshRates"]
        XCTAssertTrue(refresh.label.contains("CBR of October 2"), refresh.label)

        refresh.tap()
        XCTAssertTrue(app.staticTexts["Didn't work. No network?"].waitForExistence(timeout: 15))
    }

    /// The markup is the profile's, but Android kept it with the rates and so people look for it
    /// here: the row shows it and a change reaches the row at once.
    @MainActor
    func testTheMarkupCanBeChangedFromTheRates() {
        let app = launch()
        openSettings(app)
        let row = app.buttons["settings.markup"]
        reveal(row, in: app)
        XCTAssertTrue(row.label.contains("%"), row.label)
        row.tap()

        let field = app.textFields["markupSheet.amount"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8))
        field.typeText("12")
        app.buttons["markupSheet.save"].tap()
        XCTAssertTrue(app.buttons["markupSheet.save"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("12 %"), row.label)
    }

    @MainActor
    func testTheRowsLeadWhereTheySay() {
        let app = launch()
        openSettings(app)

        let licences = app.buttons["settings.licences.row"]
        reveal(licences, in: app)
        let version = app.descendants(matching: .any)["settings.version"]
        XCTAssertTrue(version.label.contains("1.0.3 (4)"), version.label)
        licences.tap()
        XCTAssertTrue(app.navigationBars["Licences"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Golda"].exists)
        XCTAssertTrue(app.staticTexts["GRDB.swift"].exists)
        app.navigationBars["Licences"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(licences.waitForExistence(timeout: 5))

        // The profiles screen takes the place of the settings. `reveal` finds the row from where
        // the licences left the list; a fast swipe down that reached the top pulled the sheet away.
        let profiles = app.buttons["settings.profiles"]
        reveal(profiles, in: app)
        XCTAssertTrue(profiles.label.contains("Personal"), profiles.label)
        profiles.tap()
        XCTAssertTrue(app.navigationBars["Profiles"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["settings.done"].exists)
        app.buttons["profiles.done"].tap()
        XCTAssertTrue(app.buttons["profiles.done"].waitForNonExistence(timeout: 5))

        // The language is the system's: the row opens Golda's page in the iOS Settings.
        openSettings(app)
        let language = app.buttons["settings.language"]
        reveal(language, in: app)
        XCTAssertTrue(language.label.contains("English"), language.label)
        language.tap()
        let preferences = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        XCTAssertTrue(preferences.wait(for: .runningForeground, timeout: 10))
        preferences.terminate()
    }

    @MainActor
    func testEraseEverythingAsksAndGoesBackToOnboarding() {
        let app = launch()
        openSettings(app)
        let erase = app.buttons["settings.erase"]
        reveal(erase, in: app)

        // Cancelled, nothing goes.
        erase.tap()
        let alert = app.alerts["Erase everything?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.done"].exists)

        erase.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Erase"].tap()
        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["settings.done"].exists)

        // A new start is a fresh install: the defaults, no samples left.
        app.finishOnboarding()
        let hero = app.descendants(matching: .any)["home.hero"]
        XCTAssertTrue(hero.waitForExistence(timeout: 10))
        openSettings(app)
        XCTAssertTrue(app.buttons["settings.local"].label.contains("₽ RUB"))
        XCTAssertTrue(app.buttons["settings.shown"].label.contains("₽ $"))
    }

    /// Saves a backup through the system's panel into "On My iPhone", then restores it from there
    /// after the question. Skipped where the simulator's panels cannot be driven.
    @MainActor
    func testABackupGoesOutAndComesBack() throws {
        let app = launch()
        openSettings(app)
        let export = app.buttons["settings.export"]
        reveal(export, in: app)
        export.tap()

        // The save panel, "On My iPhone" with "Save" in its bar. It can take a while on a fresh
        // simulator, and stay blank on a slow one.
        let save = app.buttons.matching(NSPredicate(format: "label IN %@", ["Save", "Move"])).firstMatch
        guard save.waitForExistence(timeout: 30) else { throw XCTSkip("No save panel to drive here.") }
        save.tap()
        // A file of the same day from an earlier run: a second copy is written fresh, where
        // replacing the first one keeps the simulator's panel spinning.
        let keepBoth = app.buttons["Keep Both"]
        if keepBoth.waitForExistence(timeout: 2) { keepBoth.tap() }
        // The app answers a finished panel either way, with "Backup saved" or "Could not save the
        // file". Neither means the simulator's panel went away without handing the file back, which
        // it does on a slow runner (its process vanishes mid-save): nothing here to check.
        let saved = app.staticTexts["Backup saved"]
        let failed = app.staticTexts["Could not save the file"]
        guard waitFor({ saved.exists || failed.exists }, timeout: 20) else {
            throw XCTSkip("The simulator's save panel did not hand the file back.")
        }
        XCTAssertTrue(saved.exists, "the app could not write the file")

        let restore = app.buttons["settings.import"]
        reveal(restore, in: app)
        restore.tap()
        // The open panel starts on Recents; the file is where the save panel put it.
        let browse = app.buttons.matching(identifier: "Browse")
        if browse.firstMatch.waitForExistence(timeout: 10),
           let tab = browse.allElementsBoundByIndex.first(where: { $0.exists && $0.isHittable }) {
            tab.tap()
        }
        let onMyPhone = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "On My iPhone")).firstMatch
        if onMyPhone.waitForExistence(timeout: 3), onMyPhone.isHittable, !app.navigationBars["On My iPhone"].exists { onMyPhone.tap() }
        let file = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "golda-")).firstMatch
        guard file.waitForExistence(timeout: 10) else { throw XCTSkip("No open panel to drive here.") }
        file.tap()
        let question = app.alerts["Restore from the file?"]
        XCTAssertTrue(question.waitForExistence(timeout: 10))
        XCTAssertTrue(question.staticTexts["Everything in Golda now will be replaced by the file. The Gemini key stays."].exists)
        question.buttons["Restore"].tap()
        let restored = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Restored: ")).firstMatch
        XCTAssertTrue(restored.waitForExistence(timeout: 10))
        XCTAssertTrue(restored.label.contains("7 accounts"), restored.label)
    }

    /// Not a check: pictures of the settings and each sheet for a human to judge. Runs only when
    /// `GOLDA_SHOTS_DIR` is set for the runner (`TEST_RUNNER_GOLDA_SHOTS_DIR=...`); `GOLDA_SHOTS_LANG`
    /// picks the language, `GOLDA_SHOTS_NAME` prefixes the files and `GOLDA_SHOTS_SIZE=xxxl` takes
    /// the largest text size. Appearance is the simulator's (`simctl ui`).
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
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", russian ? "ru_RU" : "en_US", "-golda.inMemory", "-golda.samples"]
            + (environment["GOLDA_SHOTS_SIZE"] == "xxxl" ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] : [])
        app.launch()

        openSettings(app)
        try shoot("settings-top")
        app.buttons["settings.local"].tap()
        XCTAssertTrue(app.buttons["settings.pick.done"].waitForExistence(timeout: 5))
        try shoot("pick-local")
        app.buttons["settings.pick.done"].tap()
        XCTAssertTrue(app.buttons["settings.pick.done"].waitForNonExistence(timeout: 5))
        let main = app.buttons["settings.main"]
        reveal(main, in: app)
        main.tap()
        XCTAssertTrue(app.buttons["settings.pick.done"].waitForExistence(timeout: 5))
        try shoot("pick-main")
        app.buttons["settings.pick.done"].tap()
        XCTAssertTrue(app.buttons["settings.pick.done"].waitForNonExistence(timeout: 5))
        let shown = app.buttons["settings.shown"]
        reveal(shown, in: app)
        shown.tap()
        XCTAssertTrue(app.buttons["settings.shown.done"].waitForExistence(timeout: 5))
        try shoot("shown")
        // The rest, by name: the first screen of them, then what a search for pesos finds.
        app.swipeUp(velocity: .slow)
        app.swipeUp(velocity: .slow)
        try shoot("shown-others")
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 5) {
            search.tap()
            search.typeText(russian ? "песо" : "peso")
            try shoot("shown-search")
            let cancel = app.navigationBars.buttons[russian ? "Закрыть" : "Close"].firstMatch
            if cancel.exists && cancel.isHittable { cancel.tap() }
        }
        app.buttons["settings.shown.done"].tap()
        XCTAssertTrue(app.buttons["settings.shown.done"].waitForNonExistence(timeout: 5))

        let refresh = app.buttons["settings.refreshRates"]
        reveal(refresh, in: app)
        refresh.tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings.notice"].waitForExistence(timeout: 15))
        try shoot("rates-notice")

        let key = app.buttons["settings.key"]
        reveal(key, in: app)
        try shoot("settings-voice")
        key.tap()
        let field = app.secureTextFields["settings.key.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        try shoot("key-empty")
        if !app.keyboards.firstMatch.waitForExistence(timeout: 2) { field.tap() }
        field.typeText("AIza-test-key")
        try shoot("key-typed")
        app.buttons["settings.key.save"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        try shoot("key-saved")
        key.tap()
        XCTAssertTrue(app.buttons["settings.key.remove"].waitForExistence(timeout: 5))
        try shoot("key-replace")
        app.buttons["settings.key.cancel"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))

        let model = app.buttons["settings.model"]
        reveal(model, in: app)
        model.tap()
        let modelField = app.textFields["settings.model.field"]
        XCTAssertTrue(modelField.waitForExistence(timeout: 5))
        modelField.tap()
        modelField.typeText("-next")
        try shoot("model")
        app.buttons["settings.model.cancel"].tap()
        XCTAssertTrue(modelField.waitForNonExistence(timeout: 5))

        let reminder = app.switches["settings.reminder"]
        reveal(reminder, in: app)
        try shoot("settings-data")
        let licences = app.buttons["settings.licences.row"]
        reveal(licences, in: app)
        let erase = app.buttons["settings.erase"]
        reveal(erase, in: app)
        try shoot("settings-bottom")
        erase.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        try shoot("erase-question")
        app.alerts.firstMatch.buttons[russian ? "Отмена" : "Cancel"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForNonExistence(timeout: 5))
        reveal(licences, in: app)
        licences.tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings.licences"].waitForExistence(timeout: 5))
        try shoot("licences")
    }
}
