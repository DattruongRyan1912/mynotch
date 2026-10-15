import AppKit
import Foundation
import Testing
@testable import ClipboardModule

/// Code in the module: classified when it is copied, kept with the history, and never pasted as rich text unasked.
extension ClipboardModuleTests {
    static let swiftCode = "let total = items.reduce(0) { $0 + $1.price }\nprint(total)"

    func copyRichText(_ text: String) {
        copy(PasteboardSnapshot(types: ["public.utf8-plain-text", "public.rtf"], string: text, rtf: Data("{\\rtf1 x}".utf8)))
    }

    @Test func aCopyIsClassifiedWhenItIsRecordedAndKeptOnDisk() async throws {
        await start()
        copy(Self.swiftCode)
        copy("Hôm nay trời đẹp quá.")
        copy(PasteboardSnapshot(types: ["public.url"], url: URL(string: "https://example.com")))

        #expect(items.map(\.codeDetection) == [nil, .notCode, .code(.swift)])
        await module.store?.flush()
        #expect(makeStore().load().items.map(\.codeDetection) == [nil, .notCode, .code(.swift)])
    }

    @Test func richTextThatIsCodeIsClassifiedByItsPlainText() async throws {
        await start()
        copyRichText("SELECT id FROM users;")
        #expect(items.first?.codeDetection == .code(.sql))
    }

    @Test func codeIsPastedAsPlainTextEvenWhenItWasCopiedWithFormatting() async throws {
        await start()
        copyRichText("SELECT id FROM users;")
        let item = try #require(items.first)

        module.activate(item)
        module.paste(item)
        module.copy(item)
        harness.scheduler.advance(by: .milliseconds(80))

        #expect(pasteboard.writes.map(\.plainTextOnly) == [true, true, true])
    }

    @Test func richTextThatIsNotCodeKeepsItsFormattingByDefault() async throws {
        await start()
        copyRichText("Xin chào")
        let item = try #require(items.first)

        module.paste(item)
        harness.scheduler.advance(by: .milliseconds(80))
        #expect(pasteboard.writes.map(\.plainTextOnly) == [false])
    }

    @Test func pastingAsPlainTextDropsTheFormattingAndStillPastes() async throws {
        await start()
        copyRichText("Xin chào")
        let item = try #require(items.first)

        module.paste(item, plainText: true)
        harness.scheduler.advance(by: .milliseconds(80))

        #expect(pasteboard.writes.map(\.plainTextOnly) == [true])
        #expect(keystrokes.pasteCount == 1)
    }

    @Test func aPlainTextPasteWithoutPermissionOnlyCopies() async throws {
        system.trusted = false
        await start()
        copyRichText("Xin chào")
        let item = try #require(items.first)

        let outcome = module.paste(item, plainText: true)

        #expect(outcome == .copiedNeedsPermission)
        #expect(pasteboard.writes.map(\.plainTextOnly) == [true])
        #expect(keystrokes.pasteCount == 0)
    }

    // MARK: Items from before code detection

    @Test func startClassifiesTheTextsSavedBeforeDetectionAndSavesThem() async throws {
        func legacy(_ content: ClipboardContent) -> ClipboardItem {
            ClipboardItem(
                id: UUID(), content: content, contentHash: ClipboardContent.hash(of: content), copiedAt: system.now,
                sourceBundleID: nil, sourceAppName: nil
            )
        }
        let code = legacy(.text(Self.swiftCode))
        let prose = legacy(.text("Xin chào"))
        let link = legacy(.link(URL(string: "https://example.com")!))
        await persist(ClipboardHistory(items: [code, prose, link]))

        await start()

        #expect(items.map(\.codeDetection) == [.code(.swift), .notCode, nil])
        #expect(items.map(\.id) == [code.id, prose.id, link.id])
        await module.store?.flush()
        #expect(makeStore().load().items.map(\.codeDetection) == [.code(.swift), .notCode, nil])
    }
}

@Suite struct ClipboardCardMenuCodeTests {
    func item(_ content: ClipboardContent) -> ClipboardItem {
        ClipboardItem(
            id: UUID(), content: content, contentHash: ClipboardContent.hash(of: content), copiedAt: .now,
            sourceBundleID: nil, sourceAppName: nil, codeDetection: ClipboardCodeDetector.detect(content)
        )
    }

    @Test func plainTextPasteIsOfferedForRichTextAndForCode() {
        let rtf = Data("{\\rtf1 x}".utf8)
        #expect(ClipboardCardMenu.offersPlainTextPaste(for: item(.richText(plain: "Xin chào", rtf: rtf))))
        #expect(ClipboardCardMenu.offersPlainTextPaste(for: item(.richText(plain: "SELECT id FROM users;", rtf: rtf))))
        #expect(ClipboardCardMenu.offersPlainTextPaste(for: item(.text("SELECT id FROM users;"))))
    }

    @Test func plainTextPasteIsNotOfferedWhereItChangesNothing() {
        #expect(!ClipboardCardMenu.offersPlainTextPaste(for: item(.text("Xin chào"))))
        #expect(!ClipboardCardMenu.offersPlainTextPaste(for: item(.link(URL(string: "https://example.com")!))))
        #expect(!ClipboardCardMenu.offersPlainTextPaste(for: item(.color(hex: "#FF8800"))))
        #expect(!ClipboardCardMenu.offersPlainTextPaste(for: item(.files([URL(fileURLWithPath: "/tmp/a")]))))
    }
}
