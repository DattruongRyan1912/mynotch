import CoreGraphics

/// One display's screen as it was when the capture started, at full pixel resolution.
nonisolated struct FrozenDisplay: Sendable {
    var info: DisplayInfo
    var image: CGImage
}
