import AppKit

/// Brings an app back to the front, so a replacement lands in it; a protocol so tests never switch apps.
protocol ApplicationActivating {
    /// False when the app has quit.
    func activate(_ application: FocusedApplication) -> Bool
    func isFrontmost(_ application: FocusedApplication) -> Bool
}

struct SystemApplicationActivator: ApplicationActivating {
    func activate(_ application: FocusedApplication) -> Bool {
        NSRunningApplication(processIdentifier: application.processID)?.activate() ?? false
    }

    func isFrontmost(_ application: FocusedApplication) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processID
    }
}
