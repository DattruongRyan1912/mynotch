import Foundation

/// What a permission request asks to do, in the words the card shows the user. The card offers "Cho phép" only when
/// the user can see all of it (`isComplete`), because an allow for something that was cut off is an allow for something
/// the user never read.
public struct PermissionDetail: Codable, Equatable, Sendable {
    /// The most of one request that is shown: more is cut at the end and the request is not complete.
    public static let maxLength = 1_000
    public static let maxLines = 20
    /// The longest tool name shown whole.
    public static let maxToolLength = 100

    /// As much as is shown, with the lines the helper ended with: a command, a path, a URL, the arguments of a tool or
    /// the files of a patch. Cut only at the end.
    public var text: String
    /// How many lines of the request are not in `text`, counting the rest of the line the cut fell in; 0 when `text` is all.
    public var hiddenLines: Int
    /// True only when `text` is everything the request asks for that matters: nothing was cut, and the helper knows the
    /// tool well enough to say what the part that matters is.
    public var isComplete: Bool

    public init(text: String, hiddenLines: Int, isComplete: Bool) {
        self.text = text
        self.hiddenLines = hiddenLines
        self.isComplete = isComplete
    }

    /// What the helper shows of a request of `tool` with this input. Only a few keys of the input are read, and only
    /// those that are the thing asked for, so what the model said about it (a description, a prompt) and the content of a
    /// file never travel on.
    static func describing(tool: String?, input: [String: Any]?) -> PermissionDetail {
        let text: String?
        switch tool {
        case "Bash":
            text = string(input?["command"])
        case "Write", "Edit", "MultiEdit", "Read", "NotebookEdit":
            text = string(input?["file_path"]) ?? string(input?["path"]) ?? string(input?["notebook_path"])
                ?? string(input?["command"]).flatMap(patchedFiles)
        case "WebFetch":
            text = string(input?["url"])
        case "WebSearch":
            text = string(input?["query"])
        case "apply_patch":
            text = string(input?["command"]).flatMap(patchedFiles)
        default:
            text = input.flatMap(arguments)
        }
        guard let text else { return PermissionDetail(text: "", hiddenLines: 0, isComplete: false) }
        let shown = cut(HookText.clean(text).trimmingCharacters(in: .whitespacesAndNewlines))
        return PermissionDetail(text: shown.kept, hiddenLines: shown.hiddenLines, isComplete: shown.hiddenLines == 0 && !shown.kept.isEmpty)
    }

    /// The text up to the limits and how many lines are left. The cut is at the end: a line is never skipped in the middle.
    static func cut(_ text: String) -> (kept: String, hiddenLines: Int) {
        var kept = ""
        var lines = 1
        var characters = 0
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "\n" {
                if lines == maxLines { break }
                lines += 1
            }
            if characters == maxLength { break }
            kept.append(text[index])
            characters += 1
            index = text.index(after: index)
        }
        guard index < text.endIndex else { return (text, 0) }
        var rest = text[index...]
        if rest.first == "\n" { rest = rest.dropFirst() }
        return (kept, rest.split(separator: "\n", omittingEmptySubsequences: false).count)
    }

    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return text
    }

    /// The tool's whole input, keys in a fixed order, so nothing that is asked for is left out whatever the tool is. Nil
    /// when the hook gave no input at all.
    private static func arguments(_ input: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(input),
              let data = try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys, .withoutEscapingSlashes])
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// The header lines of a Codex patch, which name each file it adds, changes, deletes or moves; not what it writes.
    /// Nil when there is none, since then nothing says which files it is about.
    private static func patchedFiles(_ patch: String) -> String? {
        let headers = ["*** Add File: ", "*** Update File: ", "*** Delete File: ", "*** Move to: "]
        let lines = HookText.clean(patch).split(separator: "\n", omittingEmptySubsequences: true).filter { line in
            headers.contains { line.hasPrefix($0) }
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}

/// What the helper does to text before it is shown: the characters that could make it read differently from what a
/// shell or a file system sees, or draw nothing at all, are replaced by a visible one, so they cannot hide anything.
public enum HookText {
    private static let replacement: Unicode.Scalar = "\u{FFFD}"
    /// A run of combining marks longer than this is cut: a few are a letter with accents, hundreds smear the lines around.
    static let maxMarksInARun = 3

    /// True for a character that draws nothing or something else than it is, other than the plain space, the tab and
    /// the line feed: control and format characters (an escape, a direction override, a zero-width space), every space
    /// but the plain one (no-break space, em space, ideographic space), the characters that Unicode says are ignorable
    /// when drawn (the Hangul fillers, variation selectors, combining grapheme joiner), the Braille blank, and the code
    /// points that mean nothing in themselves (private use, unassigned, surrogates).
    public static func isInvisible(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "\n", "\t", " ": return false
        case "\u{2800}": return true
        default: break
        }
        if scalar.properties.isDefaultIgnorableCodePoint { return true }
        switch scalar.properties.generalCategory {
        case .control, .format, .spaceSeparator, .lineSeparator, .paragraphSeparator, .privateUse, .surrogate, .unassigned: return true
        default: return false
        }
    }

    /// Line endings as `\n`; every invisible character as U+FFFD; a run of combining marks cut after a few; the tab, the
    /// plain space and everything else as it came.
    public static func clean(_ text: String) -> String {
        var result = String.UnicodeScalarView()
        var afterReturn = false
        var marks = 0
        for scalar in text.unicodeScalars {
            defer { afterReturn = scalar == "\r" }
            switch scalar {
            case "\r", "\u{2028}", "\u{2029}", "\u{85}":
                result.append("\n")
                marks = 0
            case "\n":
                if !afterReturn { result.append("\n") }
                marks = 0
            default:
                if isInvisible(scalar) {
                    result.append(replacement)
                    marks = 0
                } else if scalar.properties.generalCategory == .nonspacingMark || scalar.properties.generalCategory == .enclosingMark {
                    marks += 1
                    result.append(marks > maxMarksInARun ? replacement : scalar)
                } else {
                    result.append(scalar)
                    marks = 0
                }
            }
        }
        return String(result)
    }

    /// For what is shown on one line, a tool name or a folder: line breaks become spaces.
    public static func cleanLine(_ text: String) -> String {
        clean(text).replacingOccurrences(of: "\n", with: " ")
    }
}
