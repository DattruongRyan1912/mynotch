import Foundation
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
        #expect(pasteboard.writes == [.init(content: Self.content, imageURL: Self.imageURL, plainTextOnly: false)])
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

        #expect(pasteboard.writes == [.init(content: Self.content, imageURL: nil, plainTextOnly: true)])
    }
}
