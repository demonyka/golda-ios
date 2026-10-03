import Foundation
import GoldaData
import Testing

@testable import Golda

/// The debug launch arguments and the in-memory environment UI tests start from.
@Suite struct LaunchOptionsTests {
    private func options(_ arguments: [String], environment: [String: String] = [:]) -> LaunchOptions {
        LaunchOptions(arguments: ["Golda"] + arguments, environment: environment)
    }

    @Test func noArgumentsMeanTheRealApp() {
        #expect(options([]) == LaunchOptions())
    }

    @Test func eachCommandIsReadFromItsFlag() {
        #expect(options(["-golda.demo"]).command == .demo)
        #expect(options(["-golda.samples"]).command == .samples)
        #expect(options(["-golda.reset"]).command == .reset)
        // Android's order decides when several are passed.
        #expect(options(["-golda.reset", "-golda.samples"]).command == .samples)
    }

    @Test func uiTestsAskForAThrowawayStore() {
        let parsed = options(["-golda.inMemory", "-golda.samples"])
        #expect(parsed.inMemory)
        #expect(parsed.command == .samples)
    }

    @Test func theTestHostIsRecognised() {
        #expect(options([], environment: ["XCTestConfigurationFilePath": "/tmp/x.xctestconfiguration"]).isHostingTests)
        #expect(!options([]).isHostingTests)
        // This very process hosts the tests: the check holds on what Xcode really passes.
        #expect(LaunchOptions.current.isHostingTests)
    }

    @Test func theInMemorySuiteStartsEmpty() throws {
        let suite = "golda.tests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let first = try AppEnvironment.inMemory(defaultsSuite: suite)
        first.deviceSettings.update { $0.onboarded = true }

        let second = try AppEnvironment.inMemory(defaultsSuite: suite)

        #expect(!second.deviceSettings.current.onboarded)
    }
}
