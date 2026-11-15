// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TodoModule",
    platforms: [.macOS(.v26)],
    products: [.library(name: "TodoModule", targets: ["TodoModule"])],
    dependencies: [
        .package(path: "../../MyNotchCore"),
        .package(path: "../../NotchUI"),
    ],
    targets: [
        .target(
            name: "TodoModule",
            dependencies: ["MyNotchCore", "NotchUI"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "TodoModuleTests",
            dependencies: ["TodoModule", .product(name: "MyNotchTestSupport", package: "MyNotchCore")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
