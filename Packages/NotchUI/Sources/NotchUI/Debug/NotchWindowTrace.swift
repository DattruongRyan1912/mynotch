import AppKit

extension NSWindow {
    /// Everything that decides whether the panel can be seen or used, on one line.
    var logSummary: String {
        "window=\(windowNumber) frame=\(frame.logDescription) alpha=\(alphaValue) visible=\(isVisible) "
            + "occluded=\(!occlusionState.contains(.visible)) key=\(isKeyWindow) ignoresMouse=\(ignoresMouseEvents)"
    }
}

#if DEBUG
/// Logs the panel's frame, alpha, visibility, occlusion and key changes however they come about, so a change the
/// controller did not make itself (AppKit, SwiftUI, the window server) shows up next to the ones it did.
final class NotchWindowTrace {
    private var tokens: [NSObjectProtocol] = []
    private var observations: [NSKeyValueObservation] = []

    init(_ panel: NSPanel) {
        let center = NotificationCenter.default
        let names: [(Notification.Name, String)] = [
            (NSWindow.didResizeNotification, "resized"),
            (NSWindow.didMoveNotification, "moved"),
            (NSWindow.didChangeScreenNotification, "changed screen"),
            (NSWindow.didChangeOcclusionStateNotification, "changed occlusion"),
            (NSWindow.didBecomeKeyNotification, "became key"),
            (NSWindow.didResignKeyNotification, "resigned key"),
        ]
        for (name, label) in names {
            tokens.append(center.addObserver(forName: name, object: panel, queue: .main) { [weak panel] _ in
                MainActor.assumeIsolated { NotchLog.record("window \(label) \(panel?.logSummary ?? "gone")") }
            })
        }
        observations.append(panel.observe(\.alphaValue, options: [.old, .new]) { panel, change in
            let (old, new) = (change.oldValue, change.newValue)
            MainActor.assumeIsolated { NotchLog.record("window alpha \(old ?? .nan) -> \(new ?? .nan) \(panel.logSummary)") }
        })
        observations.append(panel.observe(\.isVisible, options: [.old, .new]) { panel, change in
            let (old, new) = (change.oldValue, change.newValue)
            MainActor.assumeIsolated {
                NotchLog.record("window visible \(old.map(String.init) ?? "?") -> \(new.map(String.init) ?? "?") \(panel.logSummary)")
            }
        })
    }

    isolated deinit {
        tokens.forEach(NotificationCenter.default.removeObserver)
    }
}
#endif
