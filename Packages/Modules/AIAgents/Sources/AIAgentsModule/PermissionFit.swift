import AgentHookKit
import Foundation

/// Where a permission card is drawn, which says how much of a request fits on it.
nonisolated enum PermissionPlacement: Equatable, Sendable {
    /// Under the closed notch.
    case strip
    /// At the top of the AI tab.
    case tab

    var limits: PermissionFit.Limits {
        switch self {
        case .strip: PermissionFit.strip
        case .tab: PermissionFit.tab
        }
    }
}

/// Whether a request's text is on the card in full, without scrolling: the rule for offering "Cho phép". It is a model of
/// the lines the text takes, written to be an upper bound of what SwiftUI draws at the narrowest width the card gets, so a
/// text it lets through is never partly out of view. The text is drawn in the monospaced 11 pt font, so a column is the same
/// width for every ASCII character; anything else is counted as more, and anything that draws nothing is never let through.
nonisolated enum PermissionFit {
    nonisolated struct Limits: Equatable, Sendable {
        /// The lines the card shows.
        let lines: Int
        /// How many columns a line holds at the narrowest width the card gets.
        let columns: Int
    }

    /// More than the widest ASCII character of the font takes (6.8 pt), so a line holds no more columns than the model says.
    static let glyphWidth = 7.0
    /// The narrowest the strip gets: a virtual notch is at least 120 pt wide, with its two ears (6 pt each) and its two
    /// sides (64 pt each), less the strip's padding of 12 pt on both sides. A test compares these with the notch's own numbers.
    static let stripWidth: Double = {
        let notch = 120.0, ears = 2 * 6.0, sides = 2 * 64.0, padding = 2 * 12.0
        return notch + ears + sides - padding
    }()
    /// The narrowest the AI tab gets: the open notch is at least 480 pt wide, less its padding (14 pt a side) and the card's (8 pt).
    static let tabWidth = 420.0

    /// Two lines fit the strip, which has no room for more.
    static let strip = Limits(lines: 2, columns: Int(stripWidth / glyphWidth))
    static let tab = Limits(lines: 6, columns: Int(tabWidth / glyphWidth))

    /// True when `text` is drawn in at most `limits.lines` lines whatever the width, down to the narrowest, so all of it is
    /// on the card. A blank line is a line, and a run of spaces takes the columns it is.
    static func fits(_ text: String, in limits: Limits) -> Bool {
        var lines = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let taken = linesTaken(by: line, columns: limits.columns) else { return false }
            lines += taken
            if lines > limits.lines { return false }
        }
        return true
    }

    /// An upper bound of the lines `line` is drawn in when it wraps at `columns`; nil for a line that cannot be bounded or
    /// holds a character that is not safe to show.
    ///
    /// A line that fits is one line. A longer one wraps at spaces, and breaks before a word only when the word does not fit,
    /// so when no word is longer than half a line, every line but the last holds more than half a line, and the line is at
    /// most `ceil(2 * columnsOfTheLine / columns)` lines. With a longer word there is no bound.
    static func linesTaken(by line: Substring, columns: Int) -> Int? {
        var total = 0
        var word = 0
        var longest = 0
        for character in line {
            guard let width = width(of: character) else { return nil }
            total += width
            if character == " " {
                word = 0
            } else {
                word += width
                longest = max(longest, word)
            }
        }
        if total <= columns { return 1 }
        guard longest * 2 <= columns else { return nil }
        return (2 * total + columns - 1) / columns
    }

    /// The columns a character takes, at most; nil for one that draws nothing, or something else than it is. ASCII is one
    /// (6.8 pt in the font), an emoji three (16 pt), the tab eight, any other character two (the widest measured, a kana,
    /// is 10.4 pt).
    private static func width(of character: Character) -> Int? {
        let scalars = character.unicodeScalars
        // More than a few scalars in one character is a pile of combining marks.
        guard scalars.count <= 4, !scalars.contains(where: HookText.isInvisible) else { return nil }
        if character == "\t" { return 8 }
        if character.isASCII { return 1 }
        return scalars.contains(where: { $0.properties.isEmoji || $0.value >= 0x1F000 }) ? 3 : 2
    }
}
