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

    func focusedApplication() -> FocusedApplication? { application }

    func readSelection(in application: FocusedApplication) -> SelectionRead {
        defer { reads += 1 }
        if unresponsiveReads.contains(reads) { return .unresponsive }
        return (reads < selections.count ? selections[reads] : nil).map(SelectionRead.text) ?? .empty
    }

    func isEnabled(_ attribute: String, in application: FocusedApplication) -> Bool { attributes.contains(attribute) }

    func enable(_ attribute: String, in application: FocusedApplication) {
        enabled.append(attribute)
        attributes.insert(attribute)
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
        #expect(await makeReader().selectedText() == "Xin chào")
        #expect(accessibility.reads == 1)
    }

    @Test func untrustedReadsNothing() async {
        accessibility.isTrusted = false
        accessibility.selections = ["Xin chào"]
        #expect(await makeReader().selectedText() == nil)
        #expect(accessibility.reads == 0)
    }

    @Test func noFocusedApplicationReadsNothing() async {
        accessibility.application = nil
        #expect(await makeReader().selectedText() == nil)
        #expect(accessibility.reads == 0)
    }

    @Test func myNotchItselfIsNotRead() async {
        accessibility.application = FocusedApplication(processID: getpid(), bundleID: "com.google.Chrome")
        accessibility.selections = ["Xin chào"]
        #expect(await makeReader().selectedText() == nil)
        #expect(accessibility.reads == 0)
    }

    @Test func emptySelectionIsNil() async {
        accessibility.selections = [""]
        #expect(await makeReader().selectedText() == nil)
        let blank = FakeAccessibility()
        blank.selections = [" \n\t"]
        #expect(await SelectionReader(accessibility: blank) { _ in }.selectedText() == nil)
    }

    @Test func chromiumRetrySucceedsOnTheThirdPoll() async {
        focus("com.google.Chrome")
        accessibility.selections = [nil, nil, "", "Hello"]
        #expect(await makeReader().selectedText() == "Hello")
        #expect(accessibility.enabled == ["AXEnhancedUserInterface"])
        #expect(pauses.durations == [.milliseconds(100), .milliseconds(100), .milliseconds(100)])
        #expect(accessibility.reads == 4)
    }

    @Test func electronAppsGetManualAccessibility() async {
        focus("com.tinyspeck.slackmacgap")
        accessibility.selections = [nil, "Hello"]
        #expect(await makeReader().selectedText() == "Hello")
        #expect(accessibility.enabled == ["AXManualAccessibility"])
    }

    @Test func retriesStopAfter600Milliseconds() async {
        focus("com.microsoft.VSCode")
        #expect(await makeReader().selectedText() == nil)
        #expect(pauses.durations.reduce(.zero, +) == .milliseconds(600))
        #expect(accessibility.reads == 7)
    }

    @Test func attributeAlreadyOnIsNotSetAgain() async {
        focus("com.google.Chrome")
        accessibility.attributes = ["AXEnhancedUserInterface"]
        accessibility.selections = [nil, "Hello"]
        #expect(await makeReader().selectedText() == "Hello")
        #expect(accessibility.enabled.isEmpty)
    }

    @Test func anAppEnabledEarlierIsNotWaitedForAgain() async {
        focus("com.google.Chrome")
        let reader = makeReader()
        #expect(await reader.selectedText() == nil)
        #expect(accessibility.reads == 7)

        #expect(await reader.selectedText() == nil)
        #expect(accessibility.reads == 8)
        #expect(pauses.durations.count == 6)
        #expect(accessibility.enabled == ["AXEnhancedUserInterface"])
    }

    @Test func unresponsiveAppIsNotRetried() async {
        focus("com.google.Chrome")
        accessibility.unresponsiveReads = [0]
        accessibility.selections = [nil, "Hello"]
        #expect(await makeReader().selectedText() == nil)
        #expect(accessibility.reads == 1)
        #expect(accessibility.enabled.isEmpty)
        #expect(pauses.durations.isEmpty)
    }

    @Test func appBecomingUnresponsiveStopsTheRetries() async {
        focus("com.google.Chrome")
        accessibility.unresponsiveReads = [1]
        accessibility.selections = [nil, nil, "Hello"]
        #expect(await makeReader().selectedText() == nil)
        #expect(accessibility.reads == 2)
        #expect(pauses.durations.count == 1)
    }

    @Test(arguments: ["com.apple.Safari", nil] as [String?])
    func otherAppsAreNotRetried(bundleID: String?) async {
        focus(bundleID)
        accessibility.selections = [nil, "Hello"]
        #expect(await makeReader().selectedText() == nil)
        #expect(accessibility.reads == 1)
        #expect(accessibility.enabled.isEmpty)
        #expect(pauses.durations.isEmpty)
    }

    @Test func chromiumAccessibilityCanBeTurnedOff() async {
        focus("com.google.Chrome")
        accessibility.selections = [nil, "Hello"]
        let reader = makeReader()
        reader.useChromiumAccessibility = false
        #expect(await reader.selectedText() == nil)
        #expect(accessibility.enabled.isEmpty)
        #expect(pauses.durations.isEmpty)
    }

    @Test func cancellationStopsRetrying() async {
        focus("com.google.Chrome")
        accessibility.selections = [nil, "Hello"]
        pauses.error = CancellationError()
        #expect(await makeReader().selectedText() == nil)
        #expect(accessibility.reads == 1)
        #expect(pauses.durations.count == 1)
    }
}
