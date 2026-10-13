// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MyNotchCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "MyNotchCore", targets: ["MyNotchCore"]),
        .library(name: "MyNotchTestSupport", targets: ["MyNotchTestSupport"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "3.1.0"),
    ],
    targets: [
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
        .testTarget(
            name: "MyNotchCoreTests",
            dependencies: ["MyNotchCore", "MyNotchTestSupport"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
