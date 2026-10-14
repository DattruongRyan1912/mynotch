// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MediaModule",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "MediaModule", targets: ["MediaModule"]),
        .library(name: "YouTubeBridgeKit", targets: ["YouTubeBridgeKit"]),
    ],
    dependencies: [
        .package(path: "../../MyNotchCore"),
        .package(path: "../../NotchUI"),
    ],
    targets: [
        // Foundation only and no main-actor default, so the tiny `mynotch-youtube-host` CLI can link it.
        .target(name: "YouTubeBridgeKit"),
        .target(
            name: "MediaModule",
            dependencies: ["YouTubeBridgeKit", "MyNotchCore", "NotchUI"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "YouTubeBridgeKitTests", dependencies: ["YouTubeBridgeKit"]),
        .testTarget(
            name: "MediaModuleTests",
            dependencies: ["MediaModule", "YouTubeBridgeKit", .product(name: "MyNotchTestSupport", package: "MyNotchCore")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
