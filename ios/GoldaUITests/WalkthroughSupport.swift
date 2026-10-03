import XCTest

/// What the walkthrough's tests share (`ButtonInventoryUITests`, `EndToEndUITests`): a fresh launch
/// in a chosen language, the look-ups every screen needs, waiting, and the pictures for a human.
///
/// The interface runs in English unless the runner sets `GOLDA_SHOTS_LANG=ru`
/// (`TEST_RUNNER_GOLDA_SHOTS_LANG=ru xcodebuild test ...`), so the same walk can be pictured in both
/// languages; the few look-ups by title go through `Walk.text(_:_:)`. The sample names stay
/// Russian in both languages, as they are data.
@MainActor
struct Walk {
    let app: XCUIApplication
    let language: String
    private let shots: Shots?

    var isRussian: Bool { language == "ru" }

    /// A fresh app: in memory, the made-up person's fortnight unless [samples] is false, and
    /// [extra] arguments after (the voice stub). The language goes first: the defaults system reads
    /// arguments in pairs, and the single `-golda.*` flags after it must not take it away.
    init(samples: Bool = true, extra: [String] = [], shotsName: String) {
        let environment = ProcessInfo.processInfo.environment
        let language = environment["GOLDA_SHOTS_LANG"] ?? "en"
        self.language = language
        shots = environment["GOLDA_SHOTS_DIR"].map { Shots(directory: $0, prefix: (environment["GOLDA_SHOTS_NAME"] ?? language) + "-" + shotsName) }
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", language == "ru" ? "ru_RU" : "en_US", "-golda.inMemory"]
            + (samples ? ["-golda.samples"] : []) + extra
        app.launch()
    }

    /// The English or the Russian of a title, as the interface shows it.
    func text(_ english: String, _ russian: String) -> String { isRussian ? russian : english }

    /// A picture of the screen, when the runner asks for them (`GOLDA_SHOTS_DIR`).
    func shoot(_ name: String) {
        shots?.shoot(name)
    }

    // MARK: Look-ups

    func any(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier] }

    var homeHero: XCUIElement { any("home.hero") }
    var accountsHero: XCUIElement { any("accounts.hero") }
    var mic: XCUIElement { app.buttons["mic"] }
    var operations: XCUIElementQuery { app.buttons.matching(identifier: "home.operation") }

    func tab(_ english: String, _ russian: String) -> XCUIElement { app.tabBars.buttons[text(english, russian)] }

    /// A toolbar button of the open tab: each tab has its own toolbar, and only the open one can be tapped.
    func tapToolbar(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let buttons = app.navigationBars.buttons.matching(identifier: identifier)
        XCTAssertTrue(buttons.firstMatch.waitForExistence(timeout: 30), identifier, file: file, line: line)
        guard let button = buttons.allElementsBoundByIndex.first(where: { $0.exists && $0.isHittable }) else {
            return XCTFail("no tappable \(identifier)", file: file, line: line)
        }
        button.tap()
    }

    /// An account's row on Accounts: its VoiceOver label starts with the name.
    func accountRow(_ name: String) -> XCUIElement {
        app.buttons.matching(identifier: "accounts.account").matching(NSPredicate(format: "label BEGINSWITH %@", name + ",")).firstMatch
    }

    /// A toast's text, or any text, that contains [part].
    func staticText(containing part: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", part)).firstMatch
    }

    func button(startingWith prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    // MARK: Moving about

    func openTab(_ english: String, _ russian: String, waitingFor identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let tab = tab(english, russian)
        XCTAssertTrue(tab.waitForExistence(timeout: 30), english, file: file, line: line)
        tab.tap()
        XCTAssertTrue(any(identifier).waitForExistence(timeout: 10), identifier, file: file, line: line)
    }

    /// Scrolls until [element] can be tapped clear of the bars: a row under the tab bar still counts
    /// as hittable. A list keeps only the rows near the screen, so a missing row is looked for
    /// further down first, then back up; a row in sight is moved clear of the top bar or the
    /// bottom one. Down is swiped only while there is something above, so a sheet at its top is
    /// never pulled down and closed.
    func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let screen = app.frame
        let top = screen.minY + 100
        func bottom() -> CGFloat {
            let bar = app.tabBars.firstMatch
            return bar.exists && bar.isHittable ? min(bar.frame.minY, screen.maxY - 40) : screen.maxY - 40
        }
        func clear() -> Bool {
            element.exists && element.isHittable && element.frame.minY > top && element.frame.maxY <= bottom()
        }
        for _ in 0..<8 where !element.exists { app.swipeUp(velocity: .slow) }
        for _ in 0..<12 where !element.exists { app.swipeDown(velocity: .slow) }
        for _ in 0..<8 where !clear() {
            if element.exists, element.frame.minY <= top {
                app.swipeDown(velocity: .slow)
            } else {
                app.swipeUp(velocity: .slow)
            }
        }
        XCTAssertTrue(element.exists && element.isHittable, "\(element) is not on screen", file: file, line: line)
    }

    /// The back button of the page on top.
    func back() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    /// A short drag on a form puts the keyboard away: it goes as soon as the form scrolls.
    func dismissKeyboard() {
        guard app.keyboards.firstMatch.exists else { return }
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42))
        from.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48)))
        _ = waitUntil { !app.keyboards.firstMatch.exists }
    }

    /// Types into a field after a tap, a second tap when the keyboard has not come.
    func type(_ text: String, into field: XCUIElement) {
        field.tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 2) { field.tap() }
        field.typeText(text)
    }

    /// A SwiftUI switch flips on its knob, not on its label; a tap lost while a list settles is made again.
    func flip(_ toggle: XCUIElement) {
        let before = toggle.value as? String
        for _ in 0..<2 {
            let knob = toggle.switches.firstMatch
            if knob.exists { knob.tap() } else { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
            if waitUntil(timeout: 2, { toggle.value as? String != before }) { return }
        }
    }
}

/// Polls [condition] until it holds or [timeout] runs out: the screens follow the database a moment later.
@MainActor
func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline { return false }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    }
    return true
}

/// The first whole number in a VoiceOver label, signed: "Safe to spend today. 2227 Russian rubles…"
/// gives 2227; a label of the Accounts total or a hero over the budget gives its minus.
func firstWholeNumber(in label: String) -> Int? {
    let rest = label.drop { !$0.isNumber && $0 != "-" && $0 != "−" }
    let negative = rest.first == "-" || rest.first == "−"
    let digits = rest.drop { !$0.isNumber }.prefix { $0.isNumber }
    return Int(digits).map { negative ? -$0 : $0 }
}

/// Pictures for a human, numbered in the order they were taken.
@MainActor
final class Shots {
    private let directory: String
    private let prefix: String
    private var step = 0

    init(directory: String, prefix: String) {
        self.directory = directory
        self.prefix = prefix
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    }

    func shoot(_ name: String) {
        // Animations and toasts settle first.
        Thread.sleep(forTimeInterval: 0.8)
        step += 1
        let path = (directory as NSString).appendingPathComponent(String(format: "%@-%02d-%@.png", prefix, step, name))
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: path))
    }
}
