import Foundation

/// One row of the list under the search field while an `@` word is being typed.
nonisolated struct ClipboardSearchSuggestion: Identifiable, Equatable, Sendable {
    enum Subject: Equatable, Sendable {
        case kind(ClipboardKind)
        case app(bundleID: String?)
    }

    /// What completing the row types, e.g. "@link".
    let token: String
    /// What the row says: the name of the kind or of the app.
    let title: String
    let subject: Subject

    var id: String { token }
}

nonisolated enum ClipboardSearchSuggestions {
    /// A longer list of apps would not fit under the field, and what is typed narrows it anyway.
    static let maxApps = 8

    /// The rows for the word being typed, the last one, when it starts with "@": kinds first, then the apps of the history
    /// in the order given (the library's: most items first), all narrowed to what the word starts. A kind or an app the text
    /// already has is not offered again, since two of either match nothing.
    static func suggestions(for text: String, apps: [ClipboardLibraryApp]) -> [ClipboardSearchSuggestion] {
        guard text.last?.isWhitespace == false, let last = text.split(whereSeparator: \.isWhitespace).last, last.first == "@" else {
            return []
        }
        let typed = ClipboardSearchIndex.fold(String(last.dropFirst()))
        let chosen = ClipboardSearchTerms(parsing: String(text.dropLast(last.count)), apps: apps)
        var rows: [ClipboardSearchSuggestion] = []
        if chosen.kinds.isEmpty {
            // One row per kind, under the first of its words that fits: "@color", or "@màu" for what only it matches.
            rows += ClipboardKind.libraryOrder.compactMap { kind in
                ClipboardSearchTerms.kindWords
                    .first { $0.kind == kind && ClipboardSearchIndex.fold($0.word).hasPrefix(typed) }
                    .map { ClipboardSearchSuggestion(token: "@" + $0.word, title: kind.title, subject: .kind(kind)) }
            }
        }
        if chosen.appPrefixes.isEmpty { rows += appRows(matching: typed, in: apps) }
        return rows
    }

    /// `text` with its last word, the one being typed, replaced by the row's token and a space.
    static func completing(_ text: String, with suggestion: ClipboardSearchSuggestion) -> String {
        let start = text.lastIndex(where: \.isWhitespace).map(text.index(after:)) ?? text.startIndex
        return String(text[..<start]) + suggestion.token + " "
    }

    private static func appRows(matching typed: String, in apps: [ClipboardLibraryApp]) -> [ClipboardSearchSuggestion] {
        var seen = Set<String>()
        var rows: [ClipboardSearchSuggestion] = []
        for app in apps where app.matches(prefix: typed) {
            let word = word(for: app, startingWith: typed)
            // Two apps whose bundle IDs end alike would offer the same token.
            guard !word.isEmpty, seen.insert(ClipboardSearchIndex.fold(word)).inserted else { continue }
            rows.append(ClipboardSearchSuggestion(token: "@" + word, title: app.name, subject: .app(bundleID: app.bundleID)))
            if rows.count == maxApps { break }
        }
        return rows
    }

    /// The last component of the bundle ID when it starts with what was typed ("Chrome", short for "Google Chrome"),
    /// otherwise the first word of the name.
    private static func word(for app: ClipboardLibraryApp, startingWith typed: String) -> String {
        if let component = ClipboardAppName.component(of: app.bundleID), ClipboardSearchIndex.fold(component).hasPrefix(typed) {
            return component
        }
        return app.name.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
    }
}

/// The suggestions under a search field, which row is highlighted, and what the keys do to them. A value, so the tab's
/// state and the library's model each keep one and tests need no window.
nonisolated struct ClipboardSuggestionList: Equatable, Sendable {
    private(set) var items: [ClipboardSearchSuggestion] = []
    private(set) var highlighted = 0
    private var text = ""
    /// The text Esc closed the list on; it stays closed until the text changes.
    private var dismissedText: String?

    var isOpen: Bool { !items.isEmpty }

    /// Rebuilds the rows for `text`. The highlight stays on its row while the rows are the same and starts over when
    /// they change, so a history change does not move it.
    mutating func update(text: String, apps: [ClipboardLibraryApp]) {
        self.text = text
        if dismissedText != text { dismissedText = nil }
        let rows = dismissedText == nil ? ClipboardSearchSuggestions.suggestions(for: text, apps: apps) : []
        guard rows != items else { return }
        items = rows
        highlighted = 0
    }

    /// Up (-1) or down (1), wrapping around.
    mutating func move(_ offset: Int) {
        guard !items.isEmpty else { return }
        highlighted = (highlighted + offset + items.count) % items.count
    }

    mutating func dismiss() {
        dismissedText = text
        items = []
        highlighted = 0
    }

    /// Completes `text` with a row, as a click on it does.
    func accept(_ index: Int, into text: inout String) {
        guard items.indices.contains(index) else { return }
        text = ClipboardSearchSuggestions.completing(text, with: items[index])
    }

    /// What a key does while the list is open: up and down move, Tab and Return complete the highlighted row, Esc closes
    /// the list. False when the list is closed, so the key keeps its usual meaning.
    mutating func handle(_ command: ClipboardKeyCommand, text: inout String) -> Bool {
        guard isOpen else { return false }
        switch command {
        case .next: move(1)
        case .previous: move(-1)
        case .activate, .complete: accept(highlighted, into: &text)
        case .clearSearch, .close: dismiss()
        }
        return true
    }
}
