// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EqualizerModule",
    platforms: [.macOS(.v26)],
    targets: [
        // The filters. Foundation, Core Audio's buffer types and Synchronization only, and no main-actor default,
        // because `EQChain.process` runs on Core Audio's real-time IO thread.
        .target(name: "EqualizerDSP"),
        .testTarget(name: "EqualizerDSPTests", dependencies: ["EqualizerDSP"]),
    ]
)
