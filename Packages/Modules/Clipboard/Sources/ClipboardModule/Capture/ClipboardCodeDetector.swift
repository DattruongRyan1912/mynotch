import Foundation

/// Tells code from prose with cheap rules: no model, no network, and only the first 4 KB is read, so it costs the same
/// for a 4 KB snippet and a 2 MB copy. Documents with a shape of their own (JSON, XML, SQL, CSS, YAML, Markdown, a
/// script with a shebang) are recognised by it; anything else needs most of its lines to look like code.
nonisolated enum ClipboardCodeDetector {
    /// How much of a text is looked at.
    static let sampleBytes = 4096
    /// Above this a JSON text is judged by its beginning and its last character instead of parsing it all.
    static let jsonParseLimit = 64 * 1024

    /// nil for anything that is not a text.
    static func detect(_ content: ClipboardContent) -> CodeDetection? {
        switch content {
        case .text(let text), .richText(let text, _): detect(text: text)
        case .link, .color, .image, .files: nil
        }
    }

    static func detect(text: String) -> CodeDetection {
        let sample = DetectionSample(text)
        guard let first = sample.lines.first?.text else { return .notCode }
        if first.hasPrefix("#!") { return .code(shebangLanguage(first)) }
        if first.hasPrefix("<?php") { return .code(.php) }
        if looksLikeJSON(sample, of: text) { return .code(.json) }
        if looksLikeXML(sample, of: text) { return .code(.xml) }
        let fences = sample.fenceCount
        if fences >= 2 || (fences == 1 && sample.isCut) { return .code(.markdown) }
        if SQLShape.matches(sample) { return .code(.sql) }
        if CSSShape.matches(sample) { return .code(.css) }
        if looksLikeYAML(sample) { return .code(.yaml) }
        if looksLikeMarkdown(sample) { return .code(.markdown) }
        guard CodeLineScore.isCode(sample.lines) else { return .notCode }
        return .code(CodeLanguageGuess.guess(sample))
    }

    private static func shebangLanguage(_ line: String) -> CodeLanguage {
        let interpreters: [(String, CodeLanguage)] = [("python", .python), ("ruby", .ruby), ("node", .javascript), ("php", .php)]
        return interpreters.first { line.contains($0.0) }?.1 ?? .shell
    }

    /// A whole text that parses (judged by its edges when it is large), as an object with a key or a list of two or more.
    private static func looksLikeJSON(_ sample: DetectionSample, of text: String) -> Bool {
        guard let open = sample.lines.first?.text.first, open == "{" || open == "[",
              let close = text.last(where: { !$0.isWhitespace }), close == (open == "{" ? "}" : "]") else { return false }
        guard text.utf8.count <= jsonParseLimit else { return sample.text.containsAnyBytes(["\":", "\" :"]) }
        switch try? JSONSerialization.jsonObject(with: Data(text.utf8)) {
        case let object as [String: Any]: return !object.isEmpty
        case let array as [Any]: return array.count >= 2 || array.first is [String: Any]
        default: return false
        }
    }

    /// Starts with a tag, a declaration or a comment, ends with ">", and closes something in between.
    private static func looksLikeXML(_ sample: DetectionSample, of text: String) -> Bool {
        guard let first = sample.lines.first?.text, first.hasPrefix("<"), text.last(where: { !$0.isWhitespace }) == ">" else { return false }
        if first.hasPrefix("<?xml") || first.hasPrefix("<!") { return true }
        guard first.dropFirst().first?.isLetter == true else { return false }
        return sample.text.containsAnyBytes(["</", "/>"])
    }

    /// At least three lines, nearly all of them `key: value`, `- item` or comments, with two or more keys. A key is a plain
    /// ASCII word, so Vietnamese notes such as "Ghi chú: …" stay prose.
    private static func looksLikeYAML(_ sample: DetectionSample) -> Bool {
        guard sample.lines.count >= 3 else { return false }
        let allowedOther = sample.lines.count * 15 / 100
        var keys = 0, other = 0
        for line in sample.lines {
            let text = line.text
            if text == "---" || text.hasPrefix("#") { continue }
            let isItem = text.hasPrefix("- ")
            let body = isItem ? text.dropFirst(2).drop { $0 == " " } : Substring(text)
            if let value = yamlValue(afterKeyIn: body) {
                guard !value.hasSuffix(";"), !value.hasSuffix(","), !value.hasSuffix("{") else { return false }
                keys += 1
            } else if !isItem || text.hasSuffix(";") || text.hasSuffix(",") {
                other += 1
                // Prose and code fail on their first lines, so most texts stop here.
                if other > allowedOther { return false }
            }
        }
        return keys >= 2
    }

    /// What follows "key:" when the text starts with a plain key, nil otherwise.
    private static func yamlValue(afterKeyIn text: Substring) -> Substring? {
        let key = text.prefix { $0.isASCII && ($0.isLetter || $0.isNumber || "_.-/".contains($0)) }
        guard let start = key.first, start.isLetter || start == "_" else { return nil }
        let rest = text.dropFirst(key.count)
        guard rest.first == ":", rest.dropFirst().first.map({ $0 == " " }) ?? true else { return nil }
        return rest.dropFirst().drop { $0 == " " }
    }

    /// A heading plus something else that only Markdown has. A heading alone is also a comment in many languages.
    private static func looksLikeMarkdown(_ sample: DetectionSample) -> Bool {
        guard sample.lines.contains(where: { $0.text.hasPrefix("#") && isHeading($0.text) }) else { return false }
        var headings = 0, others = 0
        for line in sample.lines {
            let text = line.text
            if isHeading(text) {
                headings += 1
            } else if text.hasPrefix("- ") || text.hasPrefix("* ") || text.hasPrefix("> ") || text.hasPrefix("|") || isNumbered(text)
                        || text.contains("](") || text.contains("**") {
                others += 1
            }
        }
        return headings >= 1 && others >= 1
    }

    private static func isHeading(_ text: String) -> Bool {
        let hashes = text.prefix { $0 == "#" }.count
        return (1...6).contains(hashes) && text.dropFirst(hashes).first == " " && text.dropFirst(hashes).contains { !$0.isWhitespace }
    }

    private static func isNumbered(_ text: String) -> Bool {
        let digits = text.prefix { $0.isASCII && $0.isNumber }
        return !digits.isEmpty && text.dropFirst(digits.count).hasPrefix(". ")
    }
}

/// The part of a text that is looked at: whole lines of its first 4 KB, with the blank ones left out.
nonisolated struct DetectionSample {
    struct Line {
        /// Without the indentation or the end of line.
        let text: String
        /// Columns of indentation; a tab counts as four.
        let indent: Int
    }

    /// The first 4 KB, cut at its last line break when the text was longer.
    let text: String
    let isCut: Bool
    let lines: [Line]

    private static let maxLines = 150

    init(_ full: String) {
        let utf8 = full.utf8
        isCut = utf8.count > ClipboardCodeDetector.sampleBytes
        var head = isCut ? String(decoding: utf8.prefix(ClipboardCodeDetector.sampleBytes), as: UTF8.self) : full
        if isCut {
            // The cut may split a character or a line; a half line would look like code or prose it is not.
            if let end = head.lastIndex(where: \.isNewline) { head = String(head[..<end]) }
            while head.last == "\u{FFFD}" { head.removeLast() }
        }
        text = head
        lines = head.split(whereSeparator: \.isNewline).prefix(Self.maxLines).compactMap { raw in
            let leading = raw.prefix { $0 == " " || $0 == "\t" }
            var text = raw.dropFirst(leading.count)
            while let last = text.last, last == " " || last == "\t" { text = text.dropLast() }
            guard !text.isEmpty else { return nil }
            return Line(text: String(text), indent: leading.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) })
        }
    }

    var fenceCount: Int {
        lines.count { $0.text.hasPrefix("```") || $0.text.hasPrefix("~~~") }
    }
}
