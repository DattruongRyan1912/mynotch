// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DebugTools",
    platforms: [.macOS(.v26)],
    products: [.library(name: "DebugTools", targets: ["DebugTools"])],
    dependencies: [
        .package(path: "../MyNotchCore"),
    ],
    targets: [
        .target(
            name: "DebugTools",
            dependencies: ["MyNotchCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "DebugToolsTests",
            dependencies: ["DebugTools", .product(name: "MyNotchTestSupport", package: "MyNotchCore")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
