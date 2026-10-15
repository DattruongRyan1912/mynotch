import AppKit
import ApplicationServices

/// A window of another app, reached through the Accessibility API.
final class AccessibilityWindow: SnapWindow, WindowAttributes {
    /// A hung app would hold each call until the timeout, and the main thread with it: reads while a drag is watched
    /// have to be quick, and the writes of one placement have to be given a little longer to be taken.
    static let readTimeout: Float = 0.1
    static let writeTimeout: Float = 0.5

    /// The attribute Chrome and other apps turn on while assistive technology is at work, and under which they animate or
    /// ignore moves from outside. Not in the public headers, but the same string every window manager uses.
    private static let enhancedUserInterface = "AXEnhancedUserInterface" as CFString

    private let element: AXUIElement
    /// The app the window belongs to: the switch above is on it, not on the window.
    private lazy var application: AXUIElement? = {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, Self.readTimeout)
        return application
    }()

    init(_ element: AXUIElement) {
        self.element = element
        AXUIElementSetMessagingTimeout(element, Self.readTimeout)
    }

    /// The owner of the element, for the log and the notice. No Accessibility call: the element knows its process.
    private var owner: NSRunningApplication? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        return NSRunningApplication(processIdentifier: pid)
    }

    var app: SnapApp { SnapApp(bundleID: owner?.bundleIdentifier, name: owner?.localizedName) }

    /// The app's own flag first (no call into the app), then the window's minimised attribute (one read).
    var isOutOfSight: Bool {
        if owner?.isHidden == true { return true }
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == CFBooleanGetTypeID() else { return false }
        return CFBooleanGetValue(unsafeDowncast(raw, to: CFBoolean.self))
    }

    func frame() -> CGRect? {
        guard let origin = position(), let size = size() else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// The order of the calls and what is done about a size the app did not take are `WindowPlacer`'s.
    @discardableResult
    func place(_ placement: SnapPlacement) -> SnapOutcome {
        let application = application
        AXUIElementSetMessagingTimeout(element, Self.writeTimeout)
        if let application { AXUIElementSetMessagingTimeout(application, Self.writeTimeout) }
        defer {
            AXUIElementSetMessagingTimeout(element, Self.readTimeout)
            if let application { AXUIElementSetMessagingTimeout(application, Self.readTimeout) }
        }
        return WindowPlacer.place(placement, on: self)
    }

    func enhancedUserInterface() -> Bool? {
        guard let application else { return nil }
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, Self.enhancedUserInterface, &raw) == .success,
              let raw, CFGetTypeID(raw) == CFBooleanGetTypeID() else { return nil }
        return CFBooleanGetValue(unsafeDowncast(raw, to: CFBoolean.self))
    }

    func setEnhancedUserInterface(_ on: Bool) -> Bool {
        guard let application else { return false }
        return AXUIElementSetAttributeValue(application, Self.enhancedUserInterface, on ? kCFBooleanTrue : kCFBooleanFalse) == .success
    }

    func position() -> CGPoint? {
        var point = CGPoint.zero
        guard let value = value(kAXPositionAttribute, as: .cgPoint), AXValueGetValue(value, .cgPoint, &point) else { return nil }
        return point
    }

    func size() -> CGSize? {
        var size = CGSize.zero
        guard let value = value(kAXSizeAttribute, as: .cgSize), AXValueGetValue(value, .cgSize, &size) else { return nil }
        return size
    }

    func setPosition(_ position: CGPoint) -> Bool {
        var position = position
        guard let value = AXValueCreate(.cgPoint, &position) else { return false }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value) == .success
    }

    func setSize(_ size: CGSize) -> Bool {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value) == .success
    }

    func isSame(as other: any SnapWindow) -> Bool {
        guard let other = other as? AccessibilityWindow else { return false }
        return CFEqual(element, other.element)
    }

    private func value(_ attribute: String, as type: AXValueType) -> AXValue? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let value = unsafeDowncast(raw, to: AXValue.self)
        return AXValueGetType(value) == type ? value : nil
    }
}

/// Finds the focused window of the app in front through the system Accessibility API. Reading never prompts: without the
/// permission every call simply fails.
final class SystemWindowProbe: WindowProbe {
    func focusedWindow() -> (any SnapWindow)? {
        // MyNotch's own windows (Settings, the clipboard panel) are never snapped, and asking one's own process through
        // Accessibility from its own main thread has nothing to gain.
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, AccessibilityWindow.readTimeout)
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return AccessibilityWindow(unsafeDowncast(raw, to: AXUIElement.self))
    }
}

/// The displays as AppKit reports them now.
enum SystemScreens {
    static func current() -> SnapScreens {
        let screens = NSScreen.screens
        return SnapScreens(
            screens: screens.compactMap { screen in
                (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
                    .map { SnapScreen(id: $0.uint32Value, visibleFrame: screen.visibleFrame) }
            },
            // The first screen is the one with the menu bar, whose top left is the origin of Accessibility coordinates.
            primaryHeight: screens.first?.frame.height ?? 0
        )
    }
}
