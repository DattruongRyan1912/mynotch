import CoreGraphics

/// A way to place a dragged window: one or more zones of a display's visible area. Dropping on a tile with several
/// zones picks the zone under the pointer; a tile with one zone places the window in it.
nonisolated enum SnapLayout: String, CaseIterable, Identifiable, Sendable {
    case leftHalf, rightHalf, fullScreen, quarters, thirds, focus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leftHalf: "Nửa trái"
        case .rightHalf: "Nửa phải"
        case .fullScreen: "Toàn màn hình"
        case .quarters: "Chia bốn"
        case .thirds: "Chia ba"
        case .focus: "Giữa"
        }
    }

    /// The zones in the order the pointer picks them: the quarters go top left, top right, bottom left, bottom right; the
    /// thirds left to right.
    var zones: [SnapZone] {
        switch self {
        case .leftHalf: [SnapZone(x: 0, y: 0, width: 0.5, height: 1, shares: [.right])]
        case .rightHalf: [SnapZone(x: 0.5, y: 0, width: 0.5, height: 1, shares: [.left])]
        case .fullScreen: [SnapZone(x: 0, y: 0, width: 1, height: 1)]
        case .quarters: [
            SnapZone(x: 0, y: 0, width: 0.5, height: 0.5, shares: [.right, .bottom]),
            SnapZone(x: 0.5, y: 0, width: 0.5, height: 0.5, shares: [.left, .bottom]),
            SnapZone(x: 0, y: 0.5, width: 0.5, height: 0.5, shares: [.right, .top]),
            SnapZone(x: 0.5, y: 0.5, width: 0.5, height: 0.5, shares: [.left, .top]),
        ]
        case .thirds: [
            SnapZone(x: 0, y: 0, width: 1.0 / 3, height: 1, shares: [.right]),
            SnapZone(x: 1.0 / 3, y: 0, width: 1.0 / 3, height: 1, shares: [.left, .right]),
            SnapZone(x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 1, shares: [.left]),
        ]
        // Centred two thirds of the width at full height, with nothing beside it.
        case .focus: [SnapZone(x: 1.0 / 6, y: 0, width: 2.0 / 3, height: 1)]
        }
    }

    /// Where the window goes for `zones[zone]`, in the same coordinates as `area` (AppKit: y grows up). `area` is what
    /// the display leaves visible once the menu bar and the Dock are out, so the window never goes under either.
    ///
    /// The gap is the space between two windows and also between a window and the edge of the area, so a gap of 8 looks
    /// the same everywhere. A side the zone shares with another window's zone is moved in by half the gap, so the two
    /// windows end up a whole gap apart even though each was placed on its own.
    func frame(zone index: Int, in area: CGRect, gap: CGFloat) -> CGRect {
        let zone = zones[index]
        let unit = zone.unit
        // Never so deep that nothing is left, whatever the area: on a tiny one the gap just shrinks.
        let margin = min(gap, max((min(area.width, area.height) - 2) / 2, 0))
        let canvas = area.insetBy(dx: margin, dy: margin)
        let half = margin / 2
        var left = canvas.minX + unit.minX * canvas.width
        var right = canvas.minX + unit.maxX * canvas.width
        var upper = canvas.maxY - unit.minY * canvas.height
        var lower = canvas.maxY - unit.maxY * canvas.height
        if zone.shares.contains(.left) { left += half }
        if zone.shares.contains(.right) { right -= half }
        if zone.shares.contains(.top) { upper -= half }
        if zone.shares.contains(.bottom) { lower += half }
        // Each edge is rounded on its own, so two windows that share an edge still share it (and keep exactly the gap
        // between them: both are the same edge moved by half the gap, a whole number of points for 0, 8 and 16).
        let minX = left.rounded(), minY = lower.rounded()
        return CGRect(x: minX, y: minY, width: max(right.rounded() - minX, 1), height: max(upper.rounded() - minY, 1))
    }
}

/// One place a layout puts a window.
nonisolated struct SnapZone: Equatable, Sendable {
    /// The sides of a zone that face another window's zone.
    struct Sides: OptionSet, Sendable {
        let rawValue: Int
        static let left = Sides(rawValue: 1)
        static let right = Sides(rawValue: 2)
        static let top = Sides(rawValue: 4)
        static let bottom = Sides(rawValue: 8)
    }

    /// As fractions of the area (0 to 1, y grows down, as a picture).
    let unit: CGRect
    /// Sides where another window sits when the layout is used fully, so a gap is left between them.
    let shares: Sides

    /// The edges a window that does not fit this zone stays against: the one the zone touches, or the middle for a zone
    /// that touches neither side. A zone that touches both sides (the whole width) counts as leading, where the title bar is.
    var anchor: SnapAnchor {
        let epsilon: CGFloat = 1e-9
        return SnapAnchor(
            horizontal: unit.minX < epsilon ? .leading : (unit.maxX > 1 - epsilon ? .trailing : .centre),
            vertical: unit.minY < epsilon ? .top : (unit.maxY > 1 - epsilon ? .bottom : .centre)
        )
    }

    init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, shares: Sides = []) {
        unit = CGRect(x: x, y: y, width: width, height: height)
        self.shares = shares
    }
}

/// Space between windows, and between a window and the edge of the visible area.
nonisolated enum SnapGap: Int, Codable, CaseIterable, Sendable {
    case none = 0
    case small = 8
    case large = 16

    var points: CGFloat { CGFloat(rawValue) }
}

/// What the user chose in Settings: the layouts that get a tile, in the tiles' order, and the gap.
nonisolated struct SnapOptions: Equatable, Sendable {
    let layouts: [SnapLayout]
    let gap: SnapGap

    /// `storedLayouts` are the ids the setting keeps. Ids no layout has are ignored, and nothing left means all of them:
    /// no tile at all would make the module do nothing without saying why.
    init(storedLayouts: [String], gap: SnapGap) {
        let chosen = SnapLayout.allCases.filter { storedLayouts.contains($0.rawValue) }
        layouts = chosen.isEmpty ? SnapLayout.allCases : chosen
        self.gap = gap
    }
}

/// Which edges of its zone a window is kept against when it turns out bigger (or smaller) than the zone.
nonisolated struct SnapAnchor: Equatable, Sendable {
    enum Horizontal: Sendable { case leading, centre, trailing }
    enum Vertical: Sendable { case top, centre, bottom }

    let horizontal: Horizontal
    let vertical: Vertical
}

/// Where a window goes: its zone, the visible area of its display and the edges it is anchored to, all in Accessibility
/// coordinates (y grows down). The size is only a request: an app may keep a smallest or a fixed size, so where the window
/// really goes is decided once its size is known (`origin(for:)`).
nonisolated struct SnapPlacement: Equatable, Sendable {
    let frame: CGRect
    /// What the display leaves visible once the menu bar and the Dock are out.
    let area: CGRect
    let anchor: SnapAnchor

    /// Where a window of `size` goes: against the anchored edges of the zone, then moved back inside the visible area if
    /// it sticks out of it. A window too big for the area starts at its top left corner, where its title bar is.
    func origin(for size: CGSize) -> CGPoint {
        let x = switch anchor.horizontal {
        case .leading: frame.minX
        case .centre: frame.midX - size.width / 2
        case .trailing: frame.maxX - size.width
        }
        let y = switch anchor.vertical {
        case .top: frame.minY
        case .centre: frame.midY - size.height / 2
        case .bottom: frame.maxY - size.height
        }
        return CGPoint(
            x: Self.inside(x.rounded(), length: size.width, from: area.minX, to: area.maxX),
            y: Self.inside(y.rounded(), length: size.height, from: area.minY, to: area.maxY)
        )
    }

    private static func inside(_ start: CGFloat, length: CGFloat, from low: CGFloat, to high: CGFloat) -> CGFloat {
        length >= high - low ? low : min(max(start, low), high - length)
    }
}

/// Accessibility positions are not AppKit's.
nonisolated enum SnapSpace {
    /// `rect` (AppKit: origin at the bottom left of the primary display, y up) in Accessibility coordinates (origin at
    /// the top left of the primary display, y down). `primaryHeight` is the primary display's height.
    static func accessibilityFrame(of rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
