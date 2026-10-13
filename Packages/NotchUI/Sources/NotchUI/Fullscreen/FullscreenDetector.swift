import AppKit

/// Watches Space, app and display changes and reports which displays are covered by a fullscreen window of another app.
final class FullscreenDetector {
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var recheck: Task<Void, Never>?
    private let onChange: (Set<CGDirectDisplayID>) -> Void

    init(onChange: @escaping (Set<CGDirectDisplayID>) -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard observers.isEmpty else { return }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let subscriptions: [(NotificationCenter, Notification.Name)] = [
            (workspaceCenter, NSWorkspace.activeSpaceDidChangeNotification),
            (workspaceCenter, NSWorkspace.didActivateApplicationNotification),
            (NotificationCenter.default, NSApplication.didChangeScreenParametersNotification),
        ]
        for (center, name) in subscriptions {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluateSoon() }
            }
            observers.append((center: center, token: token))
        }
        evaluate()
    }

    func stop() {
        for observer in observers {
            observer.center.removeObserver(observer.token)
        }
        observers.removeAll()
        recheck?.cancel()
        recheck = nil
    }

    /// Evaluate now and again after the Space transition animation settles.
    private func evaluateSoon() {
        evaluate()
        recheck?.cancel()
        recheck = Task { [weak self] in
            for delay in [500, 1000] {   // 0.5 s and 1.5 s after the event
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled else { return }
                self?.evaluate()
            }
        }
    }

    private func evaluate() {
        let windows = Self.onScreenWindows()
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let covered = NSScreen.screens.compactMap { screen -> CGDirectDisplayID? in
            guard let displayID = screen.displayID else { return nil }
            let isCovered = FullscreenRule.isFullscreen(
                windows: windows, ownPID: ownPID,
                displayBounds: CGDisplayBounds(displayID), topInset: screen.safeAreaInsets.top
            )
            return isCovered ? displayID : nil
        }
        onChange(Set(covered))
    }

    private static func onScreenWindows() -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { return nil }
            return WindowInfo(ownerPID: pid, layer: layer, bounds: bounds)
        }
    }
}
