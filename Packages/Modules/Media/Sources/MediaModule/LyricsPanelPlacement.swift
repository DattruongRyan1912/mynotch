import CoreGraphics

/// What the lyrics panel needs to know of a display: `key` is stable across reconnects (the display's UUID, unlike its number or
/// its place in the list), the whole frame decides which display a window is on, and the visible frame (without the menu bar and
/// the Dock) is where the panel may go. AppKit coordinates: global, origin at the bottom left of the main display, y up.
nonisolated struct PanelDisplay: Equatable, Sendable {
    var key: String
    var frame: CGRect
    var visibleFrame: CGRect
}

/// Where the floating lyrics panel was left on each display, and where it opens: on the display it was last on, at the place
/// and in the size it had there. Pure geometry, stored as one setting.
nonisolated struct LyricsPanelPlacement: Codable, Equatable, Sendable {
    static let defaultSize = CGSize(width: 460, height: 132)
    /// Smaller than this the three lines no longer fit.
    static let minimumSize = CGSize(width: 260, height: 92)
    /// Between the bottom of the visible area and the panel the first time.
    static let bottomGap: CGFloat = 80

    /// A frame relative to the bottom left of its display, so a display that moves in the arrangement takes the panel along.
    struct StoredFrame: Codable, Equatable, Sendable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
    }

    /// By display key.
    private(set) var frames: [String: StoredFrame] = [:]
    /// The display the panel was last moved or resized on; where it opens while that display is there.
    private(set) var lastDisplay: String?

    init() {}

    /// The first time on `display`: centred, just above its bottom.
    static func defaultFrame(on display: PanelDisplay) -> CGRect {
        let area = display.visibleFrame
        return inside(CGRect(
            x: area.midX - defaultSize.width / 2, y: area.minY + bottomGap, width: defaultSize.width, height: defaultSize.height
        ), area)
    }

    /// Remembers `frame` for the display that holds most of it. A frame on no display, or with a number that is not one, is
    /// left out: it says nothing about where the user wants the panel.
    mutating func remember(_ frame: CGRect, among displays: [PanelDisplay]) {
        guard [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite) else { return }
        var best: (display: PanelDisplay, area: CGFloat)?
        for display in displays {
            let shared = frame.intersection(display.frame)
            let area = shared.isNull ? 0 : shared.width * shared.height
            if area > (best?.area ?? 0) { best = (display, area) }
        }
        guard let display = best?.display else { return }
        frames[display.key] = StoredFrame(
            x: frame.minX - display.frame.minX, y: frame.minY - display.frame.minY, width: frame.width, height: frame.height
        )
        lastDisplay = display.key
    }

    /// Where the panel opens: on the display it was last on, or on the first one (the main display) when that is gone, at the
    /// frame remembered there or else the default; kept at least `minimumSize`, at most the display's, and inside it.
    func restoredFrame(among displays: [PanelDisplay]) -> CGRect {
        guard let display = displays.first(where: { $0.key == lastDisplay }) ?? displays.first else {
            return CGRect(origin: .zero, size: Self.defaultSize)
        }
        guard let stored = frames[display.key] else { return Self.defaultFrame(on: display) }
        let area = display.visibleFrame
        let size = CGSize(
            width: min(max(stored.width, Self.minimumSize.width), area.width),
            height: min(max(stored.height, Self.minimumSize.height), area.height)
        )
        return Self.inside(CGRect(origin: CGPoint(x: display.frame.minX + stored.x, y: display.frame.minY + stored.y), size: size), area)
    }

    private static func inside(_ frame: CGRect, _ area: CGRect) -> CGRect {
        var frame = frame
        frame.size.width = min(frame.width, area.width)
        frame.size.height = min(frame.height, area.height)
        frame.origin.x = max(area.minX, min(frame.minX, area.maxX - frame.width))
        frame.origin.y = max(area.minY, min(frame.minY, area.maxY - frame.height))
        return frame
    }
}
