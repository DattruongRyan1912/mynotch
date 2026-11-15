// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AIAgentsModule",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "AIAgentsModule", targets: ["AIAgentsModule"]),
        .library(name: "AgentHookKit", targets: ["AgentHookKit"]),
    ],
    dependencies: [
        .package(path: "../../MyNotchCore"),
        .package(path: "../../NotchUI"),
    ],
    targets: [
        // Foundation only and no main-actor default, so the tiny `mynotch-hook` CLI can link it.
        .target(name: "AgentHookKit", dependencies: [.product(name: "LocalSocketKit", package: "MyNotchCore")]),
        .target(
            name: "AIAgentsModule",
            dependencies: ["AgentHookKit", "MyNotchCore", "NotchUI", .product(name: "LocalSocketKit", package: "MyNotchCore")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "AgentHookKitTests",
            dependencies: ["AgentHookKit", .product(name: "LocalSocketKit", package: "MyNotchCore"), .product(name: "MyNotchTestSupport", package: "MyNotchCore")]
        ),
        .testTarget(
            name: "AIAgentsModuleTests",
            dependencies: ["AIAgentsModule", "AgentHookKit", .product(name: "MyNotchTestSupport", package: "MyNotchCore")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
