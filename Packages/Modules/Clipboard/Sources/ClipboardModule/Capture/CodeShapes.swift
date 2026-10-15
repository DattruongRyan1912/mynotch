import Foundation

/// SQL, which only counts as SQL when each statement has the shape of one: `select` with columns, `from` and a table,
/// `insert into` a table, `update` a table `set` a column, and so on, backed by a second sign (a keyword in capitals, a
/// closing semicolon or three different keywords). "select all the files from the folder" has the first two words of a query
/// and no more of it.
nonisolated enum SQLShape {
    private static let keywords: Set<String> = [
        "select", "from", "where", "insert", "into", "values", "update", "set", "delete", "create", "table", "alter", "drop",
        "join", "group", "order", "limit", "having", "primary", "union", "inner", "outer", "view", "database", "null", "distinct",
    ]
    private static let clauses: Set<String> = [
        "where", "join", "inner", "left", "right", "outer", "full", "cross", "group", "order", "having", "limit", "offset", "union", "on",
        "using", "as",
    ]
    /// Words that are not names of tables or columns, so a sentence is not a statement.
    private static let fillerWords: Set<String> = [
        "is", "the", "a", "an", "to", "of", "for", "with", "that", "this", "it", "are", "was", "be", "my", "me", "your", "you", "we",
        "they", "at", "but", "so", "do", "please", "here", "there", "what", "how", "then", "all",
    ]

    static func matches(_ sample: DetectionSample) -> Bool {
        let statements = sample.lines.filter { !$0.text.hasPrefix("--") && !$0.text.hasPrefix("/*") }.map(\.text)
        // Most texts are rejected by their first word, before anything else is split.
        guard let start = statements.first?.prefix(while: { $0.isLetter }).lowercased(), starters.contains(start) else { return false }
        let code = statements.joined(separator: " ")
        guard !CodeLineText.hasProseLetters(code) else { return false }
        let words = code.split { !($0.isLetter || $0 == "_") }
        let lowercased = Set(words.map { $0.lowercased() })
        let shouting = words.contains { $0.count >= 3 && keywords.contains($0.lowercased()) && $0 == $0.uppercased() }
        guard shouting || code.hasSuffix(";") || lowercased.intersection(keywords).count >= 3 else { return false }
        let parts = CodeLineText.strippingStrings(code).split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return !parts.isEmpty && parts.allSatisfy(isStatement)
    }

    private static let starters: Set<String> = ["select", "insert", "update", "delete", "create", "alter", "drop", "truncate", "with"]

    /// One statement, lower-cased and split into words and punctuation.
    private static func isStatement(_ statement: String) -> Bool {
        let tokens = statement.lowercased().split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init)
        guard let first = tokens.first else { return false }
        switch first {
        case "select": return isSelect(tokens)
        case "insert": return tokens.count >= 4 && tokens[1] == "into" && isName(tokens[2])
        case "update": return tokens.count >= 4 && isName(tokens[1]) && tokens[2] == "set"
        case "delete": return tokens.count >= 3 && tokens[1] == "from" && isName(tokens[2]) && followsTable(tokens.dropFirst(3))
        case "create": return tokens.count >= 3 && declaresObject(tokens.dropFirst())
        case "alter": return tokens.count >= 4 && tokens[1] == "table" && isName(tokens[2])
        case "drop": return tokens.count >= 3 && declaresObject(tokens.dropFirst())
        case "truncate": return tokens.count >= 3 && tokens[1] == "table" && isName(tokens[2])
        case "with": return tokens.count >= 5 && isName(tokens[1]) && tokens[2] == "as" && statement.lowercased().containsBytes("select")
        default: return false
        }
    }

    /// `select <columns> from <table> …`: something between the two words that is a list of columns, and a table.
    private static func isSelect(_ tokens: [String]) -> Bool {
        guard let from = tokens.firstIndex(of: "from"), from >= 2, from + 1 < tokens.count else { return false }
        var columns = tokens[1..<from]
        for modifier in ["distinct", "all"] where columns.first == modifier { columns = columns.dropFirst() }
        guard !columns.isEmpty else { return false }
        // "a, b" and "count(*) as n" are column lists; "the files" is two plain words.
        let joined = columns.joined(separator: " ")
        let hasShape = joined.contains(",") || joined.contains("*") || joined.contains("(") || joined.contains(".") || columns.count == 1
            || columns.contains("as")
        guard hasShape, !columns.contains(where: { fillerWords.contains($0.trimmingCharacters(in: CharacterSet(charactersIn: ",()"))) }),
              isName(tokens[from + 1]) || tokens[from + 1].hasPrefix("(") else { return false }
        return followsTable(tokens.dropFirst(from + 2))
    }

    /// After a table: nothing, a clause keyword, or an alias and then one of those.
    private static func followsTable(_ rest: ArraySlice<String>) -> Bool {
        guard let first = rest.first else { return true }
        if clauses.contains(first) { return true }
        return rest.count == 1 || clauses.contains(rest[rest.startIndex + 1])
    }

    private static func declaresObject(_ tokens: ArraySlice<String>) -> Bool {
        var tokens = tokens
        while let first = tokens.first, ["temp", "temporary", "unique", "or", "replace"].contains(first) { tokens = tokens.dropFirst() }
        guard let kind = tokens.first, ["table", "index", "view", "database", "schema", "trigger"].contains(kind) else { return false }
        tokens = tokens.dropFirst()
        if tokens.starts(with: ["if", "not", "exists"]) { tokens = tokens.dropFirst(3) } else if tokens.starts(with: ["if", "exists"]) { tokens = tokens.dropFirst(2) }
        return tokens.first.map(isName) ?? false
    }

    /// A table or column name: letters, digits, `_` and `.`, or quoted.
    private static func isName(_ token: String) -> Bool {
        let name = token.trimmingCharacters(in: CharacterSet(charactersIn: "(,"))
        guard let first = name.first, !fillerWords.contains(name) else { return false }
        if "\"`[".contains(first) { return true }
        return (first.isLetter || first == "_") && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == ".") }
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
