import Foundation

/// How big an item is, in the words of its kind.
nonisolated enum ClipboardInspectorSize: Equatable, Sendable {
    case text(ClipboardTextStats)
    /// A text too long to count while drawing: the inspector counts it off the main actor and shows the numbers when they are ready.
    case largeText(byteCount: Int)
    /// A link or a colour: how long it is written.
    case characters(Int)
    case image(pixelWidth: Int, pixelHeight: Int, byteCount: Int)
    case files(count: Int)
}

/// What an item is in the language sense: the programming language of code, or the language of prose.
nonisolated enum ClipboardInspectorLanguage: Equatable, Sendable {
    case code(CodeLanguage)
    /// The language's name, in Vietnamese.
    case prose(String)
}

/// The facts the inspector lists about one item.
struct ClipboardInspectorInfo: Equatable, Sendable {
    /// Texts of up to this many bytes are counted while the inspector is made; longer ones off the main actor.
    static let inlineLimit = 50_000

    let id: UUID
    /// "Văn bản", "Mã Swift", "Ảnh"...
    let kindTitle: String
    let systemImage: String
    let sourceAppName: String?
    let sourceBundleID: String?
    let copiedAt: Date
    let timesCopied: Int
    let size: ClipboardInspectorSize
    let language: ClipboardInspectorLanguage?
    /// The boards it is pinned to, in the order of the row.
    let boards: [String]
    let isEdited: Bool
    /// "Sửa…" is available: a text, a code or a link that is not in a closed board.
    let canEdit: Bool

    init(_ item: ClipboardItem, in history: ClipboardHistory) {
        id = item.id
        kindTitle = item.isCode ? ClipboardCardText.kindTitle(of: item) : item.content.kind.title
        systemImage = item.isCode ? ClipboardSearchTerms.codeSystemImage : item.content.kind.systemImage
        sourceAppName = item.sourceAppName
        sourceBundleID = item.sourceBundleID
        copiedAt = item.copiedAt
        timesCopied = item.timesCopied
        isEdited = item.isEdited
        canEdit = history.canEdit(item.id)
        boards = history.boards(containing: item.id).map(\.name)
        switch item.content {
        case .text(let text), .richText(let text, _):
            size = text.utf8.count > Self.inlineLimit ? .largeText(byteCount: text.utf8.count) : .text(ClipboardTextStats(text))
            language = Self.language(of: item, text: text)
        case .image(let image):
            size = .image(pixelWidth: image.pixelWidth, pixelHeight: image.pixelHeight, byteCount: image.byteCount)
            language = nil
        case .files(let urls):
            size = .files(count: urls.count)
            language = nil
        case .link, .color:
            size = .characters(item.content.plainText?.count ?? 0)
            language = nil
        }
    }

    private static func language(of item: ClipboardItem, text: String) -> ClipboardInspectorLanguage? {
        if let code = item.codeLanguage { return .code(code) }
        return ClipboardTextLanguage.code(of: text).map { .prose(ClipboardTextLanguage.name(forCode: $0)) }
    }
}

/// What the inspector pane shows.
enum ClipboardInspectorContent: Equatable, Sendable {
    /// No card is selected.
    case nothing
    /// The board on show, or the item's board, is locked: only that is said, nothing of what it holds.
    case locked
    case item(ClipboardInspectorInfo)

    /// `item` is the card the user is on (nil for none). `boardIsLocked` is the library showing a board that is closed, where there are
    /// no cards at all.
    static func make(for item: ClipboardItem?, in history: ClipboardHistory, boardIsLocked: Bool) -> ClipboardInspectorContent {
        if boardIsLocked { return .locked }
        guard let item else { return .nothing }
        guard history.canPreview(item.id) else { return .locked }
        return .item(ClipboardInspectorInfo(item, in: history))
    }
}

/// The inspector's words.
nonisolated enum ClipboardInspectorFormat {
    static let vietnamese = Locale(identifier: "vi_VN")

    /// "15 thg 1, 2027 08:00".
    static func date(_ date: Date, locale: Locale = vietnamese, timeZone: TimeZone = .current) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale, timeZone: timeZone))
    }

    /// "3 lần".
    static func times(_ count: Int) -> String {
        "\(count) lần"
    }

    /// "1.234 ký tự · 210 từ · 18 dòng", "1920 × 1080 px · 2,1 MB", "3 file"; nil for a text still being counted.
    static func size(_ size: ClipboardInspectorSize, locale: Locale = vietnamese) -> String? {
        func number(_ value: Int) -> String { value.formatted(.number.locale(locale)) }
        switch size {
        case .text(let stats):
            return "\(number(stats.characters)) ký tự · \(number(stats.words)) từ · \(number(stats.lines)) dòng"
        case .largeText:
            return nil
        case .characters(let count):
            return "\(number(count)) ký tự"
        case .image(let width, let height, let bytes):
            return "\(width) × \(height) px · \(ClipboardPreviewFormat.size(bytes))"
        case .files(let count):
            return "\(count) file"
        }
    }
}
