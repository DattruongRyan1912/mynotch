import Foundation

/// Keyboard selection in the card row. Nothing selected, or a selection the search filtered away, counts as the
/// first card: the tab marks it and Return activates it, so moving starts from there. Moving stops at either end.
nonisolated enum ClipboardSelection {
    /// The selected id while it is still shown, else the first; nil only for an empty row.
    static func current<ID: Equatable>(in ids: [ID], selected: ID?) -> ID? {
        guard let selected, ids.contains(selected) else { return ids.first }
        return selected
    }

    static func next<ID: Equatable>(in ids: [ID], current: ID?) -> ID? {
        step(in: ids, from: current, by: 1)
    }

    static func previous<ID: Equatable>(in ids: [ID], current: ID?) -> ID? {
        step(in: ids, from: current, by: -1)
    }

    private static func step<ID: Equatable>(in ids: [ID], from current: ID?, by offset: Int) -> ID? {
        guard !ids.isEmpty else { return nil }
        let index = current.flatMap { ids.firstIndex(of: $0) } ?? 0
        return ids[min(max(index + offset, 0), ids.count - 1)]
    }
}
