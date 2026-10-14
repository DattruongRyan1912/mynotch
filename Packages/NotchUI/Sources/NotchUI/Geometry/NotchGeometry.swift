import CoreGraphics
import MyNotchCore

nonisolated public enum NotchKind: Equatable, Sendable { case hardware, virtual }

/// Pure size and placement math for one screen's notch.
nonisolated public struct NotchGeometry: Equatable, Sendable {
    public static let maxOpenWidth: CGFloat = 720
    public static let hitPadding: CGFloat = 8
    /// Padding of the hit area while a drag with data is in progress, so the panel accepts the drop.
    public static let dragHitPadding: CGFloat = 40
    /// Tallest strip under the collapsed notch. The panel never resizes and holds `NotchTab.heightRange.upperBound`
    /// below the notch, so a strip this tall always fits inside it.
    public static let maxBottomHeight: CGFloat = 80
    /// Most the collapsed notch can grow downward for anything (a strip or the list): what the panel holds below it.
    static let maxExtraHeight: CGFloat = NotchTab.heightRange.upperBound

    public let kind: NotchKind
    /// Size of the physical (or virtual) notch body.
    public let notchSize: CGSize
    /// Horizontal offset of the notch centre from the screen centre (hardware notches can be asymmetric).
    public let centerOffset: CGFloat
    public let config: NotchLayoutConfig

    public init(screen: ScreenDescriptor, config: NotchLayoutConfig) {
        self.config = config
        if screen.safeAreaTop > 0, let left = screen.auxiliaryTopLeftWidth, let right = screen.auxiliaryTopRightWidth,
           screen.frame.width - left - right > 0 {
            kind = .hardware
            let width = screen.frame.width - left - right
            notchSize = CGSize(width: width, height: screen.safeAreaTop)
            centerOffset = left + width / 2 - screen.frame.width / 2
        } else {
            kind = .virtual
            let width = min(max(config.virtualNotchWidth, 120), 300)
            let height = min(max(config.virtualNotchHeight ?? screen.menuBarHeight, 24), 40)
            notchSize = CGSize(width: width, height: height)
            centerOffset = 0
        }
    }

    public func cornerRadii(for state: NotchState) -> (top: CGFloat, bottom: CGFloat) {
        state.isExpanded ? (8, 24) : (6, 10)
    }

    /// How far the shape grows downward for an activity's strip: only the collapsed notch with an activity shows one
    /// (an expanded notch already shows its tab), and never more than `maxBottomHeight`.
    public func bottomHeight(for state: NotchState, requested: CGFloat) -> CGFloat {
        guard state == .compact, requested > 0 else { return 0 }
        return min(requested, Self.maxBottomHeight)
    }

    /// Full shape size, including the top "ears" that blend into the menu bar. `bottomHeight` is how far the collapsed
    /// notch grows downward, for the strip or the open list (see `bottomHeight(for:strip:listRows:)`); other states ignore it.
    public func shapeSize(for state: NotchState, contentHeight: CGFloat = NotchTab.defaultHeight, bottomHeight: CGFloat = 0) -> CGSize {
        let ears = 2 * cornerRadii(for: state).top
        switch state {
        case .closed:
            return CGSize(width: notchSize.width + ears, height: notchSize.height)
        case .compact:
            return CGSize(
                width: notchSize.width + ears + 2 * config.compactSideWidth,
                height: notchSize.height + self.extraHeight(for: state, requested: bottomHeight)
            )
        case .open, .toast:
            let width = min(max(config.openWidth, 480), Self.maxOpenWidth)
            let content = min(max(contentHeight, NotchTab.heightRange.lowerBound), NotchTab.heightRange.upperBound)
            return CGSize(width: width, height: notchSize.height + content)
        }
    }

    /// A height already resolved by `bottomHeight(for:strip:listRows:)`, held to what the fixed panel has below the notch.
    private func extraHeight(for state: NotchState, requested: CGFloat) -> CGFloat {
        guard state == .compact, requested > 0 else { return 0 }
        return min(requested, Self.maxExtraHeight)
    }

    /// Fixed panel size: the largest the notch can ever get.
    public var panelSize: CGSize {
        CGSize(width: Self.maxOpenWidth, height: notchSize.height + NotchTab.heightRange.upperBound)
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

    /// Area (screen coordinates) where the pointer counts as "inside" the notch.
    public func hitRect(
        for state: NotchState, contentHeight: CGFloat = NotchTab.defaultHeight, bottomHeight: CGFloat = 0, in screenFrame: CGRect
    ) -> CGRect {
        paddedRect(for: state, contentHeight: contentHeight, bottomHeight: bottomHeight, padding: Self.hitPadding, in: screenFrame)
    }

    /// The enlarged hit area used while something is being dragged.
    public func dragHitRect(
        for state: NotchState, contentHeight: CGFloat = NotchTab.defaultHeight, bottomHeight: CGFloat = 0, in screenFrame: CGRect
    ) -> CGRect {
        paddedRect(for: state, contentHeight: contentHeight, bottomHeight: bottomHeight, padding: Self.dragHitPadding, in: screenFrame)
    }

    private func paddedRect(
        for state: NotchState, contentHeight: CGFloat, bottomHeight: CGFloat, padding: CGFloat, in screenFrame: CGRect
    ) -> CGRect {
        let size = shapeSize(for: state, contentHeight: contentHeight, bottomHeight: bottomHeight)
        let padded = CGRect(
            x: screenFrame.midX + centerOffset - size.width / 2,
            y: screenFrame.maxY - size.height,
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
