// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MyNotchCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "MyNotchCore", targets: ["MyNotchCore"]),
        .library(name: "MyNotchTestSupport", targets: ["MyNotchTestSupport"]),
        .library(name: "LocalSocketKit", targets: ["LocalSocketKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "3.1.0"),
    ],
    targets: [
        // Foundation only and no main-actor default, so the tiny command-line helpers (`mynotch-hook`,
        // `mynotch-clipboard-mcp`, `mynotch-youtube-host`) can link it without the rest of MyNotchCore.
        .target(name: "LocalSocketKit"),
        .target(
            name: "MyNotchCore",
            dependencies: ["KeyboardShortcuts"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .target(
            name: "MyNotchTestSupport",
            dependencies: ["MyNotchCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "LocalSocketKitTests", dependencies: ["LocalSocketKit", "MyNotchTestSupport"]),
        .testTarget(
            name: "MyNotchCoreTests",
            dependencies: ["MyNotchCore", "MyNotchTestSupport"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
