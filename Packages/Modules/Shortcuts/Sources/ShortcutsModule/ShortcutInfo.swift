import Foundation

/// One Apple Shortcut as `shortcuts list --show-identifiers` reports it.
nonisolated struct ShortcutInfo: Hashable, Sendable, Identifiable {
    let id: String
    let name: String
}

/// Reads the CLI's "Name (UUID)" lines.
nonisolated enum ShortcutListParser {
    /// The identifier is the last parenthesised UUID, so names may contain parentheses. Other lines (warnings) are dropped.
    static func parse(_ output: String) -> [ShortcutInfo] {
        var seen = Set<String>()
        return output.split(whereSeparator: \.isNewline).compactMap { line in
            let line = line.trimmingCharacters(in: .whitespaces)
            guard line.hasSuffix(")"), let open = line.lastIndex(of: "(") else { return nil }
            let id = String(line[line.index(after: open)..<line.index(before: line.endIndex)])
            let name = line[..<open].trimmingCharacters(in: .whitespaces)
            guard UUID(uuidString: id) != nil, !name.isEmpty, seen.insert(id).inserted else { return nil }
            return ShortcutInfo(id: id, name: name)
        }
    }
}

/// Settings-side helpers for the favourites: they are stored as identifiers, each with a hotkey of its own.
nonisolated enum ShortcutFavorites {
    /// Adds or removes `id`, keeping the order the user chose and never duplicating.
    static func setting(_ id: String, isFavorite: Bool, in favorites: [String]) -> [String] {
        let others = favorites.filter { $0 != id }
        return isFavorite ? (favorites.contains(id) ? favorites : others + [id]) : others
    }

    /// `HotkeyRegistry` names must not contain ".", and KeyboardShortcuts keeps them in defaults, so only letters and digits stay.
    static func hotkeyName(for id: String) -> String {
        "run_" + String(id.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "_" })
    }
}
