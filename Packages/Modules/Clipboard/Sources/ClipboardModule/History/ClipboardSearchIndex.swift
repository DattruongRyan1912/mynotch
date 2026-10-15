import Foundation

/// Folded search text per item, kept across keystrokes so typing only folds items that are new or changed.
/// The tab holds one; `ClipboardSearch.filter` builds a throwaway one.
nonisolated final class ClipboardSearchIndex {
    /// Long items are searched by their beginning only, so folding stays fast however much text was copied.
    static let maxSearchableCharacters = 20_000

    private struct Entry {
        /// What the text was built from: the hash fixes the content, the app can change on a repeated copy.
        let contentHash: String
        let sourceAppName: String?
        let sourceBundleID: String?
        let text: String
        /// What an `@app` token is matched against: the app's name and the end of its bundle ID.
        let appNames: [String]
    }

    private var entries: [UUID: Entry] = [:]
    /// Items folded so far, so tests can prove unchanged items are reused.
    private(set) var foldCount = 0

    /// Folds new or changed items and forgets removed ones.
    func update(_ history: ClipboardHistory) {
        for item in history.items {
            if let entry = entries[item.id], entry.contentHash == item.contentHash, entry.sourceAppName == item.sourceAppName,
               entry.sourceBundleID == item.sourceBundleID {
                continue
            }
            entries[item.id] = Entry(
                contentHash: item.contentHash, sourceAppName: item.sourceAppName, sourceBundleID: item.sourceBundleID,
                text: Self.foldedText(of: item), appNames: ClipboardAppName.folded(name: item.sourceAppName, bundleID: item.sourceBundleID)
            )
            foldCount += 1
        }
        if entries.count > history.items.count {
            let ids = Set(history.items.map(\.id))
            entries = entries.filter { ids.contains($0.key) }
        }
    }

    /// Items matching every word of `query.text`, ignoring case and diacritics so "dong ho" finds "Đồng hồ", and every
    /// `@` token in it (see `ClipboardSearchTerms`). Newest first, or in the board's pin order when a board is selected.
    /// `apps` are the apps of the history, which the caller usually has already; nil works them out when the text has an "@".
    func filter(_ history: ClipboardHistory, _ query: ClipboardQuery, apps: [ClipboardLibraryApp]? = nil) -> [ClipboardItem] {
        var items = history.items
        if let boardID = query.boardID {
            let pinnedIDs = history.boards.first { $0.id == boardID }?.itemIDs ?? []
            let itemsByID = Dictionary(history.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            items = pinnedIDs.compactMap { itemsByID[$0] }
        }
        if let kind = query.kind {
            items = items.filter { $0.content.kind == kind }
        }
        let hasAt = query.text.contains("@")
        let terms = ClipboardSearchTerms(parsing: query.text, apps: hasAt ? apps ?? ClipboardLibraryContent.counts(of: history).apps : [])
        let kinds = terms.kinds
        if !kinds.isEmpty {
            items = items.filter { item in kinds.allSatisfy { $0 == item.content.kind } }
        }
        if terms.wantsCode {
            items = items.filter(\.isCode)
        }
        let words = terms.text.split(whereSeparator: \.isWhitespace).map { Self.fold(String($0)) }
        let appPrefixes = terms.appPrefixes
        guard !words.isEmpty || !appPrefixes.isEmpty else { return items }
        update(history)
        return items.filter { item in
            guard let entry = entries[item.id] else { return false }
            return appPrefixes.allSatisfy { prefix in entry.appNames.contains { $0.hasPrefix(prefix) } }
                && words.allSatisfy { entry.text.range(of: $0, options: .literal) != nil }
        }
    }

    /// Those of `items`, which are all in `history`, whose text holds every one of `words` (already folded). The words are taken
    /// as they are: unlike the search field's text, an `@` in them is only a character. For callers whose words did not come
    /// from the field, such as an agent's.
    func filter(_ items: [ClipboardItem], words: [String], in history: ClipboardHistory) -> [ClipboardItem] {
        update(history)
        return items.filter { item in
            guard let entry = entries[item.id] else { return false }
            return words.allSatisfy { entry.text.range(of: $0, options: .literal) != nil }
        }
    }

    /// The source app name plus what the card shows: text, link (and its host when the URL spells it differently),
    /// color hex (and the rgb() or hsl() text it was copied as) or file names. Folders are left out so a common path
    /// such as "/Users" does not match every file.
    private static func foldedText(of item: ClipboardItem) -> String {
        var content: String
        switch item.content {
        case .files(let urls):
            content = urls.map(\.lastPathComponent).joined(separator: "\n")
        case .link(let url):
            content = url.absoluteString
            if let host = url.host(percentEncoded: false), !content.contains(host) { content += "\n" + host }
        case .color(let hex, let original):
            content = original.map { hex + "\n" + $0 } ?? hex
        case .text, .richText, .image:
            content = item.content.plainText ?? ""
        }
        return fold((item.sourceAppName ?? "") + "\n" + content.prefix(maxSearchableCharacters))
    }

    /// Lowercased without diacritics. "đ" has no decomposition, so `.diacriticInsensitive` keeps it and it is mapped by hand.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).replacing("đ", with: "d")
    }
}
