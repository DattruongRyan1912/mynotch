// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ScreenshotModule",
    platforms: [.macOS(.v26)],
    products: [.library(name: "ScreenshotModule", targets: ["ScreenshotModule"])],
    dependencies: [
        .package(path: "../../MyNotchCore"),
        .package(path: "../../NotchUI"),
    ],
    targets: [
        .target(
            name: "ScreenshotModule",
            dependencies: ["MyNotchCore", "NotchUI"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "ScreenshotModuleTests",
            dependencies: ["ScreenshotModule", .product(name: "MyNotchTestSupport", package: "MyNotchCore")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
