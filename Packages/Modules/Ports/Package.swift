// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PortsModule",
    platforms: [.macOS(.v26)],
    products: [.library(name: "PortsModule", targets: ["PortsModule"])],
    dependencies: [
        .package(path: "../../MyNotchCore"),
        .package(path: "../../NotchUI"),
    ],
    targets: [
        .target(
            name: "PortsModule",
            dependencies: ["MyNotchCore", "NotchUI"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "PortsModuleTests",
            dependencies: ["PortsModule", .product(name: "MyNotchTestSupport", package: "MyNotchCore")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
