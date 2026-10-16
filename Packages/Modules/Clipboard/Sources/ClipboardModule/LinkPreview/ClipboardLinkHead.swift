import Foundation

/// What the `<head>` of a page says that MyNotch wants: its title and where its picture may be. Only the head is read (the bytes up to
/// `</head>` or `<body`), as plain tags: nothing is run, no script is looked into, no `<base>` is believed.
nonisolated struct ClipboardLinkHead: Equatable, Sendable {
    /// The `<title>`, or failing that `og:title`, made plain; nil when neither says anything.
    var title: String?
    /// The `og:image` address, absolute and http or https; nil when there is none or it is not one.
    var openGraphImage: URL?
    /// The pages' icons, absolute and http or https, the biggest kind first. Never an SVG, which the image decoder cannot read.
    var icons: [URL]

    /// The longest address taken from a page.
    static let urlLimit = 2_048

    /// Parses `body`, the start of the page at `pageURL` (relative addresses are made absolute against it). `contentType` is the header,
    /// which may name the text encoding.
    static func parse(_ body: Data, contentType: String?, pageURL: URL) -> ClipboardLinkHead {
        let text = decoded(headBytes(of: body), contentType: contentType)
        var scanner = TagScanner(Array(text.utf8))
        var title: String?
        var openGraphTitle: String?
        var image: String?
        var icons: [(rank: Int, address: String)] = []
        while let tag = scanner.next() {
            switch tag.name {
            case "title" where title == nil:
                title = scanner.rawText(until: "title")
            case "meta":
                let key = (tag.attributes["property"] ?? tag.attributes["name"])?.lowercased()
                guard let content = tag.attributes["content"] else { continue }
                switch key {
                case "og:image", "og:image:secure_url", "og:image:url": image = image ?? content
                case "og:title": openGraphTitle = openGraphTitle ?? content
                default: break
                }
            case "link":
                guard let href = tag.attributes["href"], let rel = tag.attributes["rel"] else { continue }
                let words = Set(rel.lowercased().split(whereSeparator: \.isWhitespace).map(String.init))
                let isTouchIcon = words.contains("apple-touch-icon") || words.contains("apple-touch-icon-precomposed")
                guard isTouchIcon || words.contains("icon") else { continue }
                if tag.attributes["type"]?.lowercased().contains("svg") == true { continue }
                icons.append((isTouchIcon ? 0 : 1, href))
            default: break
            }
        }
        // Stable: the page's own order is kept inside each kind.
        let ordered = icons.enumerated().sorted { ($0.element.rank, $0.offset) < ($1.element.rank, $1.offset) }.map(\.element.address)
        return ClipboardLinkHead(
            title: (title ?? openGraphTitle).flatMap(ClipboardLinkText.title(from:)),
            openGraphImage: image.flatMap { address(of: $0, relativeTo: pageURL) },
            icons: ordered.compactMap { address(of: $0, relativeTo: pageURL) }.filter { !$0.path(percentEncoded: false).lowercased().hasSuffix(".svg") }
        )
    }

    /// An absolute http or https address for what an attribute says (entities decoded, as in a page); nil for anything else (`data:`,
    /// `javascript:`, nothing).
    static func address(of value: String, relativeTo base: URL) -> URL? {
        absolute(ClipboardLinkText.decodingEntities(value), relativeTo: base)
    }

    /// The same for text that has no entities in it, such as a `Location` header.
    static func absolute(_ text: String, relativeTo base: URL) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= urlLimit, let url = URL(string: trimmed, relativeTo: base)?.absoluteURL,
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    // MARK: Bytes

    /// Everything before `</head` or `<body`, whichever comes first, in either case.
    static func headBytes(of body: Data) -> Data {
        let bytes = [UInt8](body)
        let end = ["</head", "<body"].compactMap { ClipboardLinkBytes.find(Array($0.utf8), in: bytes) }.min() ?? bytes.count
        return Data(bytes[0..<end])
    }

    /// The header's `charset`, else the page's own `<meta charset>` (looked for in the first 2 KB as plain ASCII), else UTF-8; a text
    /// that is not valid in the encoding found is read as Latin-1, which accepts every byte.
    static func decoded(_ bytes: Data, contentType: String?) -> String {
        let encoding = charset(inHeader: contentType) ?? charset(inPage: bytes.prefix(2_048)) ?? .utf8
        return String(data: bytes, encoding: encoding) ?? String(data: bytes, encoding: .isoLatin1) ?? ""
    }

    private static func charset(inHeader header: String?) -> String.Encoding? {
        guard let header, let range = header.range(of: "charset=", options: .caseInsensitive) else { return nil }
        let name = header[range.upperBound...].prefix { $0 != ";" && !$0.isWhitespace }.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return encoding(named: name)
    }

    private static func charset(inPage bytes: Data) -> String.Encoding? {
        let ascii = String(decoding: bytes.map { $0 < 0x80 ? $0 : 0x3F }, as: UTF8.self)
        guard let range = ascii.range(of: "charset=", options: .caseInsensitive) else { return nil }
        let name = ascii[range.upperBound...].drop { $0 == "\"" || $0 == "'" || $0 == " " }
            .prefix { $0 != "\"" && $0 != "'" && $0 != ";" && $0 != ">" && $0 != "/" && !$0.isWhitespace }
        return encoding(named: String(name))
    }

    private static func encoding(named name: String) -> String.Encoding? {
        guard !name.isEmpty else { return nil }
        let cf = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        guard cf != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
    }
}

// MARK: Tags

/// A tag as the head's scanner reports it: the name in lower case and the attributes by lower-case name, their values as written (entities
/// not yet decoded).
private nonisolated struct Tag {
    var name: String
    var attributes: [String: String]
}

/// Walks the tags of a head. Comments are skipped; the text of `<script>`, `<style>` and `<template>` is skipped, since a tag-shaped
/// string in it is not a tag; a closing tag is not reported.
private nonisolated struct TagScanner {
    private let bytes: [UInt8]
    private var position = 0

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    /// The next opening tag, or nil at the end.
    mutating func next() -> Tag? {
        while let open = index(of: UInt8(ascii: "<"), from: position) {
            position = open + 1
            if matches("!--", at: position) {
                position = (find("-->", from: position + 3) ?? bytes.count) + 3
                continue
            }
            if position < bytes.count, bytes[position] == UInt8(ascii: "/") || bytes[position] == UInt8(ascii: "!") || bytes[position] == UInt8(ascii: "?") {
                skipTag()
                continue
            }
            guard position < bytes.count, isLetter(bytes[position]) else { continue }
            let name = readName()
            let attributes = readAttributes()
            if ["script", "style", "template"].contains(name) {
                position = find("</\(name)", from: position) ?? bytes.count
                skipTag()
                continue
            }
            return Tag(name: name, attributes: attributes)
        }
        return nil
    }

    /// The text up to the closing tag of `name` (the scanner's position is after the opening tag), which is skipped.
    mutating func rawText(until name: String) -> String {
        let end = find("</\(name)", from: position) ?? bytes.count
        let text = String(decoding: bytes[position..<end], as: UTF8.self)
        position = end
        skipTag()
        return text
    }

    // MARK: Reading

    private mutating func readName() -> String {
        let start = position
        while position < bytes.count, isLetter(bytes[position]) || isDigit(bytes[position]) || bytes[position] == UInt8(ascii: "-") || bytes[position] == UInt8(ascii: ":") {
            position += 1
        }
        return String(decoding: bytes[start..<position], as: UTF8.self).lowercased()
    }

    /// `name`, `name=value`, `name="value"` and `name='value'` up to the `>` that ends the tag.
    private mutating func readAttributes() -> [String: String] {
        var attributes: [String: String] = [:]
        while position < bytes.count {
            while position < bytes.count, isSpace(bytes[position]) || bytes[position] == UInt8(ascii: "/") { position += 1 }
            guard position < bytes.count else { break }
            if bytes[position] == UInt8(ascii: ">") {
                position += 1
                break
            }
            let start = position
            while position < bytes.count, !isSpace(bytes[position]), bytes[position] != UInt8(ascii: "="), bytes[position] != UInt8(ascii: ">"),
                  bytes[position] != UInt8(ascii: "/") {
                position += 1
            }
            let name = String(decoding: bytes[start..<position], as: UTF8.self).lowercased()
            while position < bytes.count, isSpace(bytes[position]) { position += 1 }
            var value = ""
            if position < bytes.count, bytes[position] == UInt8(ascii: "=") {
                position += 1
                while position < bytes.count, isSpace(bytes[position]) { position += 1 }
                value = readValue()
            }
            if !name.isEmpty, attributes[name] == nil { attributes[name] = value }
        }
        return attributes
    }

    private mutating func readValue() -> String {
        guard position < bytes.count else { return "" }
        let quote = bytes[position]
        if quote == UInt8(ascii: "\"") || quote == UInt8(ascii: "'") {
            position += 1
            let start = position
            while position < bytes.count, bytes[position] != quote { position += 1 }
            let value = String(decoding: bytes[start..<position], as: UTF8.self)
            position = min(position + 1, bytes.count)
            return value
        }
        let start = position
        while position < bytes.count, !isSpace(bytes[position]), bytes[position] != UInt8(ascii: ">") { position += 1 }
        return String(decoding: bytes[start..<position], as: UTF8.self)
    }

    /// To after the next `>`, quotes in an attribute included.
    private mutating func skipTag() {
        while position < bytes.count {
            let byte = bytes[position]
            position += 1
            if byte == UInt8(ascii: ">") { return }
            if byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "'") {
                while position < bytes.count, bytes[position] != byte { position += 1 }
                position = min(position + 1, bytes.count)
            }
        }
    }

    // MARK: Search

    private func index(of byte: UInt8, from start: Int) -> Int? {
        guard start < bytes.count else { return nil }
        return bytes[start...].firstIndex(of: byte)
    }

    private func matches(_ text: String, at start: Int) -> Bool {
        let needle = Array(text.utf8)
        guard start >= 0, start + needle.count <= bytes.count else { return false }
        return zip(bytes[start..<start + needle.count], needle).allSatisfy { ClipboardLinkBytes.lower($0) == $1 }
    }

    /// Where `text` (lower case) starts at or after `start`, in either case.
    private func find(_ text: String, from start: Int) -> Int? {
        ClipboardLinkBytes.find(Array(text.utf8), in: bytes, from: start)
    }

    private func isLetter(_ byte: UInt8) -> Bool { (65...90).contains(byte) || (97...122).contains(byte) }
    private func isDigit(_ byte: UInt8) -> Bool { (48...57).contains(byte) }
    private func isSpace(_ byte: UInt8) -> Bool { byte == 0x20 || (0x09...0x0D).contains(byte) }
}

/// Byte searches shared by the head parser and the transport's look for the end of a head.
nonisolated enum ClipboardLinkBytes {
    static func lower(_ byte: UInt8) -> UInt8 {
        (65...90).contains(byte) ? byte + 32 : byte
    }

    /// Where `needle` (lower-case ASCII) starts in `bytes` at or after `start`, whatever the case of the text.
    static func find(_ needle: [UInt8], in bytes: some RandomAccessCollection<UInt8> & Sendable, from start: Int = 0) -> Int? {
        let bytes = Array(bytes)
        guard let first = needle.first, start >= 0, bytes.count >= needle.count, start <= bytes.count - needle.count else { return nil }
        let last = bytes.count - needle.count
        var candidate = start
        while candidate <= last {
            if lower(bytes[candidate]) == first {
                var offset = 1
                while offset < needle.count, lower(bytes[candidate + offset]) == needle[offset] { offset += 1 }
                if offset == needle.count { return candidate }
            }
            candidate += 1
        }
        return nil
    }

    /// Whether the text read so far has reached the end of the head.
    static func hasEndOfHead(_ bytes: some RandomAccessCollection<UInt8> & Sendable) -> Bool {
        ["</head", "<body"].contains { find(Array($0.utf8), in: bytes) != nil }
    }
}
