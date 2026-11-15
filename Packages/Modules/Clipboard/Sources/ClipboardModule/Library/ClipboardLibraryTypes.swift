import Foundation

/// What the library's sidebar has selected; it decides which items the content shows.
nonisolated enum ClipboardLibrarySelection: Hashable, Sendable {
    case all
    case board(UUID)
    /// Text and rich text are one kind, as in the notch tab's chips.
    case kind(ClipboardKind)
    /// A `ClipboardLibraryApp.id`.
    case app(String)
}

nonisolated enum ClipboardLibrarySort: String, Codable, Sendable, CaseIterable {
    case newest, oldest, byApp, byKind

    var title: String {
        switch self {
        case .newest: "Mới nhất"
        case .oldest: "Cũ nhất"
        case .byApp: "Theo ứng dụng"
        case .byKind: "Theo loại"
        }
    }
}

nonisolated enum ClipboardLibraryLayout: String, Codable, Sendable, CaseIterable {
    case grid, list
}

/// How big the grid's cards are: three steps, so the slider has no in-between sizes to render.
nonisolated enum ClipboardLibraryCardSize: Int, Codable, Sendable, CaseIterable {
    case small, medium, large

    /// Narrowest a card gets; the grid widens cards evenly to fill the row.
    var minWidth: Double {
        switch self {
        case .small: 132
        case .medium: 172
        case .large: 232
        }
    }

    var height: Double {
        switch self {
        case .small: 108
        case .medium: 136
        case .large: 184
        }
    }

    /// Lines of a text card's preview.
    var textLines: Int {
        switch self {
        case .small: 3
        case .medium: 5
        case .large: 8
        }
    }

    /// A link card's picture and title, which share what the card has beside the footer.
    var linkImageHeight: CGFloat {
        switch self {
        case .small: 22
        case .medium: 36
        case .large: 60
        }
    }

    var linkTitleLines: Int {
        switch self {
        case .small: 1
        case .medium: 2
        case .large: 3
        }
    }

    /// The slider's position, 0 to 2.
    var sliderValue: Double { Double(rawValue) }

    /// Rounds and clamps, so any slider value picks a size.
    init(sliderValue: Double) {
        guard sliderValue.isFinite else {
            self = .medium
            return
        }
        self = Self(rawValue: Int(min(max(sliderValue.rounded(), 0), 2))) ?? .medium
    }

    /// As many cards as fit `width` at their minimum, at least one.
    func columnCount(forWidth width: Double, spacing: Double) -> Int {
        max(1, Int(((width + spacing) / (minWidth + spacing)).rounded(.down)))
    }
}

/// What the library remembers about how it looks.
nonisolated struct ClipboardLibraryPreferences: Equatable, Sendable {
    var layout: ClipboardLibraryLayout = .grid
    var sort: ClipboardLibrarySort = .newest
    var cardSize: ClipboardLibraryCardSize = .medium
    /// Whether the inspector pane beside the cards is shown (⌘I).
    var inspectorVisible = false
}

/// A source app of the history, as one sidebar row.
nonisolated struct ClipboardLibraryApp: Identifiable, Equatable, Sendable {
    /// The bundle ID; an app without one is keyed by its name.
    let id: String
    let bundleID: String?
    /// From the newest item, since an app can be renamed.
    let name: String
    let count: Int
}

/// The sidebar's numbers. They count the whole history: neither search nor the kind filter changes them.
nonisolated struct ClipboardLibraryCounts: Equatable, Sendable {
    var all = 0
    var boards: [UUID: Int] = [:]
    var kinds: [ClipboardKind: Int] = [:]
    /// By count, then name; items copied by no known app are in no row.
    var apps: [ClipboardLibraryApp] = []
}

nonisolated enum ClipboardLibraryDirection: Sendable {
    case left, right, up, down
}

/// A line of text over the library's content, e.g. "Đã chép".
nonisolated struct ClipboardLibraryNotice: Equatable, Sendable {
    let id: Int
    let text: String
    let systemImage: String
}

extension ClipboardKind {
    /// The sidebar's order of kinds; `CaseIterable` keeps the notch chips' order.
    nonisolated static let libraryOrder: [ClipboardKind] = [.text, .link, .image, .color, .file]
}
