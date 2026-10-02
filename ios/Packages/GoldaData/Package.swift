// swift-tools-version: 6.2
import PackageDescription

// Storage, backups, rates, Keychain and the voice queue. Filled in at stage 1.
let package = Package(
    name: "GoldaData",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [.library(name: "GoldaData", targets: ["GoldaData"])],
    dependencies: [.package(path: "../GoldaCore")],
    targets: [
        .target(name: "GoldaData", dependencies: [.product(name: "GoldaCore", package: "GoldaCore")]),
    ]
)
