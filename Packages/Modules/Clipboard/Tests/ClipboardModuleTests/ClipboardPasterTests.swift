import AppKit
import MyNotchTestSupport
import Testing
@testable import ClipboardModule

@Suite final class ClipboardPasterTests {
    static let content = ClipboardContent.richText(plain: "Xin chào", rtf: Data("{\\rtf1 Xin chào}".utf8))
    static let item = ClipboardItem(
        id: UUID(), content: content, contentHash: ClipboardContent.hash(of: content),
        copiedAt: .now, sourceBundleID: "com.apple.TextEdit", sourceAppName: "TextEdit"
    )
    static let imageURL = URL(fileURLWithPath: "/tmp/MyNotchTests/image.png")

    let pasteboard = FakePasteboard()
    let keystrokes = FakeKeystrokeSender()
    let scheduler = ManualScheduler()
    var trusted = true

    lazy var paster = ClipboardPaster(
        pasteboard: pasteboard, keystrokes: keystrokes, scheduler: scheduler, isTrusted: { [unowned self] in trusted }
    )

    @Test func copyWritesTheItemWithoutPasting() {
        let outcome = paster.perform(Self.item, imageURL: Self.imageURL, paste: false)
        scheduler.advance(by: .seconds(1))

        #expect(outcome == .copied)
        #expect(pasteboard.writes == [
            .init(content: Self.content, imageURL: Self.imageURL, plainTextOnly: false, sourceBundleID: "com.apple.TextEdit"),
        ])
        #expect(keystrokes.pasteCount == 0)
    }

    @Test func pasteWhenTrustedWritesFirstThenSendsOneCommandVAfterTheDelay() {
        let outcome = paster.perform(Self.item, imageURL: nil, paste: true)

        #expect(outcome == .pasted)
        #expect(pasteboard.writes.count == 1)
        scheduler.advance(by: .milliseconds(79))
        #expect(keystrokes.pasteCount == 0)
        scheduler.advance(by: .milliseconds(1))
        #expect(keystrokes.pasteCount == 1)
        scheduler.advance(by: .seconds(1))
        #expect(keystrokes.pasteCount == 1)
    }

    @Test func pasteWithoutAccessibilityOnlyCopies() {
        trusted = false
        let outcome = paster.perform(Self.item, imageURL: nil, paste: true)
        scheduler.advance(by: .seconds(1))

        #expect(outcome == .copiedNeedsPermission)
        #expect(pasteboard.writes.count == 1)
        #expect(keystrokes.pasteCount == 0)
    }

    @Test func plainTextOnlyReachesTheWrite() {
        paster.perform(Self.item, imageURL: nil, paste: false, plainTextOnly: true)

        #expect(pasteboard.writes == [
            .init(content: Self.content, imageURL: nil, plainTextOnly: true, sourceBundleID: "com.apple.TextEdit"),
        ])
    }

    @Test func aSecondPasteWithinTheDelaySendsOnlyOneCommandV() {
        paster.perform(Self.item, imageURL: nil, paste: true)
        scheduler.advance(by: .milliseconds(40))
        paster.perform(Self.item, imageURL: nil, paste: true)

        scheduler.advance(by: .milliseconds(79))
        #expect(keystrokes.pasteCount == 0)
        scheduler.advance(by: .milliseconds(1))
        #expect(keystrokes.pasteCount == 1)
        scheduler.advance(by: .seconds(1))
        #expect(keystrokes.pasteCount == 1)
        #expect(pasteboard.writes.count == 2)
    }

    /// The copy replaced the pasteboard, so the earlier ⌘V would paste the wrong item.
    @Test func aCopyWithinTheDelayCancelsThePendingPaste() {
        paster.perform(Self.item, imageURL: nil, paste: true)
        scheduler.advance(by: .milliseconds(40))
        paster.perform(Self.item, imageURL: nil, paste: false)
        scheduler.advance(by: .seconds(1))

        #expect(keystrokes.pasteCount == 0)
    }

    // MARK: Waiting for the keyboard

    /// The floating panel hands the keyboard back between the write and the key press, and says whether it worked.
    @Test func theKeyboardCheckRunsAfterTheWriteAndBeforeCommandVIsScheduled() {
        var seen: [(writes: Int, pending: Int)] = []
        let outcome = paster.perform(Self.item, imageURL: nil, paste: true) { [unowned self] in
            seen.append((pasteboard.writes.count, scheduler.pendingCount))
            return true
        }

        #expect(outcome == .pasted)
        #expect(seen.count == 1)
        #expect(seen.first?.writes == 1)
        #expect(seen.first?.pending == 0)
        scheduler.advance(by: .milliseconds(80))
        #expect(keystrokes.pasteCount == 1)
    }

    @Test func aKeyboardThatIsNotBackCopiesWithoutPasting() {
        let outcome = paster.perform(Self.item, imageURL: nil, paste: true) { false }
        scheduler.advance(by: .seconds(1))

        #expect(outcome == .copied)
        #expect(pasteboard.writes.count == 1)
        #expect(keystrokes.pasteCount == 0)
        #expect(scheduler.pendingCount == 0)
    }

    @Test func aRefusedPasteAlsoCancelsACommandVStillWaiting() {
        paster.perform(Self.item, imageURL: nil, paste: true)
        scheduler.advance(by: .milliseconds(40))
        let outcome = paster.perform(Self.item, imageURL: nil, paste: true) { false }
        scheduler.advance(by: .seconds(1))

        #expect(outcome == .copied)
        #expect(keystrokes.pasteCount == 0)
    }

    @Test func theKeyboardCheckIsNotAskedWhenNothingWouldBePasted() {
        var asked = 0
        paster.perform(Self.item, imageURL: nil, paste: false) { asked += 1; return true }
        trusted = false
        let outcome = paster.perform(Self.item, imageURL: nil, paste: true) { asked += 1; return true }

        #expect(outcome == .copiedNeedsPermission)
        #expect(asked == 0)
    }

    /// Uses a private named pasteboard so the real write path decides; the system pasteboard is never touched.
    @Test func anUnreadableImageFailsWithoutTouchingThePasteboardOrPasting() {
        let named = NSPasteboard(name: .init("MyNotchTests.\(UUID().uuidString)"))
        defer { named.releaseGlobally() }
        named.clearContents()
        named.setString("keep me", forType: .string)
        let changeCount = named.changeCount
        let image = ClipboardContent.image(ClipboardImage(fileName: "missing.png", pixelWidth: 1, pixelHeight: 1, byteCount: 4))
        let item = ClipboardItem(
            id: UUID(), content: image, contentHash: ClipboardContent.hash(of: image),
            copiedAt: .now, sourceBundleID: nil, sourceAppName: nil
        )
        let paster = ClipboardPaster(
            pasteboard: SystemPasteboard(pasteboard: named), keystrokes: keystrokes, scheduler: scheduler, isTrusted: { true }
        )

        let outcome = paster.perform(item, imageURL: URL(fileURLWithPath: "/tmp/MyNotchTests/missing.png"), paste: true)
        scheduler.advance(by: .seconds(1))

        #expect(outcome == .failed)
        #expect(named.changeCount == changeCount)
        #expect(named.string(forType: .string) == "keep me")
        #expect(keystrokes.pasteCount == 0)
        #expect(scheduler.pendingCount == 0)
    }
}
