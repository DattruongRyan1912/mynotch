// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ShelfModule",
    platforms: [.macOS(.v26)],
    products: [.library(name: "ShelfModule", targets: ["ShelfModule"])],
    dependencies: [
        .package(path: "../../MyNotchCore"),
        .package(path: "../../NotchUI"),
    ],
    targets: [
        .target(
            name: "ShelfModule",
            dependencies: ["MyNotchCore", "NotchUI"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "ShelfModuleTests",
            dependencies: ["ShelfModule", .product(name: "MyNotchTestSupport", package: "MyNotchCore")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
