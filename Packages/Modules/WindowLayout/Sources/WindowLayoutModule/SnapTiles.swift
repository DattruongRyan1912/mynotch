import CoreGraphics

/// Which zone of which layout a drop would use.
nonisolated struct SnapTarget: Equatable, Sendable {
    let layout: SnapLayout
    let zone: Int

    /// Where the window goes on a display whose visible area is `area` (AppKit coordinates).
    func frame(in area: CGRect, gap: CGFloat) -> CGRect {
        layout.frame(zone: zone, in: area, gap: gap)
    }
}

/// The row of layout tiles in the open notch and which zone of which tile the pointer is over. The view draws the row
/// from `frames` and the module hit-tests with `target`, so the highlight and the drop cannot disagree. Coordinates are
/// AppKit's (y grows up); the row is anchored at the top of the notch's content, whose height the notch decides.
nonisolated enum SnapTiles {
    /// Fits the least room a tab can leave (`NotchTab.heightRange`'s 120 pt minus the notch's padding below).
    static let height: CGFloat = 88
    static let spacing: CGFloat = 8
    /// A row of two tiles stays this wide each instead of stretching over the notch.
    static let maxWidth: CGFloat = 112
    /// Between a tile's edge and the picture of the layout.
    static let glyphInset: CGFloat = 8
    /// Width over height of the picture: a screen.
    static let glyphAspect: CGFloat = 1.6

    /// Where `count` tiles go inside `content`: equal widths up to `maxWidth`, centred.
    static func frames(count: Int, in content: CGRect) -> [CGRect] {
        guard count > 0 else { return [] }
        let gaps = CGFloat(count - 1) * spacing
        let width = min(maxWidth, (content.width - gaps) / CGFloat(count))
        let total = CGFloat(count) * width + gaps
        let start = content.midX - total / 2
        return (0..<count).map { CGRect(x: start + CGFloat($0) * (width + spacing), y: content.minY, width: width, height: content.height) }
    }

    /// The picture of the layout inside `tile`, at its top; the title has the rest.
    static func glyphFrame(in tile: CGRect) -> CGRect {
        let width = tile.width - 2 * glyphInset
        let height = width / glyphAspect
        return CGRect(x: tile.minX + glyphInset, y: tile.maxY - glyphInset - height, width: width, height: height)
    }

    /// What `point` is over: the tile it is in, and in a tile of several zones the zone under it, as drawn in the
    /// picture. Over the title (below the picture) the zones of the picture's bottom edge count, so a tile is as easy to
    /// hit as it looks. Nil between tiles and outside the row.
    static func target(at point: CGPoint, layouts: [SnapLayout], content: CGRect) -> SnapTarget? {
        let frames = frames(count: layouts.count, in: content)
        guard let index = frames.firstIndex(where: { $0.contains(point) }) else { return nil }
        let layout = layouts[index]
        guard layout.zones.count > 1 else { return SnapTarget(layout: layout, zone: 0) }
        let glyph = glyphFrame(in: frames[index])
        let x = min(max((point.x - glyph.minX) / glyph.width, 0), 1)
        let y = min(max((glyph.maxY - point.y) / glyph.height, 0), 1)
        let zone = layout.zones.indices.first { layout.zones[$0].unit.contains(inclusive: CGPoint(x: x, y: y)) } ?? 0
        return SnapTarget(layout: layout, zone: zone)
    }
}

nonisolated private extension CGRect {
    /// Edges count, so a point exactly between two zones belongs to the first one.
    func contains(inclusive point: CGPoint) -> Bool {
        point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }
}
