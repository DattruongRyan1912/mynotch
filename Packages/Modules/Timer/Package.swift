// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TimerModule",
    platforms: [.macOS(.v26)],
    products: [.library(name: "TimerModule", targets: ["TimerModule"])],
    dependencies: [
        .package(path: "../../MyNotchCore"),
        .package(path: "../../NotchUI"),
    ],
    targets: [
        .target(
            name: "TimerModule",
            dependencies: ["MyNotchCore", "NotchUI"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "TimerModuleTests",
            dependencies: ["TimerModule", .product(name: "MyNotchTestSupport", package: "MyNotchCore")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
