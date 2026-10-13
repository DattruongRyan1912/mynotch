// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MediaModule",
    platforms: [.macOS(.v26)],
    products: [.library(name: "MediaModule", targets: ["MediaModule"])],
    dependencies: [
        .package(path: "../../MyNotchCore"),
        .package(path: "../../NotchUI"),
    ],
    targets: [
        .target(
            name: "MediaModule",
            dependencies: ["MyNotchCore", "NotchUI"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "MediaModuleTests",
            dependencies: ["MediaModule", .product(name: "MyNotchTestSupport", package: "MyNotchCore")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
