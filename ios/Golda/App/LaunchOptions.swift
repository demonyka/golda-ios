import Foundation

/// A debug command that rebuilds the data at launch, the port of Android's `golda.demo`,
/// `golda.samples` and `golda.reset` intent extras. Every one of them ERASES EVERYTHING first.
enum LaunchCommand: String, CaseIterable, Sendable {
    /// `Demo.fill`: the made-up person with opening balances only.
    case demo
    /// `Demo.samples`: the same person with a fortnight of life abroad.
    case samples
    /// `Repository.resetAll`: a fresh install, back to onboarding.
    case reset
}

/// What the process was launched with. Debug builds read the `-golda.*` arguments; a release
/// build ignores them, so no argument can erase a real user's data.
struct LaunchOptions: Equatable, Sendable {
    var command: LaunchCommand?
    /// A throwaway database and settings: UI tests start from nothing and leave nothing behind.
    var inMemory = false
    /// The process hosts the unit tests: the tests build their own models, so the app must neither
    /// touch the real database nor go to the network.
    var isHostingTests = false
    /// Opening the data fails, so a UI test can see the failure screen; "Try again" clears it.
    var failsDatabase = false

    static var current: LaunchOptions {
        LaunchOptions(arguments: ProcessInfo.processInfo.arguments, environment: ProcessInfo.processInfo.environment)
    }

    init(command: LaunchCommand? = nil, inMemory: Bool = false, isHostingTests: Bool = false, failsDatabase: Bool = false) {
        self.command = command
        self.inMemory = inMemory
        self.isHostingTests = isHostingTests
        self.failsDatabase = failsDatabase
    }

    /// Every argument is a flag on its own: `-golda.samples`, `-golda.inMemory`, `-golda.failDatabase`.
    init(arguments: [String], environment: [String: String]) {
        isHostingTests = environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil
        #if DEBUG
        let flags = Set(arguments)
        // One command per launch, checked in the order of Android's `when`.
        command = [LaunchCommand.samples, .demo, .reset].first { flags.contains("-golda.\($0.rawValue)") }
        inMemory = flags.contains("-golda.inMemory")
        failsDatabase = flags.contains("-golda.failDatabase")
        #endif
    }
}
