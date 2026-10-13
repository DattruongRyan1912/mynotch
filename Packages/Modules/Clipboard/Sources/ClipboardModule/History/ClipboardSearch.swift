import Foundation

/// What the tab's search field, kind chips and board pills select.
nonisolated struct ClipboardQuery: Equatable {
    var text = ""
    var kind: ClipboardKind?
    var boardID: UUID?
}

nonisolated enum ClipboardSearch {
    /// Items matching every word of `query.text`, ignoring case and diacritics so "dong ho" finds "Đồng hồ".
    /// Newest first, or in the board's pin order when a board is selected.
    static func filter(_ history: ClipboardHistory, _ query: ClipboardQuery) -> [ClipboardItem] {
        var items = history.items
        if let boardID = query.boardID {
            let pinnedIDs = history.boards.first { $0.id == boardID }?.itemIDs ?? []
            let itemsByID = Dictionary(history.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            items = pinnedIDs.compactMap { itemsByID[$0] }
        }
        if let kind = query.kind {
            items = items.filter { $0.content.kind == kind }
        }
        let words = query.text.split(whereSeparator: \.isWhitespace).map { folded(String($0)) }
        guard !words.isEmpty else { return items }
        return items.filter { item in
            let searchable = folded(searchableText(of: item))
            return words.allSatisfy(searchable.contains)
        }
    }

    /// Everything a user may type to find an item, including what the card shows besides the content.
    private static func searchableText(of item: ClipboardItem) -> String {
        var parts = [item.content.plainText, item.sourceAppName]
        switch item.content {
        case .link(let url): parts.append(url.host())
        case .files(let urls): parts += urls.map(\.lastPathComponent)
        case .text, .richText, .color, .image: break
        }
        return parts.compactMap(\.self).joined(separator: "\n")
    }

    /// Lowercased without diacritics. "đ" has no decomposition, so `.diacriticInsensitive` keeps it and it is mapped by hand.
    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).replacing("đ", with: "d")
    }
}
