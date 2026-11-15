import Foundation

/// What the library shows for a selection, search, kind filter and sort, and the sidebar's counts. Pure, so the
/// rules are testable without a window; the model calls it again whenever one of its inputs changes.
nonisolated enum ClipboardLibraryContent {
    /// The sidebar row an item belongs to: its bundle ID, or its name when it has no bundle ID; nil without a source app.
    static func appKey(of item: ClipboardItem) -> String? {
        if let bundleID = item.sourceBundleID { return bundleID }
        return item.sourceAppName.map { "name:" + $0 }
    }

    /// The items to show. `index` is kept by the caller across calls, so typing folds only new items.
    static func items(
        in history: ClipboardHistory, selection: ClipboardLibrarySelection, kindFilter: ClipboardKind?,
        searchText: String, sort: ClipboardLibrarySort, apps: [ClipboardLibraryApp], index: ClipboardSearchIndex
    ) -> [ClipboardItem] {
        var query = ClipboardQuery(text: searchText)
        if case .kind(let kind) = selection { query.kind = kind }
        var items = index.filter(history, query, apps: apps)
        switch selection {
        case .all, .kind:
            break
        case .board(let id):
            let pinned = Set(history.boards.first { $0.id == id }?.itemIDs ?? [])
            items = items.filter { pinned.contains($0.id) }
        case .app(let key):
            items = items.filter { appKey(of: $0) == key }
        }
        if let kindFilter { items = items.filter { $0.content.kind == kindFilter } }
        return sorted(items, by: sort, apps: apps)
    }

    static func counts(of history: ClipboardHistory) -> ClipboardLibraryCounts {
        var counts = ClipboardLibraryCounts(all: history.items.count)
        counts.boards = Dictionary(history.boards.map { ($0.id, $0.shownItemCount) }, uniquingKeysWith: { first, _ in first })
        var groups: [String: (bundleID: String?, name: String, count: Int)] = [:]
        for item in history.items {
            counts.kinds[item.content.kind, default: 0] += 1
            guard let key = appKey(of: item) else { continue }
            // Newest first, so the first name seen is the latest one.
            groups[key, default: (item.sourceBundleID, item.sourceAppName ?? key, 0)].count += 1
        }
        counts.apps = groups
            .map { ClipboardLibraryApp(id: $0.key, bundleID: $0.value.bundleID, name: $0.value.name, count: $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return counts
    }

    /// `items` arrive newest first. Every order falls back to that one, which also keeps equal keys steady.
    private static func sorted(_ items: [ClipboardItem], by sort: ClipboardLibrarySort, apps: [ClipboardLibraryApp]) -> [ClipboardItem] {
        switch sort {
        case .newest:
            return items
        case .oldest:
            return items.reversed()
        case .byApp:
            // Items without an app go last; the others by their app's name, ignoring case and diacritics. The apps
            // are ranked once, so sorting thousands of items compares numbers, not names.
            let ranked = apps.sorted {
                let order = $0.name.localizedStandardCompare($1.name)
                return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
            }
            let rank = Dictionary(uniqueKeysWithValues: ranked.enumerated().map { ($1.id, $0) })
            return ordered(items) { appKey(of: $0).flatMap { rank[$0] } ?? rank.count }
        case .byKind:
            let rank = Dictionary(uniqueKeysWithValues: ClipboardKind.libraryOrder.enumerated().map { ($1, $0) })
            return ordered(items) { rank[$0.content.kind] ?? rank.count }
        }
    }

    /// Stable: items with equal keys stay in their order.
    private static func ordered(_ items: [ClipboardItem], by key: (ClipboardItem) -> Int) -> [ClipboardItem] {
        let keys = items.map(key)
        return items.indices.sorted { keys[$0] != keys[$1] ? keys[$0] < keys[$1] : $0 < $1 }.map { items[$0] }
    }
}
