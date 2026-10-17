// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EqualizerModule",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: "../../MyNotchCore"),
    ],
    targets: [
        // The filters. Foundation, Core Audio's buffer types and Synchronization only, and no main-actor default,
        // because `EQChain.process` runs on Core Audio's real-time IO thread.
        .target(name: "EqualizerDSP"),
        .testTarget(name: "EqualizerDSPTests", dependencies: ["EqualizerDSP"]),
        // One tap and replay per playing output device. No main-actor default either: the IO block and the Core Audio
        // notifications run on threads of their own; only `PipelineManager` is marked `@MainActor`.
        .target(name: "EqualizerAudio", dependencies: ["EqualizerDSP", "MyNotchCore"]),
        .testTarget(
            name: "EqualizerAudioTests",
            dependencies: ["EqualizerAudio", "EqualizerDSP", "MyNotchCore", .product(name: "MyNotchTestSupport", package: "MyNotchCore")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
