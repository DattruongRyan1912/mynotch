// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BatteryModule",
    platforms: [.macOS(.v26)],
    products: [.library(name: "BatteryModule", targets: ["BatteryModule"])],
    dependencies: [
        .package(path: "../../MyNotchCore"),
        .package(path: "../../NotchUI"),
    ],
    targets: [
        .target(
            name: "BatteryModule",
            dependencies: ["MyNotchCore", "NotchUI"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "BatteryModuleTests",
            dependencies: ["BatteryModule", .product(name: "MyNotchTestSupport", package: "MyNotchCore")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
