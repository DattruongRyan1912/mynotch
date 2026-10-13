import CoreGraphics
import MyNotchCore
import UniformTypeIdentifiers

/// Picks the tab that receives a drop and decides when a drag opens the notch.
enum DropRouting {
    /// What a pointer update means for drag mode.
    enum DragAction: Equatable {
        case enter(ModuleID)
        case exit
        case none
    }

    /// The tab accepting any of the dragged pasteboard `types` (identifiers), directly or through conformance:
    /// `preferring` when it accepts them (the tab already shown keeps the drop), else the first one that does.
    static func tab(for types: [String], tabs: [NotchTab], preferring: ModuleID? = nil) -> ModuleID? {
        let dragged = types.compactMap { UTType($0) }
        func accepts(_ tab: NotchTab) -> Bool {
            tab.dropTypes.contains { accepted in dragged.contains { $0.conforms(to: accepted) } }
        }
        return (tabs.first { $0.id == preferring && accepts($0) } ?? tabs.first(where: accepts))?.id
    }

    /// Whether a pointer update starts, ends or leaves drag mode. Only a real pointer move starts a drag: a refresh
    /// (the notch changed shape under a still pointer) may keep drag mode but never re-enter it, and a drag that began
    /// inside the notch (an item dragged out) never opens it.
    static func dragAction(
        dropTab: ModuleID?, inside: Bool, isDragging: Bool, startedInside: Bool, isRefresh: Bool
    ) -> DragAction {
        guard inside, let dropTab else { return .exit }
        return isDragging || startedInside || isRefresh ? .none : .enter(dropTab)
    }
}
