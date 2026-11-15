import Foundation
import Testing
@testable import TranslationModule

/// One element's attributes, answered as a test says and recorded in order, so what a passive read asks for, and when it
/// stops asking, can be checked without Accessibility.
final class FakeAXElement: AccessibilityElementReading {
    var roleResult: AttributeResult<String> = .value("AXTextArea")
    var subroleResult: AttributeResult<String> = .missing
    var rangeResult: AttributeResult<NSRange> = .value(NSRange(location: 4, length: 5))
    var textResult: AttributeResult<String> = .value("hello")
    var boundsResult: AttributeResult<CGRect> = .value(CGRect(x: 10, y: 20, width: 30, height: 15))
    private(set) var calls: [String] = []

    func role() -> AttributeResult<String> {
        calls.append("role")
        return roleResult
    }

    func subrole() -> AttributeResult<String> {
        calls.append("subrole")
        return subroleResult
    }

    func selectedRange() -> AttributeResult<NSRange> {
        calls.append("range")
        return rangeResult
    }

    func selectedText() -> AttributeResult<String> {
        calls.append("text")
        return textResult
    }

    func bounds(of range: NSRange) -> AttributeResult<CGRect> {
        calls.append("bounds")
        return boundsResult
    }
}

/// The order of a passive read of the focused element, and where it stops.
@Suite struct PassiveSelectionReaderTests {
    let element = FakeAXElement()

    func inspect() -> SelectionInspection {
        PassiveSelectionReader.inspect(element, maxLength: SelectionIgnoreRules.maxLength)
    }

    @Test func readsTheTextAndWhereItIsFromTheOneElement() {
        #expect(inspect() == .selected(text: "hello", bounds: CGRect(x: 10, y: 20, width: 30, height: 15)))
        #expect(element.calls == ["role", "subrole", "range", "text", "bounds"])
    }

    // MARK: password fields

    @Test func aPasswordFieldByRoleIsNotLookedIntoAnyFurther() {
        element.roleResult = .value("AXSecureTextField")
        #expect(inspect() == .none)
        #expect(element.calls == ["role"])
    }

    @Test func aPasswordFieldBySubroleIsNotLookedIntoAnyFurther() {
        element.roleResult = .value("AXTextField")
        element.subroleResult = .value("AXSecureTextField")
        #expect(inspect() == .none)
        #expect(element.calls == ["role", "subrole"])
    }

    @Test func aFieldWithNoSubroleIsAnOrdinaryField() {
        element.subroleResult = .missing
        element.roleResult = .missing
        #expect(inspect() == .selected(text: "hello", bounds: CGRect(x: 10, y: 20, width: 30, height: 15)))
    }

    @Test func aFieldThatCannotSayWhetherItIsAPasswordIsNotRead() {
        // Failing open here would read a password field whenever its app is slow to answer.
        element.roleResult = .timedOut
        #expect(inspect() == .unresponsive)
        #expect(element.calls == ["role"])
        let other = FakeAXElement()
        other.subroleResult = .timedOut
        #expect(PassiveSelectionReader.inspect(other, maxLength: 2_000) == .unresponsive)
        #expect(other.calls == ["role", "subrole"])
    }

    // MARK: stopping at the first timeout

    @Test(arguments: ["role", "subrole", "range", "text"])
    func stopsAtTheFirstAnswerThatNeverComes(step: String) {
        switch step {
        case "role": element.roleResult = .timedOut
        case "subrole": element.subroleResult = .timedOut
        case "range": element.rangeResult = .timedOut
        default: element.textResult = .timedOut
        }
        #expect(inspect() == .unresponsive)
        // Nothing was asked after it.
        let steps = ["role", "subrole", "range", "text"]
        #expect(element.calls == Array(steps[...steps.firstIndex(of: step)!]))
    }

    @Test func anAppThatNeverAnswersCostsOneTimeoutPerGesture() {
        let hung = FakeAXElement()
        hung.roleResult = .timedOut
        hung.subroleResult = .timedOut
        hung.rangeResult = .timedOut
        hung.textResult = .timedOut
        hung.boundsResult = .timedOut
        #expect(PassiveSelectionReader.inspect(hung, maxLength: 2_000) == .unresponsive)
        // One call, so at most one timeout of the main actor's time: well under a third of a second.
        #expect(hung.calls.count == 1)
        #expect(Double(hung.calls.count) * Double(SystemAccessibilityClient.passiveTimeout) < 0.3)
        #expect(SystemAccessibilityClient.passiveTimeout <= 0.1)
    }

    // MARK: length, before the text

    @Test func aRangeOfNothingIsNothingAndTheTextIsNotAskedFor() {
        element.rangeResult = .value(NSRange(location: 3, length: 0))
        #expect(inspect() == .none)
        #expect(!element.calls.contains("text"))
    }

    @Test func aRangeTooLongIsNeverFetched() {
        element.rangeResult = .value(NSRange(location: 0, length: 2_001))
        #expect(inspect() == .tooLong)
        #expect(!element.calls.contains("text"))
        #expect(!element.calls.contains("bounds"))
    }

    @Test func aRangeOfTwoThousandIsFine() {
        element.rangeResult = .value(NSRange(location: 0, length: 2_000))
        #expect(inspect() != .tooLong)
        #expect(element.calls.contains("text"))
    }

    @Test func anAppThatDoesNotSayHowLongTheRangeIsIsAskedForTheTextAnyway() {
        element.rangeResult = .missing
        #expect(inspect() == .selected(text: "hello", bounds: nil))
        // Without a range there is nothing to ask the bounds of.
        #expect(!element.calls.contains("bounds"))
    }

    @Test func noTextIsNothing() {
        element.textResult = .missing
        #expect(inspect() == .none)
    }

    @Test func boundsThatAreMissingOrTimedOutStillGiveTheText() {
        element.boundsResult = .missing
        #expect(inspect() == .selected(text: "hello", bounds: nil))
        element.boundsResult = .timedOut
        #expect(inspect() == .selected(text: "hello", bounds: nil))
    }
}
