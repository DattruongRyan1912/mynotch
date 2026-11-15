// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HabitModule",
    platforms: [.macOS(.v26)],
    products: [.library(name: "HabitModule", targets: ["HabitModule"])],
    dependencies: [
        .package(path: "../../MyNotchCore"),
        .package(path: "../../NotchUI"),
    ],
    targets: [
        .target(
            name: "HabitModule",
            dependencies: ["MyNotchCore", "NotchUI"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "HabitModuleTests",
            dependencies: ["HabitModule", .product(name: "MyNotchTestSupport", package: "MyNotchCore")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
