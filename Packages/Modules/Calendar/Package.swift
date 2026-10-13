// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CalendarModule",
    platforms: [.macOS(.v26)],
    products: [.library(name: "CalendarModule", targets: ["CalendarModule"])],
    dependencies: [
        .package(path: "../../MyNotchCore"),
        .package(path: "../../NotchUI"),
    ],
    targets: [
        .target(
            name: "CalendarModule",
            dependencies: ["MyNotchCore", "NotchUI"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "CalendarModuleTests",
            dependencies: ["CalendarModule", .product(name: "MyNotchTestSupport", package: "MyNotchCore")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
