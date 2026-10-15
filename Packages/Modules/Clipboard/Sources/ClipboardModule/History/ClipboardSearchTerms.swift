import Foundation

/// One `@` word of the search text that filters instead of being searched for.
nonisolated struct ClipboardSearchToken: Equatable, Identifiable, Sendable {
    enum Filter: Equatable, Sendable {
        case kind(ClipboardKind)
        /// Texts that are code, whatever the language.
        case code
        /// Items whose app has a name, or a bundle ID ending, that starts with this (folded) text.
        case app(prefix: String)
    }

    /// As typed, e.g. "@Chrome".
    let raw: String
    let filter: Filter
    /// What its chip says: the kind's name, or the app's.
    let title: String
    /// It is the last word and nothing follows it yet, so the user may still be typing it.
    let isBeingTyped: Bool

    var id: String { raw }
}

/// The search text split into the filters in it and the free text that is left. A word starting with "@" is a filter when
/// it names a kind (`@text`, `@link`, `@image`, `@color` or `@màu`, `@file`), says `@code` or `@mã`, or starts the name of an
/// app in the history (`@chrome`); any other word, `@` words included, stays in the free text.
nonisolated struct ClipboardSearchTerms: Equatable, Sendable {
    /// What may follow "@" for each kind, in the order suggestions offer them. A kind is matched whole, an app by prefix.
    static let kindWords: [(word: String, kind: ClipboardKind)] = [
        ("text", .text), ("link", .link), ("image", .image), ("color", .color), ("màu", .color), ("file", .file),
    ]

    /// What may follow "@" for the texts that are code, in the order suggestions offer them. Matched whole, like a kind: an app
    /// called "Code" is reached by the end of its bundle ID (`@vscode`) instead.
    static let codeWords = ["code", "mã"]
    static let codeTitle = "Mã"
    static let codeSystemImage = "curlybraces"

    /// Whether `word` names a kind or code, so an app token must not use it. A kind is found whatever the case and accents,
    /// code only as `code` or `mã` (any case): folding the accent off would make `@ma` the code filter and take it from Mail,
    /// Maps and Mattermost.
    static func isReserved(_ word: String) -> Bool {
        let folded = ClipboardSearchIndex.fold(word)
        return kindWords.contains { ClipboardSearchIndex.fold($0.word) == folded } || isCodeWord(word)
    }

    static func isCodeWord(_ word: String) -> Bool {
        codeWords.contains(word.lowercased())
    }

    /// Every filter once, in the order typed.
    private(set) var tokens: [ClipboardSearchToken] = []
    /// The words that are not filters, for the normal search.
    private(set) var text = ""

    /// Several tokens combine with AND, so an item has to be of every kind named: two different kinds match nothing.
    var kinds: [ClipboardKind] {
        tokens.compactMap { if case .kind(let kind) = $0.filter { kind } else { nil } }
    }

    /// Texts that are code are asked for.
    var wantsCode: Bool {
        tokens.contains { $0.filter == .code }
    }

    var appPrefixes: [String] {
        tokens.compactMap { if case .app(let prefix) = $0.filter { prefix } else { nil } }
    }

    /// The tokens the user is done with; the views show these as removable chips.
    var chips: [ClipboardSearchToken] {
        tokens.filter { !$0.isBeingTyped }
    }

    /// `apps` are the apps of the history: an app token that starts none of them is just text, which is also what keeps
    /// a mention such as "@everyone" searchable.
    init(parsing text: String, apps: [ClipboardLibraryApp]) {
        let words = text.split(whereSeparator: \.isWhitespace)
        let isTypingLastWord = text.last.map { !$0.isWhitespace } ?? false
        var free: [Substring] = []
        for (index, word) in words.enumerated() {
            guard word.first == "@" else {
                free.append(word)
                continue
            }
            let name = ClipboardSearchIndex.fold(String(word.dropFirst()))
            // An "@" alone is a token just begun; it filters nothing and is not searched for.
            if name.isEmpty { continue }
            guard let (filter, title) = Self.resolve(name, raw: String(word.dropFirst()), apps: apps) else {
                free.append(word)
                continue
            }
            let raw = String(word)
            if !tokens.contains(where: { $0.raw == raw }) {
                tokens.append(ClipboardSearchToken(
                    raw: raw, filter: filter, title: title, isBeingTyped: isTypingLastWord && index == words.count - 1
                ))
            }
        }
        self.text = free.joined(separator: " ")
    }

    /// `text` without the words that are `token`. A search the user had finished typing stays finished, so the tokens
    /// before it do not turn back into ones being typed.
    static func removing(_ token: ClipboardSearchToken, from text: String) -> String {
        let rest = text.split(whereSeparator: \.isWhitespace).filter { $0 != token.raw }.joined(separator: " ")
        return rest.isEmpty || text.last?.isWhitespace != true ? rest : rest + " "
    }

    /// A kind by its whole name, so "@file" is the kind even if an app is called "Files"; otherwise the first app that matches.
    private static func resolve(_ name: String, raw: String, apps: [ClipboardLibraryApp]) -> (ClipboardSearchToken.Filter, title: String)? {
        if let entry = kindWords.first(where: { ClipboardSearchIndex.fold($0.word) == name }) {
            return (.kind(entry.kind), entry.kind.title)
        }
        if isCodeWord(raw) { return (.code, codeTitle) }
        guard let app = apps.first(where: { $0.matches(prefix: name) }) else { return nil }
        return (.app(prefix: name), app.name)
    }
}

nonisolated extension ClipboardLibraryApp {
    /// Whether `prefix` (already folded) starts its name or the last component of its bundle ID, "Chrome" for
    /// com.google.Chrome, which is how an app called "Google Chrome" is found by `@chrome`.
    func matches(prefix: String) -> Bool {
        ClipboardAppName.folded(name: name, bundleID: bundleID).contains { $0.hasPrefix(prefix) }
    }
}

/// The two names an `@app` token is compared with.
nonisolated enum ClipboardAppName {
    /// "Chrome" for "com.google.Chrome"; nil without a bundle ID or when it ends in a dot.
    static func component(of bundleID: String?) -> String? {
        guard let last = bundleID?.split(separator: ".", omittingEmptySubsequences: false).last, !last.isEmpty else { return nil }
        return String(last)
    }

    /// The name and the last component of the bundle ID, folded.
    static func folded(name: String?, bundleID: String?) -> [String] {
        [name, component(of: bundleID)].compactMap { $0 }.map(ClipboardSearchIndex.fold).filter { !$0.isEmpty }
    }
}
