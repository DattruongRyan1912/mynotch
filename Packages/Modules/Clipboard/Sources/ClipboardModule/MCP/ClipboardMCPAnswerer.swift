import ClipboardMCPKit
import Foundation

/// What the app says to a request, and how many items it gave, which the access log shows.
nonisolated struct ClipboardMCPAnswer: Equatable, Sendable {
    var reply: ClipboardMCPWireReply
    var resultCount: Int
}

/// Turns a request into an answer from the history: which items an agent may see, and what it is told of each. A rule that
/// keeps an item from the agent is applied before anything else, so no filter or id can bring it back.
nonisolated enum ClipboardMCPAnswerer {
    /// The same for an id that does not exist and for one an agent may not see, so the answer does not tell a secret from nothing.
    static let notFoundMessage = "No clipboard item has that id. Use an id that search_clipboard returned."

    /// - Parameter lockedBoardIDs: the boards the user keeps locked. An item pinned to any of them is hidden, even when an
    ///   open board holds it too.
    static func answer(
        _ request: ClipboardMCPRequest, history: ClipboardHistory, index: ClipboardSearchIndex, lockedBoardIDs: Set<UUID>, now: Date
    ) -> ClipboardMCPAnswer {
        let visible = visibleItems(of: history, lockedBoardIDs: lockedBoardIDs)
        switch request {
        case .search(let search):
            return answer(search, among: visible, history: history, index: index, now: now)
        case .item(let id):
            guard let item = visible.first(where: { $0.id == id }) else {
                return ClipboardMCPAnswer(reply: .failure(.notFound, notFoundMessage), resultCount: 0)
            }
            return ClipboardMCPAnswer(reply: .success(json(of: item).json), resultCount: 1)
        }
    }

    /// Everything but the items an app marked as secret and the ones pinned to a locked board. An item whose flag is not known
    /// (copied before MyNotch tracked it) is not held back: only what is flagged is.
    private static func visibleItems(of history: ClipboardHistory, lockedBoardIDs: Set<UUID>) -> [ClipboardItem] {
        let hidden = Set(history.boards.filter { lockedBoardIDs.contains($0.id) }.flatMap(\.itemIDs))
        return history.items.filter { !$0.isSensitive && !hidden.contains($0.id) }
    }

    private static func answer(
        _ search: ClipboardMCPSearch, among visible: [ClipboardItem], history: ClipboardHistory, index: ClipboardSearchIndex, now: Date
    ) -> ClipboardMCPAnswer {
        var items = visible
        if let kind = search.kind { items = items.filter { Self.kind(of: $0) == kind } }
        if let app = search.app {
            let needle = ClipboardSearchIndex.fold(app)
            items = items.filter { item in
                [item.sourceAppName, item.sourceBundleID].contains { $0.map { ClipboardSearchIndex.fold($0).contains(needle) } ?? false }
            }
        }
        if let days = search.sinceDays {
            let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
            items = items.filter { $0.copiedAt >= cutoff }
        }
        let words = search.query.split(whereSeparator: \.isWhitespace).map { ClipboardSearchIndex.fold(String($0)) }
        if !words.isEmpty { items = index.filter(items, words: words, in: history) }

        var shown: [JSON] = []
        var textBytes = 0
        for item in items.prefix(search.limit) {
            let (json, bytes) = json(of: item)
            guard textBytes + bytes <= ClipboardMCPLimits.maxTotalTextBytes else { break }
            textBytes += bytes
            shown.append(json)
        }
        var result: [String: JSON] = ["count": .int(shown.count), "matches": .int(items.count), "items": .array(shown)]
        let omitted = min(items.count, search.limit) - shown.count
        if omitted > 0 { result["omitted"] = .int(omitted) }
        return ClipboardMCPAnswer(reply: .success(.object(result)), resultCount: shown.count)
    }

    /// What an agent can ask for: unlike the notch's kinds, a text that is code is `code` and not also `text`.
    private static func kind(of item: ClipboardItem) -> ClipboardMCPKind {
        switch item.content {
        case .image: .image
        case .link: .link
        case .color: .color
        case .files: .file
        case .text, .richText: item.isCode ? .code : .text
        }
    }

    /// The item as an agent reads it, and the bytes of text in it.
    private static func json(of item: ClipboardItem) -> (json: JSON, textBytes: Int) {
        let kind = kind(of: item)
        var object: [String: JSON] = [
            "id": .string(item.id.uuidString), "kind": .string(kind.rawValue),
            "copiedAt": .string(item.copiedAt.formatted(Date.ISO8601FormatStyle())),
        ]
        if let app = item.sourceAppName ?? item.sourceBundleID { object["app"] = .string(app) }
        if let language = item.codeLanguage, language != .generic { object["language"] = .string(language.rawValue) }
        var textBytes = 0
        if case .image(let image) = item.content {
            // Metadata only: the picture is never sent.
            object["image"] = .object(["width": .int(image.pixelWidth), "height": .int(image.pixelHeight), "bytes": .int(image.byteCount)])
        } else if let text = item.content.plainText {
            let (cut, truncated) = cut(text, maxBytes: ClipboardMCPLimits.maxTextBytes)
            object["text"] = .string(cut)
            object["bytes"] = .int(text.utf8.count)
            object["truncated"] = .bool(truncated)
            textBytes = cut.utf8.count
        }
        return (.object(object), textBytes)
    }

    /// The start of `text` that fits in `maxBytes` of UTF-8, ending between two characters.
    static func cut(_ text: String, maxBytes: Int) -> (text: String, truncated: Bool) {
        guard text.utf8.count > maxBytes else { return (text, false) }
        var used = 0
        var end = text.startIndex
        for index in text.indices {
            let next = text.index(after: index)
            let size = text.utf8.distance(from: index, to: next)
            if used + size > maxBytes { break }
            used += size
            end = next
        }
        return (String(text[..<end]), true)
    }
}
