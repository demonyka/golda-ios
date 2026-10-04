import XCTest

/// A voice note asked for from outside the app, here by the widget's link `golda://voice` (the
/// quick action and `StartVoiceNoteIntent` post the same request): it starts as a tap on the mic
/// does, with the debug stub for the microphone and Gemini (`-golda.voiceStub=<script>`).
final class VoiceEntryUITests: XCTestCase {
    private let link = URL(string: "golda://voice")!

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func app(consent: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-golda.inMemory", "-golda.samples", "-golda.voiceStub=shawarma",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ] + (consent ? [] : ["-golda.voiceStub.noConsent"])
        return app
    }

    /// The link from outside the running app, as the widget opens it. `app.open` would relaunch
    /// the app instead, which is the cold start the other tests take.
    @MainActor
    private func openFromOutside(_ app: XCUIApplication) {
        XCUIDevice.shared.system.open(link)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }

    /// The link launches the app recording: the request waits for the books to load and the tabs.
    /// The note is booked as one said after a tap.
    @MainActor
    func testTheLinkLaunchesTheAppRecording() {
        let app = app()
        app.open(link)
        let mic = app.buttons["mic"]
        XCTAssertTrue(mic.waitForExistence(timeout: 30))
        XCTAssertTrue(eventually { mic.label == "Listening. Tap when done" }, mic.label)

        mic.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Шаурма 15 ₾")).firstMatch.waitForExistence(timeout: 10))
    }

    /// Before consent the link opens the consent screen, as the first tap does; agreeing records.
    @MainActor
    func testWithoutConsentTheLinkAsksFirst() {
        let app = app(consent: false)
        app.open(link)
        let agree = app.buttons["voiceConsent.agree"]
        XCTAssertTrue(agree.waitForExistence(timeout: 30))
        agree.tap()
        XCTAssertTrue(agree.waitForNonExistence(timeout: 5))
        let mic = app.buttons["mic"]
        XCTAssertTrue(eventually { mic.label == "Listening. Tap when done" }, mic.label)
    }

    /// In the running app a page pushed over the tab carries no mic, so it goes; asked again while
    /// it listens, the note goes on; a screen over the tabs keeps what is typed in it, and the note
    /// starts once it is closed.
    @MainActor
    func testTheRunningAppMakesWayForTheNote() {
        let app = app()
        app.launch()
        let accounts = app.tabBars.buttons["Accounts"]
        XCTAssertTrue(accounts.waitForExistence(timeout: 30))
        accounts.tap()
        let card = app.buttons.matching(identifier: "accounts.account").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        let page = app.descendants(matching: .any)["account.hero"]
        XCTAssertTrue(page.waitForExistence(timeout: 5))

        openFromOutside(app)
        let mic = app.buttons["mic"]
        XCTAssertTrue(mic.waitForExistence(timeout: 5), "back on the tab's screen")
        XCTAssertTrue(page.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["accounts.hero"].exists, "on the same tab")
        XCTAssertTrue(eventually { mic.label == "Listening. Tap when done" }, mic.label)
        openFromOutside(app)
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertEqual(mic.label, "Listening. Tap when done")
        mic.tap()
        XCTAssertTrue(eventually(timeout: 10) { mic.label == "Say it" }, mic.label)

        app.buttons["settings"].tap()
        let done = app.buttons["settings.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        openFromOutside(app)
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertTrue(done.exists, "the settings stay open")
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))
        XCTAssertTrue(eventually { mic.label == "Listening. Tap when done" }, mic.label)
    }

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
