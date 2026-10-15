import AppKit

/// Watches Space, app and display changes and reports which displays are covered by a fullscreen window of another app.
final class FullscreenDetector {
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var recheck: Task<Void, Never>?
    private let onChange: (Set<CGDirectDisplayID>) -> Void
    private let onActivate: (CGDirectDisplayID?) -> Void

    /// `onActivate` hears the display the window of each app that comes to the front is on, once, when it does.
    init(onChange: @escaping (Set<CGDirectDisplayID>) -> Void, onActivate: @escaping (CGDirectDisplayID?) -> Void = { _ in }) {
        self.onChange = onChange
        self.onActivate = onActivate
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
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let activatedPID = name == NSWorkspace.didActivateApplicationNotification ? app?.processIdentifier : nil
                MainActor.assumeIsolated {
                    self?.evaluateSoon()
                    if let activatedPID { self?.activated(pid: activatedPID) }
                }
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

    private func activated(pid: pid_t) {
        let displays = NSScreen.screens.compactMap { screen in screen.displayID.map { (displayID: $0, bounds: CGDisplayBounds($0)) } }
        onActivate(DisplaySelection.display(ofFrontWindowOf: pid, in: Self.onScreenWindows(), on: displays))
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
