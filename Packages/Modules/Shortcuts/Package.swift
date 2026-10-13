// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ShortcutsModule",
    platforms: [.macOS(.v26)],
    products: [.library(name: "ShortcutsModule", targets: ["ShortcutsModule"])],
    dependencies: [
        .package(path: "../../MyNotchCore"),
        .package(path: "../../NotchUI"),
    ],
    targets: [
        .target(
            name: "ShortcutsModule",
            dependencies: ["MyNotchCore", "NotchUI"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "ShortcutsModuleTests",
            dependencies: ["ShortcutsModule", .product(name: "MyNotchTestSupport", package: "MyNotchCore")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
