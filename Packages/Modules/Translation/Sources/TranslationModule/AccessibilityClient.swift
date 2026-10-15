import AppKit
import ApplicationServices
import Carbon.HIToolbox

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
    /// The app with keyboard focus, from the system-wide element: an Accessibility call that waits for the system.
    func focusedApplication() -> FocusedApplication?
    /// The front app, which needs no Accessibility call at all; what a passive read goes by.
    func frontmostApplication() -> FocusedApplication?
    /// Whether the app holds secure event input, which an app turns on while a password field has the focus (and Terminal's
    /// Secure Keyboard Entry does always). Held by another process, it says nothing about this app.
    func isSecureInputHeld(by application: FocusedApplication) -> Bool
    /// The selected text of the focused element. Never the text of a password field: that reads as no selection.
    func readSelection(in application: FocusedApplication) -> SelectionRead
    /// One passive look at the focused element's selection, with a short timeout: its text, how long it is and where it is,
    /// from one element, stopping at the first call the app does not answer. Never anything from a password field.
    func inspectSelection(in application: FocusedApplication) -> SelectionInspection
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
    /// A passive read happens on every selection the user makes, on the main actor, so it waits a hung app much less than
    /// the shortcut's read does, and stops at the first call that is not answered.
    static let passiveTimeout: Float = 0.1

    var isTrusted: Bool { AXIsProcessTrusted() }

    func focusedApplication() -> FocusedApplication? {
        guard let app = Self.element(Self.copyValue(kAXFocusedApplicationAttribute, of: AXUIElementCreateSystemWide()).value) else {
            return nil
        }
        var processID: pid_t = 0
        guard AXUIElementGetPid(app, &processID) == .success else { return nil }
        return FocusedApplication(processID: processID, bundleID: NSRunningApplication(processIdentifier: processID)?.bundleIdentifier)
    }

    func frontmostApplication() -> FocusedApplication? {
        NSWorkspace.shared.frontmostApplication.map { FocusedApplication(processID: $0.processIdentifier, bundleID: $0.bundleIdentifier) }
    }

    func isSecureInputHeld(by application: FocusedApplication) -> Bool {
        guard IsSecureEventInputEnabled(), let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              let owner = session["kCGSSessionSecureInputPID"] as? Int else { return false }
        return owner == Int(application.processID)
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

    func inspectSelection(in application: FocusedApplication) -> SelectionInspection {
        let focused = Self.copyValue(kAXFocusedUIElementAttribute, of: Self.element(for: application, timeout: Self.passiveTimeout))
        guard let element = Self.element(focused.value) else { return focused.error == .cannotComplete ? .unresponsive : .none }
        AXUIElementSetMessagingTimeout(element, Self.passiveTimeout)
        return PassiveSelectionReader.inspect(SystemAXElement(element: element), maxLength: SelectionIgnoreRules.maxLength)
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

    private static func isSecure(_ element: AXUIElement) -> Bool {
        SecureTextField.matches(
            role: copyValue(kAXRoleAttribute, of: element).value as? String,
            subrole: copyValue(kAXSubroleAttribute, of: element).value as? String
        )
    }

    private static func element(for application: FocusedApplication, timeout: Float = timeout) -> AXUIElement {
        let element = AXUIElementCreateApplication(application.processID)
        AXUIElementSetMessagingTimeout(element, timeout)
        return element
    }

    fileprivate static func copyValue(_ attribute: String, of element: AXUIElement) -> (error: AXError, value: CFTypeRef?) {
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

/// A real element answering a passive read's questions. A call the app does not answer in time is `.timedOut`; any other
/// failure, such as an attribute the element does not have, is `.missing`.
private struct SystemAXElement: AccessibilityElementReading {
    let element: AXUIElement

    func role() -> AttributeResult<String> { string(kAXRoleAttribute) }
    func subrole() -> AttributeResult<String> { string(kAXSubroleAttribute) }
    func selectedText() -> AttributeResult<String> { string(kAXSelectedTextAttribute) }

    func selectedRange() -> AttributeResult<NSRange> {
        let (error, value) = SystemAccessibilityClient.copyValue(kAXSelectedTextRangeAttribute, of: element)
        guard error == .success else { return Self.failure(error) }
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return .missing }
        let rangeValue = unsafeDowncast(value, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetType(rangeValue) == .cfRange, AXValueGetValue(rangeValue, .cfRange, &range) else { return .missing }
        return .value(NSRange(location: range.location, length: range.length))
    }

    func bounds(of range: NSRange) -> AttributeResult<CGRect> {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let parameter = AXValueCreate(.cfRange, &cfRange) else { return .missing }
        var result: CFTypeRef?
        let error = AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, parameter, &result)
        guard error == .success else { return Self.failure(error) }
        guard let result, CFGetTypeID(result) == AXValueGetTypeID() else { return .missing }
        let value = unsafeDowncast(result, to: AXValue.self)
        var bounds = CGRect.zero
        guard AXValueGetType(value) == .cgRect, AXValueGetValue(value, .cgRect, &bounds) else { return .missing }
        return .value(bounds)
    }

    private func string(_ attribute: String) -> AttributeResult<String> {
        let (error, value) = SystemAccessibilityClient.copyValue(attribute, of: element)
        guard error == .success else { return Self.failure(error) }
        return (value as? String).map(AttributeResult.value) ?? .missing
    }

    private static func failure<Value>(_ error: AXError) -> AttributeResult<Value> {
        error == .cannotComplete ? .timedOut : .missing
    }
}
