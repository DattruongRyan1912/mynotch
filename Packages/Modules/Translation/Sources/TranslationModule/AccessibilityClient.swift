import AppKit
import ApplicationServices

/// The app that has keyboard focus.
nonisolated struct FocusedApplication: Equatable, Sendable {
    var processID: pid_t
    var bundleID: String?
}

/// The Accessibility calls `SelectionReader` makes, so its retry logic is testable without AX.
protocol AccessibilityClient: AnyObject {
    /// Whether MyNotch has the Accessibility permission. Checking never prompts.
    var isTrusted: Bool { get }
    func focusedApplication() -> FocusedApplication?
    /// The selection in the application's focused element; nil when AX reports none or fails.
    func selectedText(in application: FocusedApplication) -> String?
    /// Sets a boolean attribute on the application element to true.
    func enable(_ attribute: String, in application: FocusedApplication)
}

/// Reads through the system Accessibility API.
final class SystemAccessibilityClient: AccessibilityClient {
    /// AX calls block until the target app answers; a hung app must not freeze the notch for longer than this.
    /// On the system-wide element this is also the default for every other AX call MyNotch makes.
    private static let timeout: Float = 0.25

    var isTrusted: Bool { AXIsProcessTrusted() }

    func focusedApplication() -> FocusedApplication? {
        guard let app = copyElement(kAXFocusedApplicationAttribute, of: Self.withTimeout(AXUIElementCreateSystemWide())) else { return nil }
        var processID: pid_t = 0
        guard AXUIElementGetPid(app, &processID) == .success else { return nil }
        return FocusedApplication(processID: processID, bundleID: NSRunningApplication(processIdentifier: processID)?.bundleIdentifier)
    }

    func selectedText(in application: FocusedApplication) -> String? {
        guard let focused = copyElement(kAXFocusedUIElementAttribute, of: Self.element(for: application)) else { return nil }
        return copyValue(kAXSelectedTextAttribute, of: Self.withTimeout(focused)) as? String
    }

    func enable(_ attribute: String, in application: FocusedApplication) {
        AXUIElementSetAttributeValue(Self.element(for: application), attribute as CFString, kCFBooleanTrue)
    }

    private static func element(for application: FocusedApplication) -> AXUIElement {
        withTimeout(AXUIElementCreateApplication(application.processID))
    }

    private static func withTimeout(_ element: AXUIElement) -> AXUIElement {
        AXUIElementSetMessagingTimeout(element, timeout)
        return element
    }

    private func copyValue(_ attribute: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    /// Checked by type ID: a cast to a Core Foundation type always succeeds.
    private func copyElement(_ attribute: String, of element: AXUIElement) -> AXUIElement? {
        guard let value = copyValue(attribute, of: element), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }
}
