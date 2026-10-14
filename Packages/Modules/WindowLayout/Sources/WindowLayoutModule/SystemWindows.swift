import AppKit
import ApplicationServices

/// A window of another app, reached through the Accessibility API.
final class AccessibilityWindow: SnapWindow {
    /// A hung app would hold each call until the timeout, and the main thread with it: reads while a drag is watched
    /// have to be quick, and one write has to be given a little longer to be taken.
    static let readTimeout: Float = 0.1
    static let writeTimeout: Float = 0.5

    private let element: AXUIElement

    init(_ element: AXUIElement) {
        self.element = element
        AXUIElementSetMessagingTimeout(element, Self.readTimeout)
    }

    func frame() -> CGRect? {
        guard let origin = point(kAXPositionAttribute), let size = size(kAXSizeAttribute) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// Size, then position, then size again when the first one did not stick: an app clamps a window to the display it is
    /// on, so a window that is moved to a smaller display first, or resized before it reached a larger one, ends up
    /// the wrong size for the display it lands on.
    @discardableResult
    func setFrame(_ frame: CGRect) -> Bool {
        AXUIElementSetMessagingTimeout(element, Self.writeTimeout)
        defer { AXUIElementSetMessagingTimeout(element, Self.readTimeout) }
        _ = set(kAXSizeAttribute, size: frame.size)
        let moved = set(kAXPositionAttribute, origin: frame.origin)
        if let now = self.frame(), abs(now.width - frame.width) >= 1 || abs(now.height - frame.height) >= 1 {
            _ = set(kAXSizeAttribute, size: frame.size)
        }
        return moved
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

    private func point(_ attribute: String) -> CGPoint? {
        var point = CGPoint.zero
        guard let value = value(attribute, as: .cgPoint), AXValueGetValue(value, .cgPoint, &point) else { return nil }
        return point
    }

    private func size(_ attribute: String) -> CGSize? {
        var size = CGSize.zero
        guard let value = value(attribute, as: .cgSize), AXValueGetValue(value, .cgSize, &size) else { return nil }
        return size
    }

    private func set(_ attribute: String, origin: CGPoint) -> Bool {
        var origin = origin
        guard let value = AXValueCreate(.cgPoint, &origin) else { return false }
        return AXUIElementSetAttributeValue(element, attribute as CFString, value) == .success
    }

    private func set(_ attribute: String, size: CGSize) -> Bool {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return false }
        return AXUIElementSetAttributeValue(element, attribute as CFString, value) == .success
    }
}

/// Finds the focused window of the app in front through the system Accessibility API. Reading never prompts: without the
/// permission every call simply fails.
final class SystemWindowProbe: WindowProbe {
    func focusedWindow() -> (any SnapWindow)? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
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
