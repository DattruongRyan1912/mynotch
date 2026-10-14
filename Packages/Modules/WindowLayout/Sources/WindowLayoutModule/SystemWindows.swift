import AppKit
import ApplicationServices

/// A window of another app, reached through the Accessibility API.
final class AccessibilityWindow: SnapWindow, WindowAttributes {
    /// A hung app would hold each call until the timeout, and the main thread with it: reads while a drag is watched
    /// have to be quick, and the writes of one placement have to be given a little longer to be taken.
    static let readTimeout: Float = 0.1
    static let writeTimeout: Float = 0.5

    private let element: AXUIElement

    init(_ element: AXUIElement) {
        self.element = element
        AXUIElementSetMessagingTimeout(element, Self.readTimeout)
    }

    func frame() -> CGRect? {
        guard let origin = position(), let size = size() else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// The order of the calls and what is done about a size the app did not take are `WindowPlacer`'s.
    @discardableResult
    func place(_ placement: SnapPlacement) -> Bool {
        AXUIElementSetMessagingTimeout(element, Self.writeTimeout)
        defer { AXUIElementSetMessagingTimeout(element, Self.readTimeout) }
        return WindowPlacer.place(placement, on: self)
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
