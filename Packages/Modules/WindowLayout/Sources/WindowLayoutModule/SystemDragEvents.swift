import AppKit

/// The system's mouse monitors, and a key monitor for Escape while a window is dragged. Mouse monitors need no
/// permission; the key monitor needs Accessibility, which a window drag needs anyway, and only exists during a drag.
final class SystemDragEvents: DragEventSource {
    private static let escapeKeyCode: UInt16 = 53

    private var mouseMonitors: [Any] = []
    private var keyMonitors: [Any] = []
    private var handler: (@MainActor (DragEvent) -> Void)?

    func start(_ handler: @escaping @MainActor (DragEvent) -> Void) {
        stop()
        self.handler = handler
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        // Global monitors only see the events of other apps: MyNotch's own windows are never snapped (the probe skips them).
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let (type, time) = (event.type, event.timestamp)
            MainActor.assumeIsolated { self?.mouse(type, at: time) }
        }) {
            mouseMonitors.append(global)
        }
    }

    func stop() {
        mouseMonitors.forEach(NSEvent.removeMonitor)
        mouseMonitors.removeAll()
        removeKeyMonitors()
        handler = nil
    }

    func setWatchingEscape(_ watching: Bool) {
        guard watching != !keyMonitors.isEmpty else { return }
        guard watching else { return removeKeyMonitors() }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            let code = event.keyCode
            MainActor.assumeIsolated { self?.key(code) }
        }) {
            keyMonitors.append(global)
        }
    }

    private func removeKeyMonitors() {
        keyMonitors.forEach(NSEvent.removeMonitor)
        keyMonitors.removeAll()
    }

    private func mouse(_ type: NSEvent.EventType, at time: TimeInterval) {
        let point = NSEvent.mouseLocation
        switch type {
        case .leftMouseDown: handler?(.down)
        case .leftMouseDragged: handler?(.dragged(point, time: time))
        case .leftMouseUp: handler?(.up(point))
        default: break
        }
    }

    private func key(_ code: UInt16) {
        if code == Self.escapeKeyCode { handler?(.escape) }
    }
}
