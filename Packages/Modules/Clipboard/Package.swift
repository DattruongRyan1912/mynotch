// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ClipboardModule",
    platforms: [.macOS(.v26)],
    products: [.library(name: "ClipboardModule", targets: ["ClipboardModule"])],
    dependencies: [
        .package(path: "../../MyNotchCore"),
        .package(path: "../../NotchUI"),
    ],
    targets: [
        .target(
            name: "ClipboardModule",
            dependencies: ["MyNotchCore", "NotchUI"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "ClipboardModuleTests",
            dependencies: ["ClipboardModule", .product(name: "MyNotchTestSupport", package: "MyNotchCore")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
