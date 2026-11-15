import AppKit
import CoreGraphics
import Foundation

public enum ScrollingTarget: Sendable {
    case region(displayID: CGDirectDisplayID, pixelRect: CGRect)
    case window(id: CGWindowID)
}

@MainActor
final class ScrollingCaptureSession {
    let id = UUID()
    let target: ScrollingTarget
    let scale: CGFloat
    var stitcher: LongCaptureStitcher
    var eventMonitors: [Any] = []
    var isSampling = false
    var frameCount = 1
    var hasPendingScroll = false
    var lastSampleTime: ContinuousClock.Instant = .now - .seconds(1)

    init(
        target: ScrollingTarget,
        scale: CGFloat,
        initialFrame: CGImage
    ) {
        self.target = target
        self.scale = scale
        self.stitcher = LongCaptureStitcher(initialFrame: initialFrame)
    }

    func cleanUp() {
        for monitor in eventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        eventMonitors.removeAll()
    }
}
