import CoreGraphics

/// The sizes of what the bar holds. The window is as big as its content, up to the display's width, past which the content scrolls.
nonisolated public enum MenuBarItemsBarMetrics {
    /// Around the row of items.
    public static let padding: CGFloat = 4
    /// Between two items.
    public static let spacing: CGFloat = 2
    /// The height of an item's button.
    public static let cellHeight: CGFloat = 28
    /// The width of an item's button.
    public static let iconCellWidth: CGFloat = 24
    /// The app's icon in its button.
    public static let iconSize: CGFloat = 18
    /// The bar's corners.
    public static let cornerRadius: CGFloat = 10
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
    public static let gap: CGFloat = 0

    /// The window's frame (AppKit coordinates): directly on the menu bar of the display the MyNotch icon is on, to the left of the
    /// MyNotch icon, or bounded before the notch gap or display margin so a long row scrolls. With no icon on a bar, placed at the
    /// right edge of the first display.
    public static func frame(content: CGSize, anchor: CGRect?, screens: [MenuBarScreen]) -> CGRect {
        let index = anchor.flatMap { MenuBarOrder.screenIndex(of: $0, in: screens) }
        guard let screen = index.map({ screens[$0] }) ?? screens.first else { return CGRect(origin: .zero, size: content) }
        let display = screen.frame
        let validAnchor = index != nil ? anchor : nil
        let height = (validAnchor?.height).flatMap { $0 > 0 ? $0 : nil } ?? screen.barHeight
        let y = validAnchor?.minY ?? (display.maxY - height)

        let right = validAnchor.map { min($0.minX, display.maxX - margin) } ?? (display.maxX - margin)
        let minX: CGFloat
        if let notchGap = screen.notchGap, right > notchGap.upperBound {
            minX = max(display.minX + margin, notchGap.upperBound + margin)
        } else {
            minX = display.minX + margin
        }
        let maxAvailableWidth = max(right - minX, 44)
        let width = min(content.width, maxAvailableWidth)
        let x = max(minX, right - width)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
