// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SystemActivitiesModule",
    platforms: [.macOS(.v26)],
    products: [.library(name: "SystemActivitiesModule", targets: ["SystemActivitiesModule"])],
    dependencies: [
        .package(path: "../../MyNotchCore"),
        .package(path: "../../NotchUI"),
    ],
    targets: [
        .target(
            name: "SystemActivitiesModule",
            dependencies: ["MyNotchCore", "NotchUI"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "SystemActivitiesModuleTests",
            dependencies: ["SystemActivitiesModule", .product(name: "MyNotchTestSupport", package: "MyNotchCore")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
