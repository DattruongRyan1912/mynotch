// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PerformanceModule",
    platforms: [.macOS(.v26)],
    products: [.library(name: "PerformanceModule", targets: ["PerformanceModule"])],
    dependencies: [
        .package(path: "../../MyNotchCore"),
        .package(path: "../../NotchUI"),
    ],
    targets: [
        .target(
            name: "PerformanceModule",
            dependencies: ["MyNotchCore", "NotchUI"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "PerformanceModuleTests",
            dependencies: ["PerformanceModule", .product(name: "MyNotchTestSupport", package: "MyNotchCore")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
