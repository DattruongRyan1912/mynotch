import Foundation

/// What asking an element for one attribute came to.
nonisolated enum AttributeResult<Value: Equatable & Sendable>: Equatable, Sendable {
    case value(Value)
    /// The element has no such attribute, or no value for it.
    case missing
    /// The app did not answer in time (`kAXErrorCannotComplete`).
    case timedOut

    var found: Value? {
        if case .value(let value) = self { value } else { nil }
    }
}

/// The questions a passive read asks of the focused element, one attribute each. A protocol, so what is asked, in which
/// order and when asking stops can be tested with an element that records its calls and times out on demand.
protocol AccessibilityElementReading {
    func role() -> AttributeResult<String>
    func subrole() -> AttributeResult<String>
    /// The selected range, in UTF-16 units as Accessibility counts.
    func selectedRange() -> AttributeResult<NSRange>
    func selectedText() -> AttributeResult<String>
    /// Where `range` is on screen, in Accessibility coordinates.
    func bounds(of range: NSRange) -> AttributeResult<CGRect>
}

/// What one passive look at the focused element found.
nonisolated enum SelectionInspection: Equatable, Sendable {
    /// Nothing to show: nothing is selected, the field is a password field, or the app does not say.
    case none
    /// The selection is longer than `SelectionIgnoreRules.maxLength`; its text was not fetched.
    case tooLong
    /// The app did not answer in time, so asking again would stall again.
    case unresponsive
    case selected(text: String, bounds: CGRect?)
}

/// A look at the focused element for "Bôi đen là hiểu", in the fewest calls and the safest order. One element, one pass:
///
/// 1. Role and subrole, to refuse a password field before anything about it is asked. An answer that does not come is not
///    taken for "not a password field".
/// 2. The selected range, whose length says "nothing" or "too much" without fetching any text.
/// 3. The text, and, only for a selection worth showing, where it is.
///
/// It stops at the first call the app does not answer: the next would wait just as long. Each call is bounded by the
/// element's messaging timeout, so a hung app costs the main actor one timeout, not one per question.
enum PassiveSelectionReader {
    static func inspect(_ element: some AccessibilityElementReading, maxLength: Int) -> SelectionInspection {
        switch element.role() {
        case .timedOut: return .unresponsive
        case .value(let role): if SecureTextField.matches(role: role, subrole: nil) { return .none }
        case .missing: break
        }
        switch element.subrole() {
        case .timedOut: return .unresponsive
        case .value(let subrole): if SecureTextField.matches(role: nil, subrole: subrole) { return .none }
        case .missing: break
        }
        var range: NSRange?
        switch element.selectedRange() {
        case .timedOut: return .unresponsive
        case .value(let found): range = found
        case .missing: break
        }
        if let range, let reason = SelectionIgnoreRules.length(range.length) {
            return reason == .tooLong ? .tooLong : .none
        }
        switch element.selectedText() {
        case .timedOut: return .unresponsive
        case .missing: return .none
        case .value(let text):
            // Without a range there is nothing to ask the place of; a place that does not come is only a place missing.
            let bounds = range.flatMap { element.bounds(of: $0).found }
            return .selected(text: text, bounds: bounds)
        }
    }
}
