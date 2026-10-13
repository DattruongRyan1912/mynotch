// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LockScreenModule",
    platforms: [.macOS(.v26)],
    products: [.library(name: "LockScreenModule", targets: ["LockScreenModule"])],
    dependencies: [
        .package(path: "../../MyNotchCore"),
        .package(path: "../../NotchUI"),
    ],
    targets: [
        .target(
            name: "LockScreenModule",
            dependencies: ["MyNotchCore", "NotchUI"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "LockScreenModuleTests",
            dependencies: ["LockScreenModule", .product(name: "MyNotchTestSupport", package: "MyNotchCore")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
