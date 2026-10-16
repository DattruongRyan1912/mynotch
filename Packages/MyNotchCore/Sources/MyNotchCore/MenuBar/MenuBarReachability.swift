import CoreGraphics

/// Where things are on the menu bars right now, which is what decides whether an item can be seen and clicked there.
nonisolated public struct MenuBarLayout: Equatable, Sendable {
    public var screens: [MenuBarScreen]
    /// The window of ‹, while it has its normal length; nil while it is long, when its window is 10 000 points wide and says nothing.
    public var hiddenSeparator: CGRect?
    /// The same for ‹‹.
    public var alwaysHiddenSeparator: CGRect?

    public init(screens: [MenuBarScreen], hiddenSeparator: CGRect? = nil, alwaysHiddenSeparator: CGRect? = nil) {
        self.screens = screens
        self.hiddenSeparator = hiddenSeparator
        self.alwaysHiddenSeparator = alwaysHiddenSeparator
    }
}

/// Why an item is in the bar.
nonisolated public enum MenuBarItemReason: Equatable, Sendable {
    /// Its window has no area, so there is nothing to see or click.
    case zeroSize
    /// It is outside every display's bar: pushed away by a long separator, or not drawn because the bar is full.
    case offScreen
    /// Its window is where the notch is, and macOS draws no status item there.
    case underNotch
    /// The user put it left of ‹.
    case hiddenSection
    /// The user put it left of ‹‹.
    case alwaysHiddenSection
}

nonisolated public struct MenuBarBarEntry: Equatable, Sendable, Identifiable {
    public let item: MenuBarItem
    public let reason: MenuBarItemReason
    public var id: String { item.id }

    public init(item: MenuBarItem, reason: MenuBarItemReason) {
        self.item = item
        self.reason = reason
    }
}

/// The rule for which items the bar holds, and in which order. Pure: the answer comes from frames alone.
nonisolated public enum MenuBarReachability {
    /// Why `frame` belongs in the bar, or nil when it can be seen and clicked on a bar and is in none of MyNotch's sections. The
    /// notch comes before the sections: an item behind it is out of reach whichever section it is in.
    public static func reason(for frame: CGRect, in layout: MenuBarLayout) -> MenuBarItemReason? {
        guard hasArea(frame) else { return .zeroSize }
        guard let index = MenuBarOrder.screenIndex(of: frame, in: layout.screens) else { return .offScreen }
        if isUnderNotch(frame, on: layout.screens[index]) { return .underNotch }
        if isLeft(frame, of: layout.alwaysHiddenSeparator, on: index, in: layout.screens) { return .alwaysHiddenSection }
        if isLeft(frame, of: layout.hiddenSeparator, on: index, in: layout.screens) { return .hiddenSection }
        return nil
    }

    /// Whether a click on `frame` would land on a status item that is drawn: on a bar and clear of the notch.
    public static func isClickable(_ frame: CGRect, in screens: [MenuBarScreen]) -> Bool {
        guard let index = MenuBarOrder.screenIndex(of: frame, in: screens) else { return false }
        return !isUnderNotch(frame, on: screens[index])
    }

    /// The items that belong in the bar, left to right as the menu bar lays them out. Items whose frames say nothing (no area)
    /// come last, and items at the same place keep the order the source gave them.
    public static func entries(from items: [MenuBarItem], layout: MenuBarLayout) -> [MenuBarBarEntry] {
        items
            .compactMap { item in reason(for: item.frame, in: layout).map { MenuBarBarEntry(item: item, reason: $0) } }
            .sorted { left, right in
                let leftX = hasArea(left.item.frame) ? left.item.frame.minX : .infinity
                let rightX = hasArea(right.item.frame) ? right.item.frame.minX : .infinity
                return leftX == rightX ? left.item.order < right.item.order : leftX < rightX
            }
    }

    private static func hasArea(_ frame: CGRect) -> Bool {
        !frame.isNull && frame.width > 0 && frame.height > 0
    }

    private static func isUnderNotch(_ frame: CGRect, on screen: MenuBarScreen) -> Bool {
        guard let gap = screen.notchGap else { return false }
        return frame.minX < gap.upperBound && frame.maxX > gap.lowerBound
    }

    /// Left of a separator's window, on the same display as it.
    private static func isLeft(_ frame: CGRect, of separator: CGRect?, on index: Int, in screens: [MenuBarScreen]) -> Bool {
        guard let separator, MenuBarOrder.screenIndex(of: separator, in: screens) == index else { return false }
        return frame.midX < separator.minX
    }
}
