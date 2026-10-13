// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AIAgentsModule",
    platforms: [.macOS(.v26)],
    products: [.library(name: "AIAgentsModule", targets: ["AIAgentsModule"])],
    dependencies: [
        .package(path: "../../MyNotchCore"),
        .package(path: "../../NotchUI"),
    ],
    targets: [
        .target(
            name: "AIAgentsModule",
            dependencies: ["MyNotchCore", "NotchUI"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "AIAgentsModuleTests",
            dependencies: ["AIAgentsModule", .product(name: "MyNotchTestSupport", package: "MyNotchCore")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
