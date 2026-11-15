// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TranslationModule",
    platforms: [.macOS(.v26)],
    products: [.library(name: "TranslationModule", targets: ["TranslationModule"])],
    dependencies: [
        .package(path: "../../MyNotchCore"),
        .package(path: "../../NotchUI"),
    ],
    targets: [
        .target(
            name: "TranslationModule",
            dependencies: ["MyNotchCore", "NotchUI"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "TranslationModuleTests",
            dependencies: ["TranslationModule", .product(name: "MyNotchTestSupport", package: "MyNotchCore")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
