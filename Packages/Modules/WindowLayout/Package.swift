// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WindowLayoutModule",
    platforms: [.macOS(.v26)],
    products: [.library(name: "WindowLayoutModule", targets: ["WindowLayoutModule"])],
    dependencies: [
        .package(path: "../../MyNotchCore"),
        .package(path: "../../NotchUI"),
    ],
    targets: [
        .target(
            name: "WindowLayoutModule",
            dependencies: ["MyNotchCore", "NotchUI"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "WindowLayoutModuleTests",
            dependencies: ["WindowLayoutModule", .product(name: "MyNotchTestSupport", package: "MyNotchCore")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
