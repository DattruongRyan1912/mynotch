import AppKit
import Foundation

/// A notification's payload, which is only ever read, on the main queue it was delivered on.
private nonisolated struct Payload: @unchecked Sendable {
    var values: [AnyHashable: Any]
}

/// What the module needs of the machine to follow Music and Spotify, so that a test runs none of it: the notifications the players
/// post, an app quitting, and whether an app is running. The module never starts an app, and asks about an app only while it runs.
struct MediaAppEnvironment {
    /// Calls `handler` with what each distributed notification of this name carries, until the returned closure is called.
    var observe: (_ name: String, _ handler: @escaping @MainActor ([AnyHashable: Any]) -> Void) -> () -> Void
    /// Calls `handler` with the bundle id of each app that quits, until the returned closure is called.
    var observeQuit: (_ handler: @escaping @MainActor (String) -> Void) -> () -> Void
    var isRunning: (String) -> Bool

    /// Nothing is heard and nothing runs: what a module made for a test has.
    static let inert = MediaAppEnvironment(observe: { _, _ in {} }, observeQuit: { _ in {} }, isRunning: { _ in false })

    /// The real thing: the distributed notification center (which a player posts to without any permission being asked), the
    /// workspace's notifications, and the running applications.
    static let system = MediaAppEnvironment(
        observe: { name, handler in
            let center = DistributedNotificationCenter.default()
            let token = center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { notification in
                let info = Payload(values: notification.userInfo ?? [:])
                MainActor.assumeIsolated { handler(info.values) }
            }
            return { center.removeObserver(token) }
        },
        observeQuit: { handler in
            let center = NSWorkspace.shared.notificationCenter
            let token = center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard let bundleID = app?.bundleIdentifier else { return }
                MainActor.assumeIsolated { handler(bundleID) }
            }
            return { center.removeObserver(token) }
        },
        isRunning: { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }
    )
}
