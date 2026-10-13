import AppKit

/// Watches Space and app changes and reports which displays are covered by a fullscreen app.
final class FullscreenDetector {
    private var observers: [NSObjectProtocol] = []
    private var recheck: Task<Void, Never>?
    private let onChange: (Set<CGDirectDisplayID>) -> Void

    init(onChange: @escaping (Set<CGDirectDisplayID>) -> Void) {
        self.onChange = onChange
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluateSoon() }
            })
        }
        evaluate()
    }

    func stop() {
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers.removeAll()
        recheck?.cancel()
    }

    /// Evaluate now and again after the Space transition animation settles.
    private func evaluateSoon() {
        evaluate()
        recheck?.cancel()
        recheck = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.evaluate()
        }
    }

    private func evaluate() {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            onChange([])
            return
        }
        let windows = Self.onScreenWindows()
        let covered = NSScreen.screens.compactMap(\.displayID).filter { displayID in
            FullscreenRule.isFullscreen(windows: windows, frontmostPID: pid, displayBounds: CGDisplayBounds(displayID))
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
