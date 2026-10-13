import MyNotchCore
import UniformTypeIdentifiers

/// Picks the tab that receives a drop.
enum DropRouting {
    /// The first tab accepting any of the dragged pasteboard `types` (identifiers), directly or through conformance.
    static func tab(for types: [String], tabs: [NotchTab]) -> ModuleID? {
        let dragged = types.compactMap { UTType($0) }
        return tabs.first { tab in tab.dropTypes.contains { accepted in dragged.contains { $0.conforms(to: accepted) } } }?.id
    }
}
