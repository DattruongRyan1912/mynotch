// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PerformanceModule",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PerformanceModule", targets: ["PerformanceModule"]),
        .library(name: "FanHelperKit", targets: ["FanHelperKit"]),
    ],
    dependencies: [
        .package(path: "../../MyNotchCore"),
        .package(path: "../../NotchUI"),
    ],
    targets: [
        // What the app and the privileged fan helper share: the read-only SMC access, the XPC protocol and the code-signing
        // requirements. Foundation and IOKit only and no main-actor default, so the tiny `mynotch-fan-helper` daemon can link it.
        .target(name: "FanHelperKit"),
        .target(
            name: "PerformanceModule",
            dependencies: ["FanHelperKit", "MyNotchCore", "NotchUI"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "FanHelperKitTests", dependencies: ["FanHelperKit"]),
        .testTarget(
            name: "PerformanceModuleTests",
            dependencies: ["PerformanceModule", "FanHelperKit", .product(name: "MyNotchTestSupport", package: "MyNotchCore")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
