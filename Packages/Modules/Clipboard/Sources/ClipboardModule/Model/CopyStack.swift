import Foundation
import SwiftUI

/// Which copy the stack pastes next.
nonisolated enum CopyStackOrder: String, Codable, Sendable, CaseIterable {
    /// The oldest copy first, like a queue: what was copied first lands first.
    case firstIn
    /// The newest copy first, like a pile.
    case lastIn
}

/// One copy on the stack. It has an id of its own because the same item can be copied twice and sit on the stack twice,
/// and the list needs to tell the two rows apart.
nonisolated struct CopyStackEntry: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    let item: ClipboardItem
}

/// Copies collected one after another while the stack is on, to be pasted one by one. A value, so every rule is testable
/// without a pasteboard. Entries are kept in the order they were copied; the setting only decides which one is next.
/// Off always means empty: stopping forgets what was collected.
nonisolated struct CopyStack: Codable, Equatable, Sendable {
    private(set) var isOn = false
    private(set) var entries: [CopyStackEntry] = []

    init() {}

    /// A file that says "off" never brings entries back, whatever else it holds.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isOn = try container.decode(Bool.self, forKey: .isOn)
        entries = isOn ? try container.decode([CopyStackEntry].self, forKey: .entries) : []
    }

    /// Starting a stack that is already on keeps what it holds.
    mutating func start() {
        isOn = true
    }

    mutating func stop() {
        isOn = false
        entries = []
    }

    /// Appends the copy; false while the stack is off.
    @discardableResult
    mutating func collect(_ item: ClipboardItem) -> Bool {
        guard isOn else { return false }
        entries.append(CopyStackEntry(id: UUID(), item: item))
        return true
    }

    /// nil when the stack holds nothing.
    func next(_ order: CopyStackOrder) -> CopyStackEntry? {
        switch order {
        case .firstIn: entries.first
        case .lastIn: entries.last
        }
    }

    mutating func remove(id: UUID) {
        removeEntries { $0.id == id }
    }

    /// For entries that can no longer be used, like an image whose file is gone.
    mutating func removeEntries(where shouldRemove: (CopyStackEntry) -> Bool) {
        entries.removeAll(where: shouldRemove)
    }

    /// In the terms of a list's drag, so the list can pass its report straight on.
    mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        entries.move(fromOffsets: source, toOffset: destination)
    }

    /// Empties the stack and leaves it on, ready for the next copies.
    mutating func clear() {
        entries = []
    }
}
