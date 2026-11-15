import AppKit

/// Brings an app back to the front, so a replacement lands in it; a protocol so tests never switch apps.
protocol ApplicationActivating {
    /// False when the app has quit.
    func activate(_ application: FocusedApplication) -> Bool
    func isFrontmost(_ application: FocusedApplication) -> Bool
    /// Whether one of MyNotch's own windows is key. The notch's panel never makes MyNotch the active app, but it is key
    /// while the Translation input has the keyboard, and a ⌘V sent then goes to it, not to the app in front.
    var myNotchHoldsKeyboard: Bool { get }
}

struct SystemApplicationActivator: ApplicationActivating {
    func activate(_ application: FocusedApplication) -> Bool {
        NSRunningApplication(processIdentifier: application.processID)?.activate() ?? false
    }

    func isFrontmost(_ application: FocusedApplication) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processID
    }

    var myNotchHoldsKeyboard: Bool { NSApp.windows.contains(where: \.isKeyWindow) }
}
