import AppKit
import Observation

/// Something that happens to the whole Mac and puts the panel out of sight without a word to its window.
enum SystemPresenceEvent: Equatable {
    case displaysSlept, displaysWoke, screenLocked, screenUnlocked
}

/// Where those events come from, as a value of one closure so that tests stand in for the system. `start` listens and returns
/// what stops it.
struct SystemPresenceEvents {
    var start: (@escaping @MainActor (SystemPresenceEvent) -> Void) -> () -> Void

    /// Display sleep from the workspace, the lock screen from the notifications the login window posts. Listening needs no
    /// permission and changes nothing.
    static let system = SystemPresenceEvents { handler in
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        let tokens: [(NotificationCenter, NSObjectProtocol)] = [
            (workspace, workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { handler(.displaysSlept) }
            }),
            (workspace, workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { handler(.displaysWoke) }
            }),
            (distributed, distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { handler(.screenLocked) }
            }),
            (distributed, distributed.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { handler(.screenUnlocked) }
            }),
        ]
        return { tokens.forEach { $0.0.removeObserver($0.1) } }
    }
}

/// Whether the lyrics panel can be seen right now: its window is shown and not covered, the displays are awake and the screen
/// is not locked. The panel's views read it as `notchIsOnScreen`, like the notch's, so their timeline stands still and their
/// sweep is taken away while it is false. Observable, so a change reaches them at once.
@Observable
final class LyricsPanelPresence {
    private(set) var windowIsVisible = false
    private(set) var displaysAreAsleep = false
    private(set) var screenIsLocked = false

    var isOnScreen: Bool { windowIsVisible && !displaysAreAsleep && !screenIsLocked }

    func setWindowVisible(_ isVisible: Bool) {
        if isVisible != windowIsVisible { windowIsVisible = isVisible }
    }

    func apply(_ event: SystemPresenceEvent) {
        switch event {
        case .displaysSlept: if !displaysAreAsleep { displaysAreAsleep = true }
        case .displaysWoke: if displaysAreAsleep { displaysAreAsleep = false }
        case .screenLocked: if !screenIsLocked { screenIsLocked = true }
        case .screenUnlocked: if screenIsLocked { screenIsLocked = false }
        }
    }

    /// Back to nothing seen and nothing slept: the panel is gone, and the next one starts clean.
    func reset() {
        setWindowVisible(false)
        apply(.displaysWoke)
        apply(.screenUnlocked)
    }
}
