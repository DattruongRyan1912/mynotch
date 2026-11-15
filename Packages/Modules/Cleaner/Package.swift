// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CleanerModule",
    platforms: [.macOS(.v26)],
    products: [.library(name: "CleanerModule", targets: ["CleanerModule"])],
    dependencies: [
        .package(path: "../../MyNotchCore"),
        .package(path: "../../NotchUI"),
    ],
    targets: [
        .target(
            name: "CleanerModule",
            dependencies: ["MyNotchCore", "NotchUI"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "CleanerModuleTests",
            dependencies: ["CleanerModule", .product(name: "MyNotchTestSupport", package: "MyNotchCore")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
