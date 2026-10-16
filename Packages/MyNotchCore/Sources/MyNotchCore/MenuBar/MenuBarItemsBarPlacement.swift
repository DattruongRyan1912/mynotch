import CoreGraphics

/// The sizes of what the bar holds. The window is as big as its content, up to the display's width, past which the content scrolls.
nonisolated public enum MenuBarItemsBarMetrics {
    /// Around the row of items.
    public static let padding: CGFloat = 8
    /// Between two items.
    public static let spacing: CGFloat = 2
    /// The height of an item's button.
    public static let cellHeight: CGFloat = 28
    /// The width of the button of an item shown as its app's icon.
    public static let iconCellWidth: CGFloat = 28
    /// What the bar's window is while it holds a message instead of items.
    public static let messageSize = CGSize(width: 300, height: cellHeight + 2 * padding)

    /// The window's size for buttons of these widths; the message's size when there are none.
    public static func contentSize(cellWidths: [CGFloat]) -> CGSize {
        guard !cellWidths.isEmpty else { return messageSize }
        let width = cellWidths.reduce(0, +) + spacing * CGFloat(cellWidths.count - 1) + 2 * padding
        return CGSize(width: width, height: cellHeight + 2 * padding)
    }
}

/// Where the bar's window goes.
nonisolated public enum MenuBarItemsBarPlacement {
    /// Kept clear of the display's left and right edges.
    public static let margin: CGFloat = 8
    /// Between the menu bar and the bar.
    public static let gap: CGFloat = 4

    /// The window's frame (AppKit coordinates): directly under the menu bar of the display the MyNotch icon is on, with its right
    /// edge under the icon's, or centred on that display when right-aligned it would stick out past the left margin. Never wider
    /// than the display less its margins, so a long row scrolls. With no icon on a bar, the first display (the one with the menu bar).
    public static func frame(content: CGSize, anchor: CGRect?, screens: [MenuBarScreen]) -> CGRect {
        let index = anchor.flatMap { MenuBarOrder.screenIndex(of: $0, in: screens) }
        guard let screen = index.map({ screens[$0] }) ?? screens.first else { return CGRect(origin: .zero, size: content) }
        let display = screen.frame
        let width = min(content.width, display.width - 2 * margin)
        let y = display.maxY - screen.barHeight - gap - content.height
        if index != nil, let anchor {
            let right = min(anchor.maxX, display.maxX - margin)
            if right - width >= display.minX + margin {
                return CGRect(x: right - width, y: y, width: width, height: content.height)
            }
        }
        return CGRect(x: display.midX - width / 2, y: y, width: width, height: content.height)
    }
}
