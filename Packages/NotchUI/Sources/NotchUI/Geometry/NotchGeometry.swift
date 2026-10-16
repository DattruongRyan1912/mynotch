import CoreGraphics
import MyNotchCore

nonisolated public enum NotchKind: Equatable, Sendable { case hardware, virtual }

/// Pure size and placement math for one screen's notch.
nonisolated public struct NotchGeometry: Equatable, Sendable {
    /// Narrowest and widest the open notch can be; the Interface setting moves between them.
    public static let openWidthLimits: ClosedRange<CGFloat> = 480...900
    public static let maxOpenWidth: CGFloat = openWidthLimits.upperBound
    /// The most height the open notch gives the content of a tab, which is the most a tab may ask for
    /// (`NotchTab.heightRange`, which `ModuleRegistry` holds every tab to), so no tab is cut. The panel holds it below the
    /// notch.
    public static let maxContentHeight: CGFloat = NotchTab.heightRange.upperBound
    public static let hitPadding: CGFloat = 8
    /// Padding of the hit area while a drag with data is in progress, so the panel accepts the drop.
    public static let dragHitPadding: CGFloat = 40
    /// Tallest strip under the collapsed notch. The panel never resizes and holds `maxContentHeight`
    /// below the notch, so a strip this tall always fits inside it.
    public static let maxBottomHeight: CGFloat = 80
    /// Most the collapsed notch can grow downward for anything (a strip or the list), well inside what the panel holds below it.
    static let maxExtraHeight: CGFloat = maxContentHeight
    /// How far a floating pill sits below the top edge of the screen. The menu bar of a display without a notch is 24 pt at the least, so
    /// 5 pt is a clear sliver of the bar above the pill (it never reads as touching the edge, with a point to spare for rounding on a
    /// 1x display) and still inside the top fifth of the band, so the pill reads as part of the menu bar's row and not as a window
    /// dropped on the content below it.
    public static let pillTopGap: CGFloat = 5
    /// The radius of all four corners of the open pill: the open notch's own bottom radius, so the content's tile, which is
    /// `NotchTokens.padding` inside it, comes out concentric.
    public static let pillOpenRadius: CGFloat = 24
    /// The widest a strip makes the collapsed notch, however much it asks for (and not wider than the open notch): so it stays on the
    /// screen with room beside it for its bubbles. A strip that wants more scales its text down a little and is cut off after that.
    public static let stripWidthLimit: CGFloat = 560

    public let kind: NotchKind
    /// Size of the physical (or virtual) notch body.
    public let notchSize: CGSize
    /// Horizontal offset of the notch centre from the screen centre (hardware notches can be asymmetric).
    public let centerOffset: CGFloat
    public let config: NotchLayoutConfig
    /// Width of the open notch: the setting held to `openWidthLimits` and to the screen, so it never spills off a small display.
    public let openWidth: CGFloat
    /// How the notch is drawn: the setting on a display without a notch, and always the notch on one that has it.
    public let style: VirtualNotchStyle

    /// Whether the notch is a floating pill.
    public var isPill: Bool { style == .pill }

    /// How far below the top of the open notch's shape the tab page starts. A hardware notch keeps the cutout's own height free there, since
    /// the camera is in it. A display without a notch has no cutout, so nothing is kept free: the page starts the padding below the top, the
    /// same distance as from the other three edges (which, on a pill, makes the content concentric with all four rounded corners). The
    /// shape grows from the collapsed notch in place either way, with its top fixed.
    public var openTopInset: CGFloat { kind == .hardware ? notchSize.height : NotchTokens.padding }

    /// How far the shape's top is below the top edge of the screen: the pill's gap, nothing for the notch, which sticks to the edge.
    public var topGap: CGFloat { isPill ? Self.pillTopGap : 0 }

    /// Whether the open notch is made of tiles.
    public var opensAsTiles: Bool { config.opensAsTiles }

    /// The width of the collapsed notch with an activity but no strip: the notch's body, the ears and the two sides the activity's leading
    /// and trailing views have.
    public var compactWidth: CGFloat { notchSize.width + 2 * cornerRadii(for: .compact).top + 2 * config.compactSideWidth }

    /// The widest a strip makes the collapsed notch: `stripWidthLimit` held to the open notch's width, and never below the collapsed notch's
    /// own.
    public var maximumStripWidth: CGFloat { max(compactWidth, min(openWidth, Self.stripWidthLimit)) }

    /// The width of the collapsed notch while its strip wants `stripWidth` for what it shows (0 when it does not say): what it wants and
    /// the padding the notch gives it (the ears and `NotchTokens.stripPadding`), never narrower than `compactWidth` and never wider
    /// than `maximumStripWidth`. A strip that says nothing leaves it as it is.
    public func compactWidth(stripWidth: CGFloat) -> CGFloat {
        guard stripWidth > 0 else { return compactWidth }
        let wanted = stripWidth + 2 * cornerRadii(for: .compact).top + 2 * NotchTokens.stripPadding
        return min(max(wanted, compactWidth), maximumStripWidth)
    }

    /// How much taller the open notch is for its tiles, with `tabCount` tabs: the tile's own inset around the content, and the capsule
    /// for the tab bar with the gap under it, over what the tab bar takes in one piece. The tab gets the room it gets in one piece, and
    /// not less. Nothing when the notch is not made of tiles.
    public func tilesChrome(tabCount: Int) -> CGFloat {
        opensAsTiles ? NotchTilesLayout.extraHeight(tabCount: tabCount) : 0
    }

    public init(screen: ScreenDescriptor, config: NotchLayoutConfig) {
        self.config = config
        let limits = Self.openWidthLimits
        openWidth = min(max(config.openWidth, limits.lowerBound), min(limits.upperBound, max(screen.frame.width, limits.lowerBound)))
        if screen.safeAreaTop > 0, let left = screen.auxiliaryTopLeftWidth, let right = screen.auxiliaryTopRightWidth,
           screen.frame.width - left - right > 0 {
            kind = .hardware
            style = .notch
            let width = screen.frame.width - left - right
            notchSize = CGSize(width: width, height: screen.safeAreaTop)
            centerOffset = left + width / 2 - screen.frame.width / 2
        } else {
            kind = .virtual
            style = config.virtualNotchStyle
            let width = min(max(config.virtualNotchWidth, 120), 300)
            let height = min(max(config.virtualNotchHeight ?? screen.menuBarHeight, 24), 40)
            notchSize = CGSize(width: width, height: height)
            centerOffset = 0
        }
    }

    /// The notch's radii: `top` is the radius of the ears, which is also how far the shape's wall is inset from the edge of its frame
    /// (so nothing is inset on a pill, which has no ears), and `bottom` the radius of the bottom corners. The pill's four corners are all
    /// `bottom`: half the body's height while it is collapsed (so a strip or the list under it does not balloon the radius), and
    /// `pillOpenRadius` when it is open.
    public func cornerRadii(for state: NotchState) -> (top: CGFloat, bottom: CGFloat) {
        if isPill { return (0, state.isExpanded ? Self.pillOpenRadius : notchSize.height / 2) }
        return state.isExpanded ? (8, 24) : (6, 10)
    }

    /// The outline of the notch in `state`: the notch's own with its ears, or the pill's all-round one.
    public func shape(for state: NotchState) -> NotchShape {
        let radii = cornerRadii(for: state)
        return NotchShape(topRadius: radii.top, bottomRadius: radii.bottom, cornerRadius: isPill ? radii.bottom : 0)
    }

    /// How far the shape grows downward for an activity's strip: only the collapsed notch with an activity shows one
    /// (an expanded notch already shows its tab), and never more than `maxBottomHeight`.
    public func bottomHeight(for state: NotchState, requested: CGFloat) -> CGFloat {
        guard state == .compact, requested > 0 else { return 0 }
        return min(requested, Self.maxBottomHeight)
    }

    /// Full shape size, including the top "ears" that blend into the menu bar. The open notch with tiles is taller by their chrome, which
    /// depends on `tabCount` (see `tilesChrome(tabCount:)`). `bottomHeight` is how far the collapsed
    /// notch grows downward, for the strip or the open list (see `bottomHeight(for:strip:listRows:)`); other states ignore it. With a
    /// `bottomHeight` the collapsed notch is as wide as the strip wants, `stripWidth` (see `compactWidth(stripWidth:)`); pass 0 under
    /// the open list, which is not a strip.
    public func shapeSize(
        for state: NotchState, contentHeight: CGFloat = NotchTab.defaultHeight, bottomHeight: CGFloat = 0, tabCount: Int = 1,
        stripWidth: CGFloat = 0
    ) -> CGSize {
        let ears = 2 * cornerRadii(for: state).top
        switch state {
        case .closed:
            return CGSize(width: notchSize.width + ears, height: notchSize.height)
        case .compact:
            // A strip that asks for a width gets it; with no strip (nothing under the notch, or the list) the notch is as wide as it was.
            return CGSize(
                width: compactWidth(stripWidth: bottomHeight > 0 ? stripWidth : 0),
                height: notchSize.height + self.extraHeight(for: state, requested: bottomHeight)
            )
        case .open, .toast:
            let content = min(max(contentHeight, NotchTab.heightRange.lowerBound), Self.maxContentHeight)
            return CGSize(width: openWidth, height: openTopInset + content + tilesChrome(tabCount: tabCount))
        }
    }

    /// A height already resolved by `bottomHeight(for:strip:listRows:)`, held to what the fixed panel has below the notch.
    private func extraHeight(for state: NotchState, requested: CGFloat) -> CGFloat {
        guard state == .compact, requested > 0 else { return 0 }
        return min(requested, Self.maxExtraHeight)
    }

    /// Fixed panel size: the largest the notch can ever get, whatever the size settings are (and the pill's gap above it). The open
    /// notch never needs more than the notch's height and the most a tab gets (`openTopInset` is at most the notch's height), and the
    /// list under the collapsed notch needs all of it, so a display without a notch has no smaller panel for the band its open notch no
    /// longer has; with tiles the open notch is taller by their chrome, and the panel with it.
    public var panelSize: CGSize {
        let open = openTopInset + Self.maxContentHeight + tilesChrome(tabCount: 2)
        return CGSize(width: Self.maxOpenWidth, height: topGap + max(notchSize.height + Self.maxContentHeight, open))
    }

    /// Panel frame anchored to the top centre of `screenFrame` (AppKit coordinates).
    public func panelFrame(in screenFrame: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.midX + centerOffset - panelSize.width / 2,
            y: screenFrame.maxY - panelSize.height,
            width: panelSize.width,
            height: panelSize.height
        )
    }

    /// Where the content of the expanded notch (`.open` or `.toast`) starts, in screen coordinates (AppKit): under the
    /// notch's body (a hardware notch's cutout) or its padding (a display without one) and the pill's gap, inside the shape's rounded top
    /// corners and its padding, as wide as that leaves. `height` is the
    /// part the caller fills from the top; how much more room the notch has below depends on the content it shows, so
    /// nothing here relies on it. Mirrors how `NotchRootView` lays the expanded notch out; a test draws the view to keep
    /// the two together.
    public func contentFrame(height: CGFloat, in screenFrame: CGRect) -> CGRect {
        let width = shapeSize(for: .open(nil)).width
        let inset = cornerRadii(for: .open(nil)).top + NotchTokens.padding
        let top = screenFrame.maxY - topGap - openTopInset
        return CGRect(
            x: screenFrame.midX + centerOffset - width / 2 + inset, y: top - height, width: width - 2 * inset, height: height
        )
    }

    /// Area (screen coordinates) where the pointer counts as "inside" the notch. For the pill it reaches up through the gap to the top row of
    /// the screen, so moving the pointer to the top edge above the pill still opens it, and a click in the gap is a click on the notch.
    public func hitRect(
        for state: NotchState, contentHeight: CGFloat = NotchTab.defaultHeight, bottomHeight: CGFloat = 0, tabCount: Int = 1,
        stripWidth: CGFloat = 0, in screenFrame: CGRect
    ) -> CGRect {
        paddedRect(
            for: state, contentHeight: contentHeight, bottomHeight: bottomHeight, tabCount: tabCount, stripWidth: stripWidth,
            padding: Self.hitPadding, in: screenFrame
        )
    }

    /// The enlarged hit area used while something is being dragged.
    public func dragHitRect(
        for state: NotchState, contentHeight: CGFloat = NotchTab.defaultHeight, bottomHeight: CGFloat = 0, tabCount: Int = 1,
        stripWidth: CGFloat = 0, in screenFrame: CGRect
    ) -> CGRect {
        paddedRect(
            for: state, contentHeight: contentHeight, bottomHeight: bottomHeight, tabCount: tabCount, stripWidth: stripWidth,
            padding: Self.dragHitPadding, in: screenFrame
        )
    }

    private func paddedRect(
        for state: NotchState, contentHeight: CGFloat, bottomHeight: CGFloat, tabCount: Int, stripWidth: CGFloat, padding: CGFloat,
        in screenFrame: CGRect
    ) -> CGRect {
        let size = shapeSize(for: state, contentHeight: contentHeight, bottomHeight: bottomHeight, tabCount: tabCount, stripWidth: stripWidth)
        let padded = CGRect(
            x: screenFrame.midX + centerOffset - size.width / 2,
            y: screenFrame.maxY - topGap - size.height,
            width: size.width,
            height: size.height
        ).insetBy(dx: -padding, dy: -padding)
        // AppKit reports the pointer at y == maxY on a screen's top row; y == maxY + 1 already belongs
        // to a display arranged above, so the rect stops there (CGRect.contains excludes its top edge).
        return CGRect(x: padded.minX, y: padded.minY, width: padded.width, height: screenFrame.maxY + 1 - padded.minY)
    }
}

extension CGRect {
    /// Screen membership for `NSEvent.mouseLocation`: AppKit reports a screen's top row at `y == maxY`,
    /// so the top edge belongs to this screen and the bottom edge to the screen below.
    nonisolated public func containsMouseLocation(_ point: CGPoint) -> Bool {
        point.x >= minX && point.x < maxX && point.y > minY && point.y <= maxY
    }
}
