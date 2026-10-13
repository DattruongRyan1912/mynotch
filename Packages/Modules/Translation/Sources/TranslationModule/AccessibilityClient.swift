import AppKit
import ApplicationServices

/// The app that has keyboard focus.
nonisolated struct FocusedApplication: Hashable, Sendable {
    var processID: pid_t
    var bundleID: String?
}

/// What one read of the focused element's selection found.
nonisolated enum SelectionRead: Equatable, Sendable {
    case text(String)
    /// No selection, or the app doesn't expose it (yet).
    case empty
    /// The app didn't answer within the timeout (`kAXErrorCannotComplete`); asking again would block again.
    case unresponsive
}

/// The Accessibility calls `SelectionReader` makes, so its retry logic is testable without AX.
protocol AccessibilityClient: AnyObject {
    /// Whether MyNotch has the Accessibility permission. Checking never prompts.
    var isTrusted: Bool { get }
    func focusedApplication() -> FocusedApplication?
    func readSelection(in application: FocusedApplication) -> SelectionRead
    /// Whether a boolean attribute of the application element is already true.
    func isEnabled(_ attribute: String, in application: FocusedApplication) -> Bool
    /// Sets a boolean attribute of the application element to true.
    func enable(_ attribute: String, in application: FocusedApplication)
}

/// Reads through the system Accessibility API.
final class SystemAccessibilityClient: AccessibilityClient {
    /// AX calls block until the target app answers; a hung app must not freeze the notch for longer than this.
    /// Set on each element the target app answers for: on the system-wide element it would become the default
    /// for every AX call MyNotch makes.
    private static let timeout: Float = 0.25

    var isTrusted: Bool { AXIsProcessTrusted() }

    func focusedApplication() -> FocusedApplication? {
        guard let app = Self.element(Self.copyValue(kAXFocusedApplicationAttribute, of: AXUIElementCreateSystemWide()).value) else {
            return nil
        }
        var processID: pid_t = 0
        guard AXUIElementGetPid(app, &processID) == .success else { return nil }
        return FocusedApplication(processID: processID, bundleID: NSRunningApplication(processIdentifier: processID)?.bundleIdentifier)
    }

    func readSelection(in application: FocusedApplication) -> SelectionRead {
        let focused = Self.copyValue(kAXFocusedUIElementAttribute, of: Self.element(for: application))
        guard let element = Self.element(focused.value) else { return focused.error == .cannotComplete ? .unresponsive : .empty }
        AXUIElementSetMessagingTimeout(element, Self.timeout)
        let selected = Self.copyValue(kAXSelectedTextAttribute, of: element)
        guard let text = selected.value as? String else { return selected.error == .cannotComplete ? .unresponsive : .empty }
        return .text(text)
    }

    func isEnabled(_ attribute: String, in application: FocusedApplication) -> Bool {
        Self.copyValue(attribute, of: Self.element(for: application)).value as? Bool == true
    }

    func enable(_ attribute: String, in application: FocusedApplication) {
        AXUIElementSetAttributeValue(Self.element(for: application), attribute as CFString, kCFBooleanTrue)
    }

    private static func element(for application: FocusedApplication) -> AXUIElement {
        let element = AXUIElementCreateApplication(application.processID)
        AXUIElementSetMessagingTimeout(element, timeout)
        return element
    }

    private static func copyValue(_ attribute: String, of element: AXUIElement) -> (error: AXError, value: CFTypeRef?) {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return (error, error == .success ? value : nil)
    }

    /// Checked by type ID: a cast to a Core Foundation type always succeeds.
    private static func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }
}
