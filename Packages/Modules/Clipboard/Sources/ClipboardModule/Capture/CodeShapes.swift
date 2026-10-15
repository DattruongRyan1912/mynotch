import Foundation

/// A statement that starts like SQL and holds what that statement needs ("select" has its "from"), backed by a second
/// sign: a keyword written in capitals, a closing semicolon or three different keywords. "select all the files from the
/// folder" has the first two words of a query and none of the signs.
nonisolated enum SQLShape {
    private static let required: [String: Set<String>] = [
        "select": ["from"], "insert": ["into"], "delete": ["from"], "update": ["set"], "with": ["select"],
        "create": ["table", "index", "view", "database", "schema", "unique", "trigger"],
        "alter": ["table"], "drop": ["table", "index", "view", "database", "schema"], "truncate": ["table"],
    ]
    private static let keywords: Set<String> = [
        "select", "from", "where", "insert", "into", "values", "update", "set", "delete", "create", "table", "alter", "drop",
        "join", "group", "order", "limit", "having", "primary", "union", "inner", "outer", "view", "database", "null", "distinct",
    ]

    static func matches(_ sample: DetectionSample) -> Bool {
        let statements = sample.lines.filter { !$0.text.hasPrefix("--") && !$0.text.hasPrefix("/*") }
        // Most texts are rejected by their first word, before anything else is split.
        guard let start = statements.first?.text.prefix(while: { $0.isLetter }).lowercased(), required[start] != nil else { return false }
        let code = statements.map(\.text).joined(separator: "\n")
        let words = code.split { !($0.isLetter || $0 == "_") }
        guard let first = words.first?.lowercased(), let needs = required[first] else { return false }
        let lowercased = Set(words.map { $0.lowercased() })
        guard !needs.isDisjoint(with: lowercased) else { return false }
        let found = lowercased.intersection(keywords)
        let shouting = words.contains { $0.count >= 3 && keywords.contains($0.lowercased()) && $0 == $0.uppercased() }
        return shouting || code.hasSuffix(";") || found.count >= 3
    }
}

/// A stylesheet: rules whose selector looks like one and holds `property: value` declarations, or a run of such
/// declarations alone (an inline style). TypeScript interfaces and Go structs have `name: type;` lines too, but not a
/// selector in front of them.
nonisolated enum CSSShape {
    private static let tags: Set<String> = [
        "html", "body", "a", "p", "div", "span", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li", "img", "button", "input",
        "table", "tr", "td", "th", "header", "footer", "nav", "section", "main", "form", "label", "pre", "code", "svg", "textarea",
    ]

    static func matches(_ sample: DetectionSample) -> Bool {
        let text = sample.text
        if let brace = text.utf8.firstIndex(of: UInt8(ascii: "{")) {
            guard text.containsBytes("}"), isSelector(text[..<brace]) else { return false }
            return text.split { $0 == "{" || $0 == "}" || $0 == ";" || $0.isNewline }.contains { isDeclaration($0) }
        }
        guard text.containsBytes(";") else { return false }
        let segments = text.split { $0 == ";" || $0.isNewline }.filter { !$0.allSatisfy(\.isWhitespace) }
        return segments.count >= 2 && segments.allSatisfy { isDeclaration($0) }
    }

    /// `margin-top: 4px`: a lowercase property, a colon and a value.
    private static func isDeclaration(_ segment: Substring) -> Bool {
        let text = segment.drop { $0 == " " || $0 == "\t" }
        let property = text.prefix { $0.isASCII && ($0.isLowercase || $0 == "-") }
        guard !property.isEmpty else { return false }
        let rest = text.dropFirst(property.count).drop { $0 == " " }
        return rest.first == ":" && rest.dropFirst().contains { !$0.isWhitespace }
    }

    /// The last selector before the first brace.
    private static func isSelector(_ before: Substring) -> Bool {
        let selector = (before.split(whereSeparator: \.isNewline).last ?? before).drop { $0 == " " || $0 == "\t" }
        guard let first = selector.first else { return false }
        if ".#@:*[".contains(first) { return first == "@" || !selector.contains("(") }
        let tag = selector.prefix { $0.isLetter || $0.isNumber }
        return tags.contains(String(tag)) && !selector.contains("(")
    }
}
