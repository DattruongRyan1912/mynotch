import CoreGraphics
import Foundation

/// A pinned screenshot instance floating on screen.
nonisolated struct PinnedItem: Identifiable, Sendable {
    let id: UUID
    let recordID: UUID?
    let image: CGImage
    let scale: CGFloat
    let sourceFrame: CGRect?

    var pointSize: CGSize {
        CGSize(
            width: max(CGFloat(image.width) / max(scale, 1.0), 1.0),
            height: max(CGFloat(image.height) / max(scale, 1.0), 1.0)
        )
    }

    init(
        id: UUID = UUID(),
        recordID: UUID? = nil,
        image: CGImage,
        scale: CGFloat = 2.0,
        sourceFrame: CGRect? = nil
    ) {
        self.id = id
        self.recordID = recordID
        self.image = image
        self.scale = scale
        self.sourceFrame = sourceFrame
    }
}

/// Pure state machine managing zoom and opacity of a pinned floating window.
nonisolated struct PinnedWindowState: Equatable, Sendable {
    static let minZoom: CGFloat = 0.25
    static let maxZoom: CGFloat = 4.0
    static let minDimension: CGFloat = 60.0
    static let minOpacity: CGFloat = 0.2
    static let maxOpacity: CGFloat = 1.0
    static let zoomPresets: [CGFloat] = [0.5, 1.0, 1.5, 2.0]
    static let opacityPresets: [CGFloat] = [1.0, 0.75, 0.5, 0.25]

    let baseSize: CGSize
    private(set) var zoom: CGFloat = 1.0
    private(set) var opacity: CGFloat = 1.0

    init(baseSize: CGSize, zoom: CGFloat = 1.0, opacity: CGFloat = 1.0) {
        self.baseSize = CGSize(width: max(baseSize.width, 1.0), height: max(baseSize.height, 1.0))
        self.zoom = min(max(zoom, Self.minZoom), Self.maxZoom)
        self.opacity = min(max(opacity, Self.minOpacity), Self.maxOpacity)
    }

    /// The window's current dimensions, keeping aspect ratio and satisfying minimum dimension limits.
    var currentSize: CGSize {
        let targetW = max(baseSize.width * zoom, 1.0)
        let targetH = max(baseSize.height * zoom, 1.0)
        let minEdge = min(targetW, targetH)
        if minEdge < Self.minDimension {
            let scaleFactor = Self.minDimension / max(minEdge, 0.001)
            return CGSize(width: targetW * scaleFactor, height: targetH * scaleFactor)
        }
        return CGSize(width: targetW, height: targetH)
    }

    /// Updates the zoom level and returns the new window frame anchored around a local anchor point.
    mutating func setZoom(_ targetZoom: CGFloat, currentFrame: CGRect, anchorInWindow: CGPoint? = nil) -> CGRect {
        let clamped = min(max(targetZoom, Self.minZoom), Self.maxZoom)
        zoom = clamped

        let newSize = currentSize
        let anchor = anchorInWindow ?? CGPoint(x: currentFrame.width / 2.0, y: currentFrame.height / 2.0)
        let ratioX = currentFrame.width > 0 ? (anchor.x / currentFrame.width) : 0.5
        let ratioY = currentFrame.height > 0 ? (anchor.y / currentFrame.height) : 0.5

        let newOriginX = currentFrame.minX + anchor.x - (newSize.width * ratioX)
        let newOriginY = currentFrame.minY + anchor.y - (newSize.height * ratioY)
        return CGRect(origin: CGPoint(x: newOriginX, y: newOriginY), size: newSize)
    }

    /// Adjusts zoom based on scroll wheel delta (e.g. from mouse wheel or pinch gesture).
    mutating func applyScrollDelta(_ deltaY: CGFloat, currentFrame: CGRect, anchorInWindow: CGPoint? = nil) -> CGRect {
        let factor = max(0.5, min(1.5, 1.0 + deltaY * 0.01))
        return setZoom(zoom * factor, currentFrame: currentFrame, anchorInWindow: anchorInWindow)
    }

    /// Sets opacity clamped to [minOpacity, maxOpacity].
    mutating func setOpacity(_ targetOpacity: CGFloat) {
        opacity = min(max(targetOpacity, Self.minOpacity), Self.maxOpacity)
    }

    /// Calculates initial window placement: matches source capture region if available, or centers on screen.
    static func initialFrame(baseSize: CGSize, sourceFrame: CGRect?, visibleScreenFrame: CGRect) -> CGRect {
        if let source = sourceFrame {
            var frame = CGRect(origin: source.origin, size: baseSize)
            if !visibleScreenFrame.isNull && visibleScreenFrame.width > 0 && visibleScreenFrame.height > 0 {
                let minX = visibleScreenFrame.minX - baseSize.width + 48.0
                let maxX = visibleScreenFrame.maxX - 48.0
                let minY = visibleScreenFrame.minY - baseSize.height + 48.0
                let maxY = visibleScreenFrame.maxY - 48.0
                frame.origin.x = min(max(frame.origin.x, minX), maxX)
                frame.origin.y = min(max(frame.origin.y, minY), maxY)
            }
            return frame
        }

        let maxW = max(visibleScreenFrame.width * 0.8, 200.0)
        let maxH = max(visibleScreenFrame.height * 0.8, 200.0)
        let scaleW = maxW / max(baseSize.width, 1.0)
        let scaleH = maxH / max(baseSize.height, 1.0)
        let scaleFactor = min(1.0, min(scaleW, scaleH))
        let fittedSize = CGSize(width: baseSize.width * scaleFactor, height: baseSize.height * scaleFactor)
        let origin = CGPoint(
            x: visibleScreenFrame.midX - fittedSize.width / 2.0,
            y: visibleScreenFrame.midY - fittedSize.height / 2.0
        )
        return CGRect(origin: origin, size: fittedSize)
    }
}
