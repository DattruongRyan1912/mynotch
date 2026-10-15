import AppKit

/// What closes every open board by itself, besides the idle time: the Mac going to sleep, the screens sleeping, the screen being
/// locked, another user taking the session. Injected so tests post their own notifications on centers of their own.
struct ClipboardLockTriggers {
    struct Source {
        var center: NotificationCenter
        var names: [Notification.Name]
    }

    var sources: [Source]

    static var system: ClipboardLockTriggers {
        ClipboardLockTriggers(sources: [
            Source(
                center: NSWorkspace.shared.notificationCenter,
                names: [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification]
            ),
            // The lock screen has no public notification; this one is what the system posts when it comes up.
            Source(center: DistributedNotificationCenter.default(), names: [Notification.Name("com.apple.screenIsLocked")]),
        ])
    }
}
