import AppKit
import CoreGraphics
import MyNotchCore
import UniformTypeIdentifiers

/// Picks the tab that receives a drop and decides when a drag opens the notch.
public enum DropRouting {
    /// What a pointer update means for drag mode.
    enum DragAction: Equatable {
        case enter(ModuleID)
        case exit
        case none
    }

    /// The tab accepting any of the dragged pasteboard `types` (identifiers), directly or through conformance:
    /// Prioritizes tabs that match specific data types over generic container types (.fileURL).
    static func tab(for types: [String], tabs: [NotchTab], preferring: ModuleID? = nil) -> ModuleID? {
        let dragged = types.compactMap { UTType($0) }

        func specificallyAccepts(_ tab: NotchTab) -> Bool {
            tab.dropTypes.contains { accepted in
                guard accepted != .fileURL else { return false }
                return dragged.contains { $0 != .fileURL && $0.conforms(to: accepted) }
            }
        }

        func accepts(_ tab: NotchTab) -> Bool {
            tab.dropTypes.contains { accepted in
                dragged.contains { $0.conforms(to: accepted) }
            }
        }

        // Priority 1: Specific Match (e.g. applicationBundle or image)
        if let specific = (tabs.first { $0.id == preferring && specificallyAccepts($0) } ?? tabs.first(where: specificallyAccepts)) {
            return specific.id
        }

        // Priority 2: Generic Match (e.g. fileURL fallback)
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

    public nonisolated static func isApplicationURL(_ url: URL) -> Bool {
        let stdURL = url.standardized
        if stdURL.pathExtension.lowercased() == "app" { return true }
        if let values = try? stdURL.resourceValues(forKeys: [.contentTypeKey]),
           let contentType = values.contentType,
           contentType.conforms(to: .application) || contentType.conforms(to: .applicationBundle) {
            return true
        }
        return false
    }

    static func enrichedTypes(from types: [String], pasteboard: NSPasteboard? = nil) -> [String] {
        var result = types
        let pb = pasteboard ?? NSPasteboard(name: .drag)
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            if urls.contains(where: isApplicationURL) {
                if !result.contains(UTType.applicationBundle.identifier) {
                    result.append(UTType.applicationBundle.identifier)
                }
                if !result.contains(UTType.application.identifier) {
                    result.append(UTType.application.identifier)
                }
            }
        }
        return result
    }
}
