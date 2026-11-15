import AppKit

/// Reports pointer movement and mouse-button presses anywhere on screen, and the pasteboard types of a drag that
/// carries data. Mouse monitors need no Accessibility permission.
final class NotchHoverTracker {
    private var monitors: [Any] = []
    private let onMove: (CGPoint, [String]) -> Void
    private let onMouseDown: (CGPoint) -> Void
    /// Drag pasteboard change count at the last mouse-down; a drag that changed it carries data.
    private var dragChangeCount = NSPasteboard(name: .drag).changeCount
    private var cachedDragTypes: (changeCount: Int, types: [String])?

    init(onMove: @escaping (CGPoint, [String]) -> Void, onMouseDown: @escaping (CGPoint) -> Void) {
        self.onMove = onMove
        self.onMouseDown = onMouseDown
    }

    func start() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseUp, .leftMouseDown, .rightMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.report(type) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.report(type) }
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    private func report(_ type: NSEvent.EventType) {
        let point = NSEvent.mouseLocation
        switch type {
        case .leftMouseDown:
            dragChangeCount = NSPasteboard(name: .drag).changeCount
            cachedDragTypes = nil
            onMouseDown(point)
        case .rightMouseDown: onMouseDown(point)
        case .leftMouseDragged:
            let pasteboard = NSPasteboard(name: .drag)
            let currentCount = pasteboard.changeCount
            if currentCount == dragChangeCount {
                onMove(point, [])
            } else {
                if let cached = cachedDragTypes, cached.changeCount == currentCount {
                    onMove(point, cached.types)
                } else {
                    let rawTypes = pasteboard.types?.map(\.rawValue) ?? []
                    let types = DropRouting.enrichedTypes(from: rawTypes, pasteboard: pasteboard)
                    cachedDragTypes = (currentCount, types)
                    onMove(point, types)
                }
            }
        default: onMove(point, [])
        }
    }
}
