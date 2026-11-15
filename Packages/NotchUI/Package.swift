// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NotchUI",
    platforms: [.macOS(.v26)],
    products: [.library(name: "NotchUI", targets: ["NotchUI"])],
    dependencies: [.package(path: "../MyNotchCore")],
    targets: [
        .target(
            name: "NotchUI",
            dependencies: ["MyNotchCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "NotchUITests",
            dependencies: ["NotchUI", .product(name: "MyNotchTestSupport", package: "MyNotchCore")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
