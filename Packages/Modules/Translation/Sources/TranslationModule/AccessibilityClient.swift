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

/// Whether an app really took text written to its selection through Accessibility.
nonisolated enum SelectionReplacement {
    /// Judged by reading the selection back: apps that ignore the write still answer "success", and their selection is
    /// then unchanged. When either read failed, nothing says the write was ignored, so it counts.
    static func took(_ text: String, before: String?, after: String?) -> Bool {
        guard let before, let after else { return true }
        // Replacing a text with itself leaves the selection as it was.
        return after != before || before == text
    }
}

/// What marks a text field as a password field, which MyNotch never reads anything from: not its selection, nor how long
/// or where the selection is.
nonisolated enum SecureTextField {
    /// The role some apps give it, and the subrole macOS gives it (a text field whose subrole is `AXSecureTextField`).
    static func matches(role: String?, subrole: String?) -> Bool {
        role == "AXSecureTextField" || subrole == kAXSecureTextFieldSubrole
    }
}

/// The Accessibility calls `SelectionReader`, `SelectionReplacer` and the selection watcher make, so their logic is
/// testable without AX.
protocol AccessibilityClient: AnyObject {
    /// Whether MyNotch has the Accessibility permission. Checking never prompts.
    var isTrusted: Bool { get }
    func focusedApplication() -> FocusedApplication?
    /// The selected text of the focused element. Never the text of a password field: that reads as no selection.
    func readSelection(in application: FocusedApplication) -> SelectionRead
    /// How long the focused element's selected range is, in UTF-16 units as Accessibility counts, without reading the
    /// text, so a huge selection is never fetched. nil when the app does not say, and for a password field.
    func selectionLength(in application: FocusedApplication) -> Int?
    /// Where the focused element's selection is on screen, in Accessibility coordinates (the origin is the top left of the
    /// main display and y grows downward). nil when the app does not say, and for a password field.
    func selectionBounds(in application: FocusedApplication) -> CGRect?
    /// Whether a boolean attribute of the application element is already true.
    func isEnabled(_ attribute: String, in application: FocusedApplication) -> Bool
    /// Sets a boolean attribute of the application element to true.
    func enable(_ attribute: String, in application: FocusedApplication)
    /// Replaces the selection of the application's focused element with `text`. False when the app refused or ignored it.
    func replaceSelection(with text: String, in application: FocusedApplication) -> Bool
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
        // Asked of the very element whose text is read next, so focus cannot move to a password field in between.
        guard !Self.isSecure(element) else { return .empty }
        let selected = Self.copyValue(kAXSelectedTextAttribute, of: element)
        guard let text = selected.value as? String else { return selected.error == .cannotComplete ? .unresponsive : .empty }
        return .text(text)
    }

    func selectionLength(in application: FocusedApplication) -> Int? {
        Self.readableElement(in: application).flatMap(Self.selectedRange(of:))?.length
    }

    func selectionBounds(in application: FocusedApplication) -> CGRect? {
        guard let element = Self.readableElement(in: application), var range = Self.selectedRange(of: element), range.length > 0,
              let parameter = AXValueCreate(.cfRange, &range) else { return nil }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, parameter, &result) == .success,
              let result, CFGetTypeID(result) == AXValueGetTypeID() else { return nil }
        let value = unsafeDowncast(result, to: AXValue.self)
        var bounds = CGRect.zero
        guard AXValueGetType(value) == .cgRect, AXValueGetValue(value, .cgRect, &bounds) else { return nil }
        return bounds
    }

    func isEnabled(_ attribute: String, in application: FocusedApplication) -> Bool {
        Self.copyValue(attribute, of: Self.element(for: application)).value as? Bool == true
    }

    func enable(_ attribute: String, in application: FocusedApplication) {
        AXUIElementSetAttributeValue(Self.element(for: application), attribute as CFString, kCFBooleanTrue)
    }

    func replaceSelection(with text: String, in application: FocusedApplication) -> Bool {
        guard let element = Self.element(Self.copyValue(kAXFocusedUIElementAttribute, of: Self.element(for: application)).value) else {
            return false
        }
        AXUIElementSetMessagingTimeout(element, Self.timeout)
        let before = Self.copyValue(kAXSelectedTextAttribute, of: element).value as? String
        guard AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success else {
            return false
        }
        let after = Self.copyValue(kAXSelectedTextAttribute, of: element).value as? String
        return SelectionReplacement.took(text, before: before, after: after)
    }

    /// The application's focused element with the timeout set, unless it is a password field.
    private static func readableElement(in application: FocusedApplication) -> AXUIElement? {
        guard let element = element(copyValue(kAXFocusedUIElementAttribute, of: element(for: application)).value) else { return nil }
        AXUIElementSetMessagingTimeout(element, timeout)
        return isSecure(element) ? nil : element
    }

    private static func isSecure(_ element: AXUIElement) -> Bool {
        SecureTextField.matches(
            role: copyValue(kAXRoleAttribute, of: element).value as? String,
            subrole: copyValue(kAXSubroleAttribute, of: element).value as? String
        )
    }

    private static func selectedRange(of element: AXUIElement) -> CFRange? {
        guard let value = copyValue(kAXSelectedTextRangeAttribute, of: element).value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let rangeValue = unsafeDowncast(value, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetType(rangeValue) == .cfRange, AXValueGetValue(rangeValue, .cfRange, &range) else { return nil }
        return range
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
