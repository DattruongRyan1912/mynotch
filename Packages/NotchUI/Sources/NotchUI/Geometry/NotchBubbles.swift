import CoreGraphics
import MyNotchCore

/// The part of the notch the pointer is over.
nonisolated public enum PointerZone: Equatable, Sendable {
    case outside
    /// The notch itself: the collapsed pill and its strip, or the open notch.
    case notch
    /// One of the bubbles beside the collapsed notch (or the gap between two).
    case bubbles
    /// The list of all live activities under the collapsed notch.
    case list
}

/// Where the bubbles beside the collapsed notch and the list under it go, and which of them the pointer is over. All of
/// it lives inside the fixed panel: nothing here changes the pill's shape or the panel's frame.
nonisolated extension NotchGeometry {
    /// Gap between the pill's body and the first bubble, and between two bubbles.
    public static let bubbleGap: CGFloat = 6
    /// Most bubbles beside the notch: more activities end the row with a "+N" bubble.
    public static let maxBubbles = 2
    public static let listRowHeight: CGFloat = 28
    /// Space above the first and below the last row of the list.
    public static let listInset: CGFloat = 6
    /// Most rows the list shows; more end it with a "+N" row.
    public static let maxListRows = 8

    /// A bubble is a circle as tall as the collapsed notch's body.
    public var bubbleDiameter: CGFloat { notchSize.height }

    /// Right edge of the collapsed pill's body (inside its ears), from the notch's centre line.
    private var compactBodyRight: CGFloat { shapeSize(for: .compact).width / 2 - cornerRadii(for: .compact).top }

    /// Where bubble `index` goes, from the notch's centre line (x grows right) and the top edge of the screen (y grows
    /// down), the way SwiftUI lays it out. A bubble is as tall as the pill's body and starts at the pill's top (the gap below the edge),
    /// so it is centred on it.
    public func bubbleFrame(at index: Int) -> CGRect {
        let diameter = bubbleDiameter
        return CGRect(
            x: compactBodyRight + Self.bubbleGap + CGFloat(index) * (diameter + Self.bubbleGap), y: topGap, width: diameter, height: diameter
        )
    }

    /// The same frame in screen coordinates (AppKit, y grows up).
    public func bubbleScreenFrame(at index: Int, in screenFrame: CGRect) -> CGRect {
        let frame = bubbleFrame(at: index)
        return CGRect(
            x: screenFrame.midX + centerOffset + frame.minX, y: screenFrame.maxY - frame.maxY, width: frame.width, height: frame.height
        )
    }

    /// How many bubbles fit beside the collapsed pill inside the panel, which never resizes: `maxBubbles` unless the
    /// pill is so wide that the last one would stick out of it.
    public var bubbleCapacity: Int {
        (0..<Self.maxBubbles).prefix { bubbleFrame(at: $0).maxX <= panelSize.width / 2 }.count
    }

    /// Height of the list for `rows` rows (at most `maxListRows`); 0 for none.
    public func listHeight(rows: Int) -> CGFloat {
        rows > 0 ? CGFloat(min(rows, Self.maxListRows)) * Self.listRowHeight + 2 * Self.listInset : 0
    }

    /// How far the collapsed notch grows downward: the open list, which takes the strip's place, else the strip. The
    /// view and the window controller both ask this, so the drawn shape and the hit area cannot disagree.
    public func bottomHeight(for state: NotchState, strip: CGFloat, listRows: Int) -> CGFloat {
        guard state == .compact else { return 0 }
        return listRows > 0 ? listHeight(rows: listRows) : bottomHeight(for: state, requested: strip)
    }

    /// What `point` (screen coordinates) is over. In the collapsed notch the list wins, then the bubbles, then the pill;
    /// every other state has only the notch's own area. Hit areas get the usual padding, except on the pill's side of the
    /// first bubble, so the pill keeps its edge. While a drag with data is over the notch only its drag area counts.
    public func pointerZone(
        at point: CGPoint, state: NotchState, contentHeight: CGFloat = NotchTab.defaultHeight, strip: CGFloat = 0,
        bubbles: Int = 0, listRows: Int = 0, dragging: Bool = false, tabCount: Int = 1, in screenFrame: CGRect
    ) -> PointerZone {
        let bottom = bottomHeight(for: state, strip: strip, listRows: listRows)
        if dragging {
            return dragHitRect(for: state, contentHeight: contentHeight, bottomHeight: bottom, tabCount: tabCount, in: screenFrame)
                .contains(point) ? .notch : .outside
        }
        guard state == .compact else {
            return hitRect(for: state, contentHeight: contentHeight, tabCount: tabCount, in: screenFrame).contains(point) ? .notch : .outside
        }
        let centre = screenFrame.midX + centerOffset
        let pill = shapeSize(for: .compact)
        if listRows > 0 {
            let list = CGRect(
                x: centre - pill.width / 2 - Self.hitPadding,
                y: screenFrame.maxY - topGap - pill.height - listHeight(rows: listRows) - Self.hitPadding,
                width: pill.width + 2 * Self.hitPadding, height: listHeight(rows: listRows) + Self.hitPadding
            )
            if list.contains(point) { return .list }
        }
        if bubbles > 0 {
            let last = bubbleScreenFrame(at: min(bubbles, Self.maxBubbles) - 1, in: screenFrame)
            let first = bubbleScreenFrame(at: 0, in: screenFrame)
            // Down to the padding under the bubbles and up to the row above the screen's top edge, like the pill's rect.
            let area = CGRect(
                x: first.minX, y: first.minY - Self.hitPadding, width: last.maxX + Self.hitPadding - first.minX,
                height: screenFrame.maxY + 1 - (first.minY - Self.hitPadding)
            )
            if area.contains(point) { return .bubbles }
        }
        let pillBottom = listRows > 0 ? 0 : bottom
        return hitRect(for: .compact, bottomHeight: pillBottom, in: screenFrame).contains(point) ? .notch : .outside
    }
}
