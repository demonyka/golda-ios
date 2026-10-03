import Foundation

/// A debug command that rebuilds the data at launch, the port of Android's `golda.demo`,
/// `golda.samples` and `golda.reset` intent extras. Every one of them ERASES EVERYTHING first.
enum LaunchCommand: String, CaseIterable, Sendable {
    /// `Demo.fill`: the made-up person with opening balances only.
    case demo
    /// `Demo.samples`: the same person with a fortnight of life abroad.
    case samples
    /// `Repository.resetAll`: a fresh install, back to the welcome screen.
    case reset
}

/// Where the microphone sits while stage 2a compares the two layouts (O4 in `DECISIONS.md`).
enum MicLayout: String, CaseIterable, Sendable {
    /// A wide button in the tab view's bottom accessory, above the tab bar.
    case accessory
    /// A round glass button floating above the tab bar.
    case floating
}

/// What the process was launched with. Debug builds read the `-golda.*` arguments; a release
/// build ignores them, so no argument can erase a real user's data.
struct LaunchOptions: Equatable, Sendable {
    var command: LaunchCommand?
    /// A throwaway database and settings: UI tests start from nothing and leave nothing behind.
    var inMemory = false
    var micLayout = MicLayout.accessory
    /// The process hosts the unit tests: the tests build their own models, so the app must neither
    /// touch the real database nor go to the network.
    var isHostingTests = false

    static var current: LaunchOptions {
        LaunchOptions(arguments: ProcessInfo.processInfo.arguments, environment: ProcessInfo.processInfo.environment)
    }

    init(command: LaunchCommand? = nil, inMemory: Bool = false, micLayout: MicLayout = .accessory, isHostingTests: Bool = false) {
        self.command = command
        self.inMemory = inMemory
        self.micLayout = micLayout
        self.isHostingTests = isHostingTests
    }

    /// Flags come alone (`-golda.samples`); the mic layout comes as `-golda.mic=floating` or as the
    /// pair `-golda.mic floating`, the form Xcode's scheme editor and `simctl launch` pass.
    init(arguments: [String], environment: [String: String]) {
        isHostingTests = environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil
        #if DEBUG
        let flags = Set(arguments)
        // One command per launch, checked in the order of Android's `when`.
        command = [LaunchCommand.samples, .demo, .reset].first { flags.contains("-golda.\($0.rawValue)") }
        inMemory = flags.contains("-golda.inMemory")
        micLayout = Self.value(of: "-golda.mic", in: arguments).flatMap(MicLayout.init(rawValue:)) ?? .accessory
        #endif
    }

    private static func value(of name: String, in arguments: [String]) -> String? {
        for (index, argument) in arguments.enumerated() {
            if argument.hasPrefix(name + "=") { return String(argument.dropFirst(name.count + 1)) }
            if argument == name, arguments.indices.contains(index + 1) { return arguments[index + 1] }
        }
        return nil
    }
}
