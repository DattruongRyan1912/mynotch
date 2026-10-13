import AppKit

/// Reports pointer movement and mouse-button presses anywhere on screen. Mouse monitors need no Accessibility permission.
final class NotchHoverTracker {
    private var monitors: [Any] = []
    private let onMove: (CGPoint) -> Void
    private let onMouseDown: (CGPoint) -> Void

    init(onMove: @escaping (CGPoint) -> Void, onMouseDown: @escaping (CGPoint) -> Void) {
        self.onMove = onMove
        self.onMouseDown = onMouseDown
    }

    func start() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .rightMouseDown]
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
        case .leftMouseDown, .rightMouseDown: onMouseDown(point)
        default: onMove(point)
        }
    }
}
