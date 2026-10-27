import Foundation
import Testing
@testable import TranslationModule

final class FakeAccessibility: AccessibilityClient {
    var isTrusted = true
    var application: FocusedApplication? = FocusedApplication(processID: 42, bundleID: "com.apple.Safari")
    /// Returned by successive reads; reads past the end find no selection.
    var selections: [String?] = []
    /// Indices of the reads the app doesn't answer in time.
    var unresponsiveReads: Set<Int> = []
    /// Attributes that are true on the app element, including the ones `enable` set.
    var attributes: Set<String> = []
    private(set) var reads = 0
    /// Attributes `enable` set, in order.
    private(set) var enabled: [String] = []

    private(set) var focusedLookups = 0

    func focusedApplication() -> FocusedApplication? {
        focusedLookups += 1
        return application
    }

    /// The front app, which a passive read goes by; `application` when nil.
    var frontmost: FocusedApplication?

    func frontmostApplication() -> FocusedApplication? { frontmost ?? application }

    /// Apps that hold secure event input, as one does while a password field has the focus.
    var secureInputHolders: Set<pid_t> = []

    func isSecureInputHeld(by application: FocusedApplication) -> Bool { secureInputHolders.contains(application.processID) }

    /// What every read finds once `selections` is used up.
    var standing: String?
    /// The focused field is a password field: like the real client, nothing is read from it, its length and place included.
    var isSecureField = false
    /// What the selected range says about its length, in UTF-16 units; nil when the app does not say.
    var length: Int?
    /// Where the selection is, in Accessibility coordinates; nil when the app does not say.
    var bounds: CGRect?
    /// A passive read finds an app that does not answer in time.
    var hangs = false
    /// What the next passive looks find, in order, instead of what the rest of this fake says; used up one by one.
    var inspectionScript: [SelectionInspection] = []
    /// How many passive looks were taken, each of which is one round of Accessibility calls.
    private(set) var inspections = 0

    func readSelection(in application: FocusedApplication) -> SelectionRead {
        guard !isSecureField else { return .empty }
        defer { reads += 1 }
        if unresponsiveReads.contains(reads) { return .unresponsive }
        return (reads < selections.count ? selections[reads] : standing).map(SelectionRead.text) ?? .empty
    }

    func inspectSelection(in application: FocusedApplication) -> SelectionInspection {
        inspections += 1
        if !inspectionScript.isEmpty { return inspectionScript.removeFirst() }
        if hangs { return .unresponsive }
        if isSecureField { return .none }
        if let reason = SelectionIgnoreRules.length(length) { return reason == .tooLong ? .tooLong : .none }
        switch readSelection(in: application) {
        case .text(let text): return .selected(text: text, bounds: bounds)
        case .empty: return .none
        case .unresponsive: return .unresponsive
        }
    }

    func isEnabled(_ attribute: String, in application: FocusedApplication) -> Bool { attributes.contains(attribute) }

    /// Whether an app keeps the attribute that was set; some ignore it, and then it reads as off again.
    var enableSticks = true

    /// Whether an app accepts the attribute at all; some refuse it.
    var enableSucceeds = true

    @discardableResult
    func enable(_ attribute: String, in application: FocusedApplication) -> Bool {
        enabled.append(attribute)
        if enableSticks, enableSucceeds { attributes.insert(attribute) }
        return enableSucceeds
    }

    /// Whether the app takes a replacement.
    var replaces = true
    /// Texts written over the selection, in order.
    private(set) var replacements: [String] = []

    func replaceSelection(with text: String, in application: FocusedApplication) -> Bool {
        replacements.append(text)
        return replaces
    }
}

final class FakePauses {
    var durations: [Duration] = []
    var error: (any Error)?
}

@Suite struct SelectionReaderTests {
    let accessibility = FakeAccessibility()
    let pauses = FakePauses()

    func makeReader() -> SelectionReader {
        let pauses = pauses
        return SelectionReader(accessibility: accessibility) { duration in
            pauses.durations.append(duration)
            if let error = pauses.error { throw error }
        }
    }

    func focus(_ bundleID: String?) {
        accessibility.application = FocusedApplication(processID: 42, bundleID: bundleID)
    }

    @Test func readsTheSelection() async {
        accessibility.selections = ["Xin chào"]
        #expect(await makeReader().selection()?.text == "Xin chào")
        #expect(accessibility.reads == 1)
    }

    @Test func reportsTheAppTheSelectionIsIn() async {
        focus("com.apple.Safari")
        accessibility.selections = ["Xin chào"]
        let safari = FocusedApplication(processID: 42, bundleID: "com.apple.Safari")
        #expect(await makeReader().selection() == SelectionSource(text: "Xin chào", application: safari))
    }

    @Test func reportsTheAppAfterWaitingForItsTree() async {
        focus("com.google.Chrome")
        accessibility.selections = [nil, "Hello"]
        let chrome = FocusedApplication(processID: 42, bundleID: "com.google.Chrome")
        #expect(await makeReader().selection() == SelectionSource(text: "Hello", application: chrome))
    }

    @Test func untrustedReadsNothing() async {
        accessibility.isTrusted = false
        accessibility.selections = ["Xin chào"]
        #expect(await makeReader().selection() == nil)
        #expect(accessibility.reads == 0)
    }

    @Test func noFocusedApplicationReadsNothing() async {
        accessibility.application = nil
        #expect(await makeReader().selection() == nil)
        #expect(accessibility.reads == 0)
    }

    /// The system-wide element does not always say which app has the focus (it answers "cannot complete" while the app in
    /// front reads fine): the app in front is read then, as a passive read does.
    @Test func theFrontAppIsReadWhenTheFocusedOneIsNotKnown() async {
        accessibility.application = nil
        let textEdit = FocusedApplication(processID: 42, bundleID: "com.apple.TextEdit")
        accessibility.frontmost = textEdit
        accessibility.selections = ["frontmatter CYBEROS-03 và ingest"]
        #expect(await makeReader().selection() == SelectionSource(text: "frontmatter CYBEROS-03 và ingest", application: textEdit))
    }

    @Test func withMyNotchFocusedTheAppInFrontIsRead() async {
        accessibility.application = FocusedApplication(processID: getpid(), bundleID: "io.lucasvu.mynotch")
        let textEdit = FocusedApplication(processID: 42, bundleID: "com.apple.TextEdit")
        accessibility.frontmost = textEdit
        accessibility.selections = ["Xin chào"]
        #expect(await makeReader().selection() == SelectionSource(text: "Xin chào", application: textEdit))
    }

    @Test func myNotchInFrontIsNotRead() async {
        accessibility.application = nil
        accessibility.frontmost = FocusedApplication(processID: getpid(), bundleID: "io.lucasvu.mynotch")
        accessibility.selections = ["Xin chào"]
        #expect(await makeReader().selection() == nil)
        #expect(accessibility.reads == 0)
    }

    @Test func myNotchItselfIsNotRead() async {
        accessibility.application = FocusedApplication(processID: getpid(), bundleID: "com.google.Chrome")
        accessibility.selections = ["Xin chào"]
        #expect(await makeReader().selection() == nil)
        #expect(accessibility.reads == 0)
    }

    @Test func emptySelectionIsNil() async {
        accessibility.selections = [""]
        #expect(await makeReader().selection() == nil)
        let blank = FakeAccessibility()
        blank.selections = [" \n\t"]
        #expect(await SelectionReader(accessibility: blank) { _ in }.selection() == nil)
    }

    @Test func chromiumRetrySucceedsOnTheThirdPoll() async {
        focus("com.google.Chrome")
        accessibility.selections = [nil, nil, "", "Hello"]
        #expect(await makeReader().selection()?.text == "Hello")
        #expect(accessibility.enabled == ["AXEnhancedUserInterface"])
        #expect(pauses.durations == [.milliseconds(100), .milliseconds(100), .milliseconds(100)])
        #expect(accessibility.reads == 4)
    }

    @Test func electronAppsGetManualAccessibility() async {
        focus("com.tinyspeck.slackmacgap")
        accessibility.selections = [nil, "Hello"]
        #expect(await makeReader().selection()?.text == "Hello")
        #expect(accessibility.enabled == ["AXManualAccessibility"])
    }

    @Test func retriesStopAfter600Milliseconds() async {
        focus("com.microsoft.VSCode")
        #expect(await makeReader().selection() == nil)
        #expect(pauses.durations.reduce(.zero, +) == .milliseconds(600))
        #expect(accessibility.reads == 7)
    }

    @Test func attributeAlreadyOnIsNotSetAgain() async {
        focus("com.google.Chrome")
        accessibility.attributes = ["AXEnhancedUserInterface"]
        accessibility.selections = [nil, "Hello"]
        #expect(await makeReader().selection()?.text == "Hello")
        #expect(accessibility.enabled.isEmpty)
    }

    @Test func anAppEnabledEarlierIsNotWaitedForAgain() async {
        focus("com.google.Chrome")
        let reader = makeReader()
        #expect(await reader.selection() == nil)
        #expect(accessibility.reads == 7)

        #expect(await reader.selection() == nil)
        #expect(accessibility.reads == 8)
        #expect(pauses.durations.count == 6)
        #expect(accessibility.enabled == ["AXEnhancedUserInterface"])
    }

    @Test func unresponsiveAppIsNotRetried() async {
        focus("com.google.Chrome")
        accessibility.unresponsiveReads = [0]
        accessibility.selections = [nil, "Hello"]
        #expect(await makeReader().selection() == nil)
        #expect(accessibility.reads == 1)
        #expect(accessibility.enabled.isEmpty)
        #expect(pauses.durations.isEmpty)
    }

    @Test func appBecomingUnresponsiveStopsTheRetries() async {
        focus("com.google.Chrome")
        accessibility.unresponsiveReads = [1]
        accessibility.selections = [nil, nil, "Hello"]
        #expect(await makeReader().selection() == nil)
        #expect(accessibility.reads == 2)
        #expect(pauses.durations.count == 1)
    }

    @Test(arguments: ["com.apple.Safari", nil] as [String?])
    func otherAppsAreNotRetried(bundleID: String?) async {
        focus(bundleID)
        accessibility.selections = [nil, "Hello"]
        #expect(await makeReader().selection() == nil)
        #expect(accessibility.reads == 1)
        #expect(accessibility.enabled.isEmpty)
        #expect(pauses.durations.isEmpty)
    }

    @Test func chromiumAccessibilityCanBeTurnedOff() async {
        focus("com.google.Chrome")
        accessibility.selections = [nil, "Hello"]
        let reader = makeReader()
        reader.useChromiumAccessibility = false
        #expect(await reader.selection() == nil)
        #expect(accessibility.enabled.isEmpty)
        #expect(pauses.durations.isEmpty)
    }

    @Test func cancellationStopsRetrying() async {
        focus("com.google.Chrome")
        accessibility.selections = [nil, "Hello"]
        pauses.error = CancellationError()
        #expect(await makeReader().selection() == nil)
        #expect(accessibility.reads == 1)
        #expect(pauses.durations.count == 1)
    }
}
