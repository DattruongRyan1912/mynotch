import AppKit
import Foundation
import Testing
@testable import TranslationModule

final class FakeApplications: ApplicationActivating {
    /// False when the app has quit since its selection was read.
    var exists = true
    /// How many `isFrontmost` questions are answered "no" before the app is in front; nil means never.
    var checksBeforeFront: Int? = 0
    private(set) var activated: [FocusedApplication] = []
    private var checks = 0

    func activate(_ application: FocusedApplication) -> Bool {
        activated.append(application)
        return exists
    }

    func isFrontmost(_ application: FocusedApplication) -> Bool {
        defer { checks += 1 }
        return checksBeforeFront.map { checks >= $0 } ?? false
    }
}

/// Counts ⌘V instead of posting it; `onSend` sees the world at the moment the app would read the pasteboard.
final class FakeKeystroke: PasteKeystroke {
    private(set) var sent = 0
    var onSend: (() -> Void)?

    func send() {
        sent += 1
        onSend?()
    }
}

/// Returns at once, noting each wait; `during` runs as time passes and `failure` cuts every wait short.
final class ReplacerPauses {
    private(set) var durations: [Duration] = []
    var during: (() -> Void)?
    var failure: (any Error)?

    func pause(_ duration: Duration) throws {
        durations.append(duration)
        during?()
        if let failure { throw failure }
    }
}

extension NSPasteboard {
    /// Every item as type → data, so a test sees exactly what an app pasting now would find.
    var snapshot: [[String: Data]] {
        (pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type.rawValue, $0) } })
        }
    }
}

@Suite struct SelectionReplacerTests {
    static let marker = "io.lucasvu.mynotch.clipboard"
    static let concealed = "org.nspasteboard.ConcealedType"
    let source = FocusedApplication(processID: 42, bundleID: "com.apple.Safari")
    let accessibility = FakeAccessibility()
    let applications = FakeApplications()
    let keystroke = FakeKeystroke()
    let pauses = ReplacerPauses()
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("MyNotchTests.\(UUID().uuidString)"))

    init() {
        accessibility.selections = ["Hello"]
    }

    func makeReplacer() -> SelectionReplacer {
        SelectionReplacer(
            accessibility: accessibility, applications: applications, keystroke: keystroke, pasteboard: pasteboard
        ) { [pauses] duration in try pauses.pause(duration) }
    }

    func replace(_ text: String = "Xin chào") async -> ReplaceOutcome {
        await makeReplacer().replace(text, expecting: "Hello", in: source)
    }

    /// The user's clipboard: rich text from one app, a secret from a password manager, a second item.
    func fillPasteboard() {
        let first = NSPasteboardItem()
        first.setString("mine", forType: .string)
        first.setData(Data("{\\rtf1 mine}".utf8), forType: .rtf)
        first.setData(Data(), forType: NSPasteboard.PasteboardType(Self.concealed))
        let second = NSPasteboardItem()
        second.setString("second", forType: .string)
        pasteboard.clearContents()
        pasteboard.writeObjects([first, second])
    }

    // MARK: Accessibility path

    @Test func replacesThroughAccessibilityWithoutTouchingThePasteboard() async {
        fillPasteboard()
        let before = pasteboard.snapshot
        let changes = pasteboard.changeCount
        #expect(await replace() == .replaced)
        #expect(accessibility.replacements == ["Xin chào"])
        #expect(applications.activated == [source])
        #expect(keystroke.sent == 0)
        #expect(pasteboard.snapshot == before)
        #expect(pasteboard.changeCount == changes)
        #expect(pauses.durations.isEmpty)
    }

    @Test func waitsForTheAppToComeToTheFront() async {
        applications.checksBeforeFront = 3
        #expect(await replace() == .replaced)
        #expect(pauses.durations == Array(repeating: .milliseconds(50), count: 3))
        #expect(accessibility.replacements == ["Xin chào"])
    }

    @Test func anAppThatNeverComesToTheFrontIsLeftAlone() async {
        fillPasteboard()
        let before = pasteboard.snapshot
        applications.checksBeforeFront = nil
        #expect(await replace() == .failed)
        #expect(pauses.durations == Array(repeating: .milliseconds(50), count: 10))
        #expect(accessibility.replacements.isEmpty)
        #expect(keystroke.sent == 0)
        #expect(pasteboard.snapshot == before)
    }

    @Test func anAppThatQuitIsReportedAsAFailure() async {
        applications.exists = false
        #expect(await replace() == .failed)
        #expect(accessibility.replacements.isEmpty)
        #expect(keystroke.sent == 0)
        #expect(pauses.durations.isEmpty)
    }

    @Test func aCancelledReplaceChangesNothing() async {
        fillPasteboard()
        let before = pasteboard.snapshot
        accessibility.replaces = false
        let replacer = makeReplacer()
        let task = Task { await replacer.replace("Xin chào", expecting: "Hello", in: source) }
        task.cancel()
        #expect(await task.value == .failed)
        #expect(accessibility.replacements.isEmpty)
        #expect(keystroke.sent == 0)
        #expect(pasteboard.snapshot == before)
    }

    @Test func cancellationWhileWaitingForTheFrontEndsTheReplace() async {
        applications.checksBeforeFront = 3
        pauses.failure = CancellationError()
        #expect(await replace() == .failed)
        #expect(accessibility.replacements.isEmpty)
        #expect(keystroke.sent == 0)
    }

    // MARK: Permission and the selection

    @Test func withoutAccessibilityNothingHappens() async {
        fillPasteboard()
        let before = pasteboard.snapshot
        accessibility.isTrusted = false
        #expect(await replace() == .needsAccessibility)
        #expect(applications.activated.isEmpty)
        #expect(accessibility.reads == 0)
        #expect(accessibility.replacements.isEmpty)
        #expect(keystroke.sent == 0)
        #expect(pasteboard.snapshot == before)
    }

    @Test func aSelectionThatChangedIsNeverReplaced() async {
        fillPasteboard()
        let before = pasteboard.snapshot
        accessibility.selections = ["Something else the user selected since"]
        #expect(await replace() == .selectionChanged)
        // The other app's focus is not taken for a replacement that will not happen.
        #expect(applications.activated.isEmpty)
        #expect(accessibility.replacements.isEmpty)
        #expect(keystroke.sent == 0)
        #expect(pasteboard.snapshot == before)
    }

    @Test func aClearedSelectionIsNeverReplaced() async {
        accessibility.selections = []
        #expect(await replace() == .selectionChanged)
        #expect(accessibility.replacements.isEmpty)
        #expect(keystroke.sent == 0)
    }

    @Test func anAppThatDoesNotAnswerStillGetsTheReplacement() async {
        accessibility.unresponsiveReads = [0]
        #expect(await replace() == .replaced)
        #expect(accessibility.replacements == ["Xin chào"])
    }

    // MARK: Paste fallback

    @Test func fallsBackToPastingWhenAccessibilityRefuses() async {
        fillPasteboard()
        accessibility.replaces = false
        var seen: [[String: Data]] = []
        keystroke.onSend = { seen = pasteboard.snapshot }
        #expect(await replace() == .pasted)
        #expect(accessibility.replacements == ["Xin chào"])
        #expect(keystroke.sent == 1)
        // What the app reads when ⌘V arrives: the translation alone, tagged as MyNotch's own write.
        #expect(seen.count == 1)
        #expect(seen.first?[NSPasteboard.PasteboardType.string.rawValue] == Data("Xin chào".utf8))
        #expect(seen.first?[Self.marker] != nil)
        #expect(seen.first?[Self.concealed] == nil)
    }

    @Test func ourOwnWriteUsesTheTypeClipboardHistoryIgnores() {
        // Must stay equal to ClipboardClassifier.ownWriteType in the Clipboard module.
        #expect(SelectionReplacer.ownWriteType.rawValue == "io.lucasvu.mynotch.clipboard")
    }

    @Test func putsTheUsersClipboardBackWithEveryItemAndType() async {
        fillPasteboard()
        let before = pasteboard.snapshot
        accessibility.replaces = false
        #expect(await replace() == .pasted)
        var after = pasteboard.snapshot
        #expect(after.count == 2)
        // Restoring is MyNotch's write too, so Clipboard history does not record the old item a second time.
        #expect(after[0][Self.marker] != nil)
        after[0][Self.marker] = nil
        #expect(after == before)
        #expect(after[0][Self.concealed] != nil)
    }

    @Test func restoresOnlyAfterHalfASecond() async {
        fillPasteboard()
        accessibility.replaces = false
        var duringWait: [[String: Data]] = []
        pauses.during = { duringWait = pasteboard.snapshot }
        #expect(await replace() == .pasted)
        #expect(pauses.durations == [.milliseconds(500)])
        // Still the translation while the app reads it.
        #expect(duringWait.count == 1)
        #expect(duringWait.first?[NSPasteboard.PasteboardType.string.rawValue] == Data("Xin chào".utf8))
        #expect(pasteboard.snapshot.count == 2)
    }

    @Test func restoresEvenWhenTheWaitIsCutShort() async {
        fillPasteboard()
        accessibility.replaces = false
        pauses.failure = CancellationError()
        #expect(await replace() == .pasted)
        #expect(pasteboard.snapshot.count == 2)
        #expect(pasteboard.pasteboardItems?.first?.string(forType: .string) == "mine")
    }

    @Test func leavesWhatWasCopiedDuringTheWait() async {
        fillPasteboard()
        accessibility.replaces = false
        pauses.during = {
            pasteboard.clearContents()
            pasteboard.setString("copied meanwhile", forType: .string)
        }
        #expect(await replace() == .pasted)
        #expect(pasteboard.string(forType: .string) == "copied meanwhile")
        #expect(pasteboard.snapshot.count == 1)
    }

    @Test func anEmptyClipboardIsEmptyAgain() async {
        pasteboard.clearContents()
        accessibility.replaces = false
        #expect(await replace() == .pasted)
        #expect((pasteboard.pasteboardItems ?? []).isEmpty)
    }
}

@Suite struct SelectionReplacementTests {
    @Test func aChangedSelectionMeansTheAppTookTheText() {
        #expect(SelectionReplacement.took("Xin chào", before: "Hello", after: ""))
        #expect(SelectionReplacement.took("Xin chào", before: "Hello", after: "Xin chào"))
    }

    @Test func anUnchangedSelectionMeansTheAppIgnoredIt() {
        #expect(!SelectionReplacement.took("Xin chào", before: "Hello", after: "Hello"))
    }

    @Test func replacingATextWithItselfCannotBeTold() {
        #expect(SelectionReplacement.took("Hello", before: "Hello", after: "Hello"))
    }

    @Test func anUnreadableSelectionTrustsTheWrite() {
        #expect(SelectionReplacement.took("Xin chào", before: nil, after: nil))
        #expect(SelectionReplacement.took("Xin chào", before: "Hello", after: nil))
        #expect(SelectionReplacement.took("Xin chào", before: nil, after: "Hello"))
    }
}
