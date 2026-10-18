import CoreGraphics

nonisolated extension RecordingRegion {
    /// A rect in the display's own pixels, as the overlay hands it over (already snapped to pixels), kept on the display and made
    /// even. It never goes through points, so no pixel can drift on the way. Nil when none of it is on the display.
    init?(display: DisplayInfo, pixelRect: CGRect) {
        let bounds = CGRect(
            x: 0, y: 0, width: (display.frame.width * display.scale).rounded(), height: (display.frame.height * display.scale).rounded()
        )
        let rect = pixelRect.standardized.intersection(bounds)
        guard !rect.isNull else { return nil }
        let x = rect.minX.rounded(.down), y = rect.minY.rounded(.down)
        let width = (Int(rect.maxX.rounded(.up) - x) / 2) * 2, height = (Int(rect.maxY.rounded(.up) - y) / 2) * 2
        guard width >= 2, height >= 2 else { return nil }
        self.display = display
        self.pixelRect = CGRect(x: x, y: y, width: CGFloat(width), height: CGFloat(height))
    }
}

/// What the overlay's answer means for a recording.
nonisolated enum RecordingSelection {
    /// The part of a display to record for what the overlay returned. A window is its frame as it is now: the recording keeps that
    /// region for good, so moving the window afterwards moves nothing. Nil when the answer has no display or window to point at.
    static func region(for result: CaptureResult, displays: [DisplayInfo], windows: [CapturableWindow]) -> RecordingRegion? {
        switch result {
        case .fullScreen(let id):
            return displays.first { $0.id == id }.flatMap { RecordingRegion(fullScreen: $0) }
        case .region(let id, let pixelRect):
            return displays.first { $0.id == id }.flatMap { RecordingRegion(display: $0, pixelRect: pixelRect) }
        case .window(let id):
            guard let window = windows.first(where: { $0.id == id }), let primaryHeight = GeometryMapper.primaryHeight(of: displays),
                  let display = GeometryMapper.display(containingCenterOf: window.bounds, in: displays, primaryHeight: primaryHeight)
            else { return nil }
            return RecordingRegion(display: display, selection: GeometryMapper.appKitRect(fromCG: window.bounds, primaryHeight: primaryHeight))
        }
    }
}
