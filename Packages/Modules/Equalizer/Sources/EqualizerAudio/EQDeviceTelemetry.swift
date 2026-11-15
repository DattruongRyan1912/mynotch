import Foundation

/// Real-time audio device telemetry captured directly from CoreAudio pipeline.
nonisolated public struct EQDeviceTelemetry: Equatable, Sendable, Identifiable {
    public var id: String { uid }
    public let uid: String
    public let name: String
    public let sampleRate: Double
    public let volumePercent: Int?
    public let channelCount: Int
    public let isProcessing: Bool

    public init(
        uid: String,
        name: String,
        sampleRate: Double,
        volumePercent: Int?,
        channelCount: Int = 2,
        isProcessing: Bool = true
    ) {
        self.uid = uid
        self.name = name
        self.sampleRate = sampleRate
        self.volumePercent = volumePercent
        self.channelCount = channelCount
        self.isProcessing = isProcessing
    }
}
