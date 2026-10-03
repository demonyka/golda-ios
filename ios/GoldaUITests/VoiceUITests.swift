import XCTest

/// The voice end to end on the made-up person's books, with the debug stub instead of the
/// microphone and Gemini (`-golda.voiceStub=<script>`): the stub "hears" a fixed phrase and answers
/// after a moment, so "Разбираю…" can be seen.
final class VoiceUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ script: String, language: String = "ru", consent: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-golda.inMemory", "-golda.samples", "-golda.voiceStub=\(script)",
            "-AppleLanguages", "(\(language))", "-AppleLocale", language == "ru" ? "ru_RU" : "en_US",
        ] + (consent ? [] : ["-golda.voiceStub.noConsent"])
        app.launch()
        return app
    }

    @MainActor
    private func shawarmaRows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(identifier: "home.operation").matching(NSPredicate(format: "label BEGINSWITH %@", "Шаурма,"))
    }

    @MainActor
    private func toast(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Two taps book "Шаурма 15 ₾": the toast says so with what is left for today, the row is on
    /// Home, and "Отменить" takes it away again.
    @MainActor
    func testTwoTapsBookTheNoteAndUndoTakesItBack() {
        let app = launch("shawarma")
        let mic = app.buttons["mic"]
        XCTAssertTrue(mic.waitForExistence(timeout: 30))
        XCTAssertTrue(shawarmaRows(app).firstMatch.waitForExistence(timeout: 10))
        // The samples already had one this morning.
        let before = shawarmaRows(app).count
        XCTAssertEqual(mic.label, "Сказать")

        mic.tap()
        XCTAssertEqual(mic.label, "Слушаю. Нажми, когда закончишь")
        mic.tap()
        XCTAssertEqual(mic.label, "Разбираю…")

        let message = toast(app, containing: "Шаурма 15 ₾")
        XCTAssertTrue(message.waitForExistence(timeout: 10))
        XCTAssertTrue(message.label.contains("на сегодня осталось") || message.label.contains("перерасход"), message.label)
        XCTAssertTrue(eventually { self.shawarmaRows(app).count == before + 1 }, "the new row on Home")
        XCTAssertEqual(mic.label, "Сказать")

        app.buttons["Отменить"].tap()
        XCTAssertTrue(message.waitForNonExistence(timeout: 5))
        XCTAssertTrue(eventually { self.shawarmaRows(app).count == before }, "undo removes the row")
    }

    /// Without consent the first tap asks; "Not now" records nothing, "Agree" starts the recording.
    @MainActor
    func testTheConsentScreenComesBeforeTheFirstRecording() {
        let app = launch("shawarma", language: "en", consent: false)
        let mic = app.buttons["mic"]
        XCTAssertTrue(mic.waitForExistence(timeout: 30))

        mic.tap()
        XCTAssertTrue(app.navigationBars["Voice"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Your voice goes to Google Gemini"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Gemini API key")).firstMatch.exists)
        let notNow = app.buttons["voiceConsent.notNow"]
        XCTAssertEqual(notNow.label, "Not now")
        notNow.tap()
        XCTAssertTrue(notNow.waitForNonExistence(timeout: 5))
        XCTAssertEqual(mic.label, "Say it")

        mic.tap()
        let agree = app.buttons["voiceConsent.agree"]
        XCTAssertTrue(agree.waitForExistence(timeout: 5))
        XCTAssertEqual(agree.label, "Agree")
        agree.tap()
        XCTAssertTrue(agree.waitForNonExistence(timeout: 5))
        XCTAssertTrue(eventually { mic.label == "Listening. Tap when done" }, mic.label)
        mic.tap()
        XCTAssertTrue(toast(app, containing: "Шаурма 15 ₾").waitForExistence(timeout: 10))
    }

    /// "Хочу купить наушники за 120 долларов" opens the operation form for the purchase.
    @MainActor
    func testAPurchaseToWeighUpOpensTheOperationForm() {
        let app = launch("consider", language: "en")
        let mic = app.buttons["mic"]
        XCTAssertTrue(mic.waitForExistence(timeout: 30))
        mic.tap()
        mic.tap()
        XCTAssertTrue(app.buttons["entry.cancel"].waitForExistence(timeout: 10), "the form for the purchase")
        app.buttons["entry.cancel"].tap()
        XCTAssertTrue(app.buttons["entry.cancel"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(mic.label, "Say it")
    }

    /// The mic goes idle → recording → thinking → idle. (That a tap while it thinks does nothing is
    /// checked by `VoiceMicModelTests`: here the timing of a third tap is the runner's.)
    @MainActor
    func testTheMicGoesThroughItsStates() {
        let app = launch("unclear", language: "en")
        let mic = app.buttons["mic"]
        XCTAssertTrue(mic.waitForExistence(timeout: 30))
        XCTAssertEqual(mic.label, "Say it")
        mic.tap()
        XCTAssertEqual(mic.label, "Listening. Tap when done")
        mic.tap()
        XCTAssertEqual(mic.label, "Working it out…")
        XCTAssertTrue(eventually { mic.label == "Say it" })
        XCTAssertTrue(toast(app, containing: "Couldn’t make out").waitForExistence(timeout: 5))
    }

    /// A note recorded before launch is booked "from a saved note" by the first run of the queue.
    @MainActor
    func testANoteThatWaitedIsBookedAtLaunch() {
        let app = launch("late")
        XCTAssertTrue(toast(app, containing: "Из отложенного: Шаурма 15 ₾").waitForExistence(timeout: 30))
    }

    // MARK: Screenshots

    /// Not a check: the mic in each state, the consent screen and the toasts, for a human to judge.
    /// Runs only when `GOLDA_SHOTS_DIR` is set for the runner (`TEST_RUNNER_GOLDA_SHOTS_DIR=...`);
    /// `GOLDA_SHOTS_LANG` chooses the language and `GOLDA_SHOTS_NAME` prefixes the files.
    /// Appearance is the simulator's (`simctl ui`).
    @MainActor
    func testVoiceScreenshotsForTheLead() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let directory = environment["GOLDA_SHOTS_DIR"] else { throw XCTSkip("Screenshots are taken on request only.") }
        let language = environment["GOLDA_SHOTS_LANG"] ?? "en"
        let prefix = environment["GOLDA_SHOTS_NAME"] ?? language
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        var step = 0
        func shoot(_ name: String) throws {
            Thread.sleep(forTimeInterval: 0.6)
            step += 1
            let path = (directory as NSString).appendingPathComponent(String(format: "%@-%02d-%@.png", prefix, step, name))
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: path))
        }

        // The consent screen, then the mic in its three states and the booked note.
        var app = launch("two", language: language, consent: false)
        var mic = app.buttons["mic"]
        XCTAssertTrue(mic.waitForExistence(timeout: 30))
        try shoot("mic-idle")
        mic.tap()
        XCTAssertTrue(app.buttons["voiceConsent.agree"].waitForExistence(timeout: 5))
        try shoot("consent")
        app.swipeUp()
        try shoot("consent-scrolled")
        app.buttons["voiceConsent.agree"].tap()
        XCTAssertTrue(app.buttons["voiceConsent.agree"].waitForNonExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1.2)
        try shoot("mic-recording")
        mic.tap()
        try shoot("mic-thinking")
        XCTAssertTrue(toast(app, containing: "Шаурма 15 ₾ · Кофе 8 ₾").waitForExistence(timeout: 10))
        try shoot("toast-two")
        app.terminate()

        // The other toasts, one launch each.
        for (script, name, text) in [
            ("late", "toast-late", language == "ru" ? "Из отложенного" : "From a saved note"),
            ("unclear", "toast-unclear", language == "ru" ? "Не разобрать" : "Couldn’t make out"),
            ("nokey", "toast-nokey", "Gemini"),
            ("offline", "toast-offline", language == "ru" ? "Нет связи" : "No connection"),
        ] {
            app = launch(script, language: language)
            mic = app.buttons["mic"]
            XCTAssertTrue(mic.waitForExistence(timeout: 30))
            if script != "late" {
                mic.tap()
                mic.tap()
            }
            XCTAssertTrue(toast(app, containing: text).waitForExistence(timeout: 15), name)
            try shoot(name)
            app.terminate()
        }
    }

    // MARK: Waiting

    @MainActor
    private func eventually(timeout: TimeInterval = 10, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }
}
