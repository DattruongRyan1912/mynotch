import CoreGraphics

/// What is left of a zone once the windows beside it are out of the way.
nonisolated enum SnapRoom: Equatable, Sendable {
    /// No neighbour reaches into the zone.
    case whole
    /// The biggest part of the zone no neighbour covers, a gap away from each of them.
    case part(SnapPlacement)
    /// Next to nothing is left: not worth a window.
    case crowded
}

nonisolated extension SnapPlacement {
    /// Overlap this small is the rounding apps do to a size, not a window in the way.
    static let overlapTolerance: CGFloat = 0.5
    /// The least of the zone's width and height that a part must keep to be worth a window.
    static let smallestShare: CGFloat = 0.25
    /// A window this much bigger than the zone has kept a size of its own (apps round sizes to whole points or cells).
    static let oversizeTolerance: CGFloat = 2

    /// Which way a window of `size` is bigger than a zone of `zone`.
    static func overflow(of size: CGSize, in zone: CGSize) -> (wide: Bool, tall: Bool) {
        (size.width - zone.width > oversizeTolerance, size.height - zone.height > oversizeTolerance)
    }

    func isOversize(_ size: CGSize) -> Bool {
        let overflow = Self.overflow(of: size, in: frame.size)
        return overflow.wide || overflow.tall
    }

    /// The zone minus the frames of `neighbours` (where their windows really are, which may reach past their own zones),
    /// with `gap` between them and what is left. Where a neighbour splits the zone the biggest part stays, so a window that
    /// kept a wider size takes its side of the zone and the next one gets the other. Edges are rounded away from the
    /// neighbour, so a fraction of a point never leaves the two overlapping.
    func room(beside neighbours: [CGRect], gap: CGFloat) -> SnapRoom {
        var free = frame
        var reached = false
        for neighbour in neighbours {
            let clear = neighbour.insetBy(dx: -gap, dy: -gap)
            let overlap = free.intersection(clear)
            guard overlap.width > Self.overlapTolerance, overlap.height > Self.overlapTolerance else { continue }
            reached = true
            // Right of it, left of it, below it and above it (y grows down).
            let parts = [
                Self.part(left: clear.maxX.rounded(.up), top: free.minY, right: free.maxX, bottom: free.maxY),
                Self.part(left: free.minX, top: free.minY, right: clear.minX.rounded(.down), bottom: free.maxY),
                Self.part(left: free.minX, top: clear.maxY.rounded(.up), right: free.maxX, bottom: free.maxY),
                Self.part(left: free.minX, top: free.minY, right: free.maxX, bottom: clear.minY.rounded(.down)),
            ].compactMap { $0 }
            guard let largest = parts.max(by: { $0.width * $0.height < $1.width * $1.height }) else { return .crowded }
            free = largest
        }
        guard reached else { return .whole }
        guard free.width >= frame.width * Self.smallestShare, free.height >= frame.height * Self.smallestShare else { return .crowded }
        return .part(SnapPlacement(frame: free, area: area, anchor: anchor))
    }

    private static func part(left: CGFloat, top: CGFloat, right: CGFloat, bottom: CGFloat) -> CGRect? {
        right > left && bottom > top ? CGRect(x: left, y: top, width: right - left, height: bottom - top) : nil
    }
}
