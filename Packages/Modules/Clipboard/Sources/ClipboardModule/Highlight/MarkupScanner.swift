import Foundation

/// The two languages that are mostly text with marks in it, so they get a scanner of their own: XML and HTML by tags,
/// Markdown by lines.
nonisolated enum MarkupScanner {
    // MARK: XML and HTML

    /// Tags: the brackets are punctuation, the tag name a keyword, attribute values strings; comments and CDATA as such.
    static func xml(_ bytes: UnsafeBufferPointer<UInt8>) -> [CodeToken] {
        var tokens: [CodeToken] = []
        var index = 0
        func matches(_ text: StaticString) -> Bool {
            guard index + text.utf8CodeUnitCount <= bytes.count else { return false }
            return (0..<text.utf8CodeUnitCount).allSatisfy { bytes[index + $0] == text.utf8Start[$0] }
        }
        func skip(to end: StaticString) {
            while index < bytes.count, !matches(end) { index += 1 }
            index = min(index + end.utf8CodeUnitCount, bytes.count)
        }
        func isNameByte(_ byte: UInt8) -> Bool {
            byte >= 0x80 || byte == UInt8(ascii: "_") || byte == UInt8(ascii: "-") || byte == UInt8(ascii: ":") || byte == UInt8(ascii: ".")
                || (byte | 0x20 >= UInt8(ascii: "a") && byte | 0x20 <= UInt8(ascii: "z")) || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9"))
        }
        while index < bytes.count {
            guard bytes[index] == UInt8(ascii: "<") else {
                index += 1
                continue
            }
            let start = index
            if matches("<!--") {
                skip(to: "-->")
                tokens.append(CodeToken(kind: .comment, range: start..<index))
                continue
            }
            if matches("<![CDATA[") {
                skip(to: "]]>")
                tokens.append(CodeToken(kind: .string, range: start..<index))
                continue
            }
            let opener: StaticString = matches("</") ? "</" : matches("<?") ? "<?" : matches("<!") ? "<!" : "<"
            let afterOpener = index + opener.utf8CodeUnitCount
            // "a < b" in text is not a tag.
            guard afterOpener < bytes.count, isNameByte(bytes[afterOpener]) else {
                index += 1
                continue
            }
            tokens.append(CodeToken(kind: .punctuation, range: start..<afterOpener))
            index = afterOpener
            while index < bytes.count, isNameByte(bytes[index]) { index += 1 }
            tokens.append(CodeToken(kind: .keyword, range: afterOpener..<index))
            while index < bytes.count, bytes[index] != UInt8(ascii: ">"), bytes[index] != UInt8(ascii: "<") {
                let byte = bytes[index]
                if byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "'") {
                    let quoteStart = index
                    index += 1
                    while index < bytes.count, bytes[index] != byte { index += 1 }
                    index = min(index + 1, bytes.count)
                    tokens.append(CodeToken(kind: .string, range: quoteStart..<index))
                } else if byte == UInt8(ascii: "="), !matches("=>") {
                    tokens.append(CodeToken(kind: .punctuation, range: index..<index + 1))
                    index += 1
                } else if (byte == UInt8(ascii: "/") || byte == UInt8(ascii: "?")), index + 1 < bytes.count, bytes[index + 1] == UInt8(ascii: ">") {
                    break
                } else {
                    index += 1
                }
            }
            if index < bytes.count, bytes[index] != UInt8(ascii: "<") {
                let closerStart = index
                if bytes[index] != UInt8(ascii: ">") { index += 1 }
                index += 1
                tokens.append(CodeToken(kind: .punctuation, range: closerStart..<min(index, bytes.count)))
            }
        }
        return tokens
    }

    // MARK: Markdown

    /// Headings and fenced blocks as a whole, quotes as comments, list marks as punctuation and `code` spans as strings.
    static func markdown(_ bytes: UnsafeBufferPointer<UInt8>) -> [CodeToken] {
        var tokens: [CodeToken] = []
        var fence: (start: Int, marker: UInt8)?
        var lineStart = 0
        while lineStart < bytes.count {
            var lineEnd = lineStart
            while lineEnd < bytes.count, bytes[lineEnd] != UInt8(ascii: "\n"), bytes[lineEnd] != UInt8(ascii: "\r") { lineEnd += 1 }
            let line = lineStart..<lineEnd
            var first = lineStart
            while first < lineEnd, bytes[first] == UInt8(ascii: " ") || bytes[first] == UInt8(ascii: "\t") { first += 1 }
            let marker = fenceMarker(bytes, at: first, end: lineEnd)
            if let open = fence {
                if let marker, marker == open.marker {
                    tokens.append(CodeToken(kind: .string, range: open.start..<lineEnd))
                    fence = nil
                }
            } else if let marker {
                fence = (first, marker)
            } else if isHeading(bytes, at: first, end: lineEnd) {
                tokens.append(CodeToken(kind: .keyword, range: first..<lineEnd))
            } else if first < lineEnd, bytes[first] == UInt8(ascii: ">") {
                tokens.append(CodeToken(kind: .comment, range: first..<lineEnd))
            } else {
                var contentStart = first
                if isBullet(bytes, at: first, end: lineEnd) {
                    tokens.append(CodeToken(kind: .punctuation, range: first..<first + 1))
                    contentStart = first + 1
                }
                codeSpans(bytes, in: contentStart..<line.upperBound, into: &tokens)
            }
            lineStart = lineEnd
            while lineStart < bytes.count, bytes[lineStart] == UInt8(ascii: "\n") || bytes[lineStart] == UInt8(ascii: "\r") { lineStart += 1 }
        }
        if let open = fence { tokens.append(CodeToken(kind: .string, range: open.start..<bytes.count)) }
        return tokens
    }

    /// "```" or "~~~" at the start of a line.
    private static func fenceMarker(_ bytes: UnsafeBufferPointer<UInt8>, at start: Int, end: Int) -> UInt8? {
        guard start + 3 <= end else { return nil }
        let byte = bytes[start]
        guard byte == UInt8(ascii: "`") || byte == UInt8(ascii: "~"), bytes[start + 1] == byte, bytes[start + 2] == byte else { return nil }
        return byte
    }

    /// One to six "#" and a space.
    private static func isHeading(_ bytes: UnsafeBufferPointer<UInt8>, at start: Int, end: Int) -> Bool {
        var index = start
        while index < end, bytes[index] == UInt8(ascii: "#") { index += 1 }
        return (1...6).contains(index - start) && index < end && bytes[index] == UInt8(ascii: " ")
    }

    private static func isBullet(_ bytes: UnsafeBufferPointer<UInt8>, at start: Int, end: Int) -> Bool {
        guard start + 1 < end, bytes[start + 1] == UInt8(ascii: " ") else { return false }
        return bytes[start] == UInt8(ascii: "-") || bytes[start] == UInt8(ascii: "*") || bytes[start] == UInt8(ascii: "+")
    }

    /// Text between a run of backticks and the next run of the same length on the line.
    private static func codeSpans(_ bytes: UnsafeBufferPointer<UInt8>, in range: Range<Int>, into tokens: inout [CodeToken]) {
        var index = range.lowerBound
        while index < range.upperBound {
            guard bytes[index] == UInt8(ascii: "`") else {
                index += 1
                continue
            }
            let start = index
            while index < range.upperBound, bytes[index] == UInt8(ascii: "`") { index += 1 }
            let length = index - start
            var search = index
            var closed: Int?
            while search < range.upperBound, closed == nil {
                guard bytes[search] == UInt8(ascii: "`") else {
                    search += 1
                    continue
                }
                let runStart = search
                while search < range.upperBound, bytes[search] == UInt8(ascii: "`") { search += 1 }
                if search - runStart == length { closed = search }
            }
            if let closed {
                tokens.append(CodeToken(kind: .string, range: start..<closed))
                index = closed
            }
        }
    }
}
