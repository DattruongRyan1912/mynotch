import CoreGraphics

/// Where the large preview goes, as pure geometry on the screens' rectangles so no test needs a display. All coordinates are
/// AppKit's: global, with the origin at the bottom left of the main screen and y growing upwards.
nonisolated enum ClipboardPreviewPlacement {
    /// How much of the visible frame the preview takes in each direction: most of it, so what is shown is large, with the
    /// window it belongs to still around it.
    static let share: CGFloat = 0.8

    /// Centred on the display that has most of `host` (the library window or the floating panel), inside that display's
    /// visible frame, so the menu bar and the Dock stay clear. A host that is on no display, or none given, means the first
    /// one. nil when there is no display at all.
    static func frame(host: CGRect?, screens: [ClipboardPanelPlacement.Screen]) -> CGRect? {
        guard let first = screens.first else { return nil }
        let screen = host.flatMap { host in
            screens.max { overlap(host, $0.frame) < overlap(host, $1.frame) }.flatMap { overlap(host, $0.frame) > 0 ? $0 : nil }
        } ?? first
        let area = screen.visibleFrame
        let size = CGSize(width: area.width * share, height: area.height * share)
        return CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height)
    }

    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let shared = a.intersection(b)
        return shared.isNull ? 0 : shared.width * shared.height
    }
}
