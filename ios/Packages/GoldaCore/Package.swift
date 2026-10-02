// swift-tools-version: 6.2
import PackageDescription

// The domain: money maths, ledger, budget, debts, goals, analytics and the voice mapper.
// It imports only Foundation, so `swift test` runs on the Mac without a simulator.
let package = Package(
    name: "GoldaCore",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [.library(name: "GoldaCore", targets: ["GoldaCore"])],
    targets: [
        .target(name: "GoldaCore"),
        .testTarget(name: "GoldaCoreTests", dependencies: ["GoldaCore"]),
    ]
)
