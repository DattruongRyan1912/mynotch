import CoreGraphics
import MyNotchCore

nonisolated public enum NotchKind: Equatable, Sendable { case hardware, virtual }

/// Pure size and placement math for one screen's notch.
nonisolated public struct NotchGeometry: Equatable, Sendable {
    public static let maxOpenWidth: CGFloat = 720
    public static let hitPadding: CGFloat = 8

    public let kind: NotchKind
    /// Size of the physical (or virtual) notch body.
    public let notchSize: CGSize
    public let config: NotchLayoutConfig

    public init(screen: ScreenDescriptor, config: NotchLayoutConfig) {
        self.config = config
        if screen.safeAreaTop > 0, let left = screen.auxiliaryTopLeftWidth, let right = screen.auxiliaryTopRightWidth {
            kind = .hardware
            notchSize = CGSize(width: screen.frame.width - left - right, height: screen.safeAreaTop)
        } else {
            kind = .virtual
            let width = min(max(config.virtualNotchWidth, 120), 300)
            let height = min(max(config.virtualNotchHeight ?? screen.menuBarHeight, 24), 40)
            notchSize = CGSize(width: width, height: height)
        }
    }

    public func cornerRadii(for state: NotchState) -> (top: CGFloat, bottom: CGFloat) {
        state.isExpanded ? (8, 24) : (6, 10)
    }

    /// Full shape size, including the top "ears" that blend into the menu bar.
    public func shapeSize(for state: NotchState, contentHeight: CGFloat = NotchTab.defaultHeight) -> CGSize {
        let ears = 2 * cornerRadii(for: state).top
        switch state {
        case .closed:
            return CGSize(width: notchSize.width + ears, height: notchSize.height)
        case .compact:
            return CGSize(width: notchSize.width + ears + 2 * config.compactSideWidth, height: notchSize.height)
        case .open, .toast:
            let width = min(max(config.openWidth, 480), Self.maxOpenWidth)
            let content = min(max(contentHeight, NotchTab.heightRange.lowerBound), NotchTab.heightRange.upperBound)
            return CGSize(width: width, height: notchSize.height + content)
        }
    }

    /// Fixed panel size: the largest the notch can ever get.
    public var panelSize: CGSize {
        CGSize(width: Self.maxOpenWidth, height: notchSize.height + NotchTab.heightRange.upperBound)
    }

    /// Panel frame anchored to the top centre of `screenFrame` (AppKit coordinates).
    public func panelFrame(in screenFrame: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.midX - panelSize.width / 2,
            y: screenFrame.maxY - panelSize.height,
            width: panelSize.width,
            height: panelSize.height
        )
    }

    /// Area (screen coordinates) where the pointer counts as "inside" the notch.
    public func hitRect(for state: NotchState, contentHeight: CGFloat = NotchTab.defaultHeight, in screenFrame: CGRect) -> CGRect {
        let size = shapeSize(for: state, contentHeight: contentHeight)
        return CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        ).insetBy(dx: -Self.hitPadding, dy: -Self.hitPadding)
    }
}
