import AppKit

/// How much room a translation takes in the chip, measured with the font the chip draws in: all of it, wrapped, up to about
/// eight lines; past that it scrolls inside the chip. The chip never grows taller than `maxHeight`, nor than the room beside
/// the selection, so it never covers what it is about.
nonisolated enum SelectionChipLayout {
    /// The widest a chip is, padding included.
    static let maxWidth: CGFloat = 360
    static let sidePadding: CGFloat = 10
    static let maxTextWidth = maxWidth - 2 * sidePadding
    static let minTextWidth: CGFloat = 200
    /// The tallest a chip is, in points.
    static let maxHeight: CGFloat = 280
    static let maxLines = 8
    /// Around the text: 10 pt of padding above and below, the row with the button and the menu (24), and the gap above that row.
    static let chromeHeight: CGFloat = 48
    /// The small caption over the text, with its gap.
    static let captionHeight: CGFloat = 17
    /// A caption is only shown when it leaves at least this many lines for the translation.
    static let linesWorthACaption = 4
    static let minLines = 2

    static func font() -> NSFont { .systemFont(ofSize: 12, weight: .medium) }

    /// The height of one line of the translation.
    static var lineHeight: CGFloat { ceil(NSLayoutManager().defaultLineHeight(for: font())) }

    struct Metrics: Equatable, Sendable {
        var textWidth: CGFloat
        /// The height of the text area, in whole lines: all the text, or `maxLines` (less when there is little room).
        var textHeight: CGFloat
        /// There is more text than the area shows.
        var scrolls: Bool
        var showsCaption: Bool

        var chipHeight: CGFloat {
            textHeight + SelectionChipLayout.chromeHeight + (showsCaption ? SelectionChipLayout.captionHeight : 0)
        }
    }

    /// - Parameter maxHeight: the most the whole chip may take: `maxHeight`, or the room beside the selection when that is less.
    static func metrics(for text: String, caption: String?, maxHeight: CGFloat = SelectionChipLayout.maxHeight) -> Metrics {
        let line = lineHeight
        let width = textWidth(of: text)
        let lines = lineCount(of: text, width: width)
        let withCaption = maxHeight - chromeHeight - captionHeight
        let showsCaption = caption != nil && Int(withCaption / line) >= linesWorthACaption
        let room = maxHeight - chromeHeight - (showsCaption ? captionHeight : 0)
        let allowed = min(maxLines, max(minLines, Int(room / line)))
        return Metrics(textWidth: width, textHeight: CGFloat(min(lines, allowed)) * line, scrolls: lines > allowed, showsCaption: showsCaption)
    }

    /// As wide as the longest line, within the narrowest and the widest the chip is.
    private static func textWidth(of text: String) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font()]
        let widest = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { NSAttributedString(string: String($0), attributes: attributes).size().width }
            .max() ?? 0
        return min(max(ceil(widest) + 2, minTextWidth), maxTextWidth)
    }

    private static func lineCount(of text: String, width: CGFloat) -> Int {
        let box = NSAttributedString(string: text, attributes: [.font: font()]).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin]
        )
        let exact = NSLayoutManager().defaultLineHeight(for: font())
        return max(1, Int((box.height / exact).rounded()))
    }
}
