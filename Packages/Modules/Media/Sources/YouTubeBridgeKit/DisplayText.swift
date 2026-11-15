import Foundation

/// Text that comes from outside (a page, a player's notification) and is shown as it is in a chip, the notch and the lock screen, made
/// safe to show: it cannot be longer than the place for it, hold a control character, or turn the order of the text around.
public enum DisplayText {
    /// Control characters and the marks that set the direction of text (the embeddings, overrides and isolates, the left-to-right and
    /// right-to-left marks, the Arabic letter mark): the latter can make a line read as another one.
    private static func isDropped(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x00...0x08, 0x0B, 0x0C, 0x0E...0x1F, 0x7F...0x9F: true
        case 0x061C, 0x200E, 0x200F, 0x202A...0x202E, 0x2066...0x2069: true
        default: false
        }
    }

    /// `text` with runs of whitespace (newlines and tabs included) as one space, no control or direction marks, trimmed, and at most
    /// `limit` characters.
    public static func clean(_ text: String, limit: Int) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: text.unicodeScalars.filter { !isDropped($0) })
        let collapsed = String(scalars).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(collapsed.prefix(limit)).trimmingCharacters(in: .whitespaces)
    }
}
