// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ClipboardModule",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ClipboardModule", targets: ["ClipboardModule"]),
        .library(name: "ClipboardMCPKit", targets: ["ClipboardMCPKit"]),
    ],
    dependencies: [
        .package(path: "../../MyNotchCore"),
        .package(path: "../../NotchUI"),
    ],
    targets: [
        // Foundation only and no main-actor default, so the tiny `mynotch-clipboard-mcp` CLI can link it.
        .target(name: "ClipboardMCPKit", dependencies: [.product(name: "LocalSocketKit", package: "MyNotchCore")]),
        .target(
            name: "ClipboardModule",
            dependencies: ["ClipboardMCPKit", "MyNotchCore", "NotchUI", .product(name: "LocalSocketKit", package: "MyNotchCore")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "ClipboardMCPKitTests",
            dependencies: ["ClipboardMCPKit", .product(name: "LocalSocketKit", package: "MyNotchCore"), .product(name: "MyNotchTestSupport", package: "MyNotchCore")]
        ),
        .testTarget(
            name: "ClipboardModuleTests",
            dependencies: [
                "ClipboardModule", "ClipboardMCPKit", .product(name: "LocalSocketKit", package: "MyNotchCore"),
                .product(name: "MyNotchTestSupport", package: "MyNotchCore"),
            ],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
