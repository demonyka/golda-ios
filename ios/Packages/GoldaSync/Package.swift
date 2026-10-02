// swift-tools-version: 6.2
import PackageDescription

// CloudKit sync and sharing of profiles. Filled in at stage 5.
let package = Package(
    name: "GoldaSync",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [.library(name: "GoldaSync", targets: ["GoldaSync"])],
    dependencies: [.package(path: "../GoldaData")],
    targets: [
        .target(name: "GoldaSync", dependencies: [.product(name: "GoldaData", package: "GoldaData")]),
    ]
)
