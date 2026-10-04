// swift-tools-version: 6.2
import PackageDescription

// CloudKit sync and sharing of profiles (stage 5). The transport stands behind `SyncTransport`;
// everything but `CloudKitSyncTransport` is tested without iCloud.
let package = Package(
    name: "GoldaSync",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [.library(name: "GoldaSync", targets: ["GoldaSync"])],
    dependencies: [
        .package(path: "../GoldaCore"),
        .package(path: "../GoldaData"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.11.1"),
    ],
    targets: [
        .target(
            name: "GoldaSync",
            dependencies: [
                .product(name: "GoldaCore", package: "GoldaCore"),
                .product(name: "GoldaData", package: "GoldaData"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(name: "GoldaSyncTests", dependencies: ["GoldaSync"]),
    ]
)
