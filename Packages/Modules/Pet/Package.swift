// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PetModule",
    platforms: [.macOS(.v26)],
    products: [.library(name: "PetModule", targets: ["PetModule"])],
    dependencies: [
        .package(path: "../../MyNotchCore"),
        .package(path: "../../NotchUI"),
    ],
    targets: [
        .target(
            name: "PetModule",
            dependencies: ["MyNotchCore", "NotchUI"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "PetModuleTests",
            dependencies: ["PetModule", .product(name: "MyNotchTestSupport", package: "MyNotchCore")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
