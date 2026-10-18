import CoreGraphics

/// A display in AppKit's coordinates, where y grows upward.
nonisolated struct ChipScreen: Equatable, Sendable {
    var frame: CGRect
    /// Without the menu bar and the Dock.
    var visibleFrame: CGRect
}

/// Where the chip goes. A corner, not under the notch: anything under the notch is in the notch's hover area, and the
/// pointer going there to press a button would open the notch, which covers it.
nonisolated enum CaptureChipGeometry {
    /// Between the chip and the edges of the visible screen, in points.
    static let margin: CGFloat = 16

    /// In the top-right corner of the visible part of the screen the pointer is on (the first one when it is on none),
    /// below the menu bar and never outside that area, even if the area is smaller than the chip.
    static func frame(size: CGSize, pointer: CGPoint, screens: [ChipScreen]) -> CGRect {
        guard let screen = screens.first(where: { $0.frame.contains(pointer) }) ?? screens.first else {
            return CGRect(origin: .zero, size: size)
        }
        let visible = screen.visibleFrame
        return CGRect(
            x: max(visible.minX, visible.maxX - margin - size.width), y: max(visible.minY, visible.maxY - margin - size.height),
            width: size.width, height: size.height
        )
    }
}
