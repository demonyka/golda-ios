import XCTest

/// The app starts on throwaway data and shows its tab bar. Scenario tests build on this launch.
final class SmokeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchesIntoTheTabs() {
        let app = XCUIApplication()
        // `-golda.inMemory` keeps the run away from real data; `-golda.samples` fills a made-up person.
        app.launchArguments = ["-golda.inMemory", "-golda.samples"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))
    }
}
