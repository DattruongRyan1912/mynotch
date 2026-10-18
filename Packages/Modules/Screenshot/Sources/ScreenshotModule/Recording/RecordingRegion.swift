import CoreGraphics

/// The part of one display a recording covers, fixed for the whole recording. A window is its frame when the recording
/// starts; dragging the window afterwards does not move the region.
nonisolated struct RecordingRegion: Codable, Equatable, Sendable {
    var display: DisplayInfo
    /// Whole pixels of the display, origin at its top-left, width and height even. The capture, the size of the video and the
    /// pointer's coordinates all come from this one rect, so they cannot disagree.
    var pixelRect: CGRect

    /// The selection (AppKit points) snapped outward to pixels and kept on the display. Nil when less than 2 pixels are left.
    /// The encoder takes odd sizes, but an odd width splits a chroma sample and breaks the H.264 export, so one pixel is dropped.
    init?(display: DisplayInfo, selection: CGRect) {
        let clamped = GeometryMapper.clamp(selection, to: display)
        let rect = GeometryMapper.pixelRect(for: clamped, on: display)
        let width = (Int(rect.width) / 2) * 2, height = (Int(rect.height) / 2) * 2
        guard width >= 2, height >= 2 else { return nil }
        self.display = display
        pixelRect = CGRect(x: rect.minX, y: rect.minY, width: CGFloat(width), height: CGFloat(height))
    }

    /// The whole display.
    init?(fullScreen display: DisplayInfo) {
        self.init(display: display, selection: display.frame)
    }

    var pixelWidth: Int { Int(pixelRect.width) }
    var pixelHeight: Int { Int(pixelRect.height) }

    /// The area ScreenCaptureKit samples: points, origin at the display's top-left.
    var sourceRect: CGRect {
        let scale = display.scale
        return CGRect(x: pixelRect.minX / scale, y: pixelRect.minY / scale, width: pixelRect.width / scale, height: pixelRect.height / scale)
    }

    /// A point in AppKit global coordinates (origin at the bottom-left of the primary display, y up) as a pixel of the video:
    /// origin at its top-left, y down. Not clamped: the pointer can leave the region, and the camera clamps.
    func pixelPoint(forAppKit point: CGPoint) -> CGPoint {
        let scale = display.scale
        let x = (point.x - display.frame.minX) * scale - pixelRect.minX
        let y = (display.frame.maxY - point.y) * scale - pixelRect.minY
        return CGPoint(x: x, y: y)
    }
}
