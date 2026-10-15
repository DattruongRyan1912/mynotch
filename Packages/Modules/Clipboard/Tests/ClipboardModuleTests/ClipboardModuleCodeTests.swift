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

    @Test func codeCopiedAsPlainTextIsPastedAsPlainText() async throws {
        await start()
        copy(Self.swiftCode)
        let item = try #require(items.first)

        module.activate(item)
        module.paste(item)
        module.copy(item)

        // A plain text has no formatting to leave out, so nothing more is asked of the pasteboard.
        #expect(pasteboard.writes.map(\.content) == [item.content, item.content, item.content])
        #expect(pasteboard.writes.allSatisfy { $0.content.plainText == Self.swiftCode })
    }

    @Test func richTextThatLooksLikeCodeKeepsItsFormattingByDefault() async throws {
        await start()
        copyRichText("SELECT id FROM users;")
        let item = try #require(items.first)
        #expect(item.isCode)

        module.activate(item)
        module.paste(item)
        module.copy(item)
        harness.scheduler.advance(by: .milliseconds(80))

        // Nothing is dropped from what was copied: a mistake of the detector must not cost anyone their formatting.
        #expect(pasteboard.writes.map(\.plainTextOnly) == [false, false, false])
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

    func legacy(_ content: ClipboardContent) -> ClipboardItem {
        ClipboardItem(
            id: UUID(), content: content, contentHash: ClipboardContent.hash(of: content), copiedAt: system.now,
            sourceBundleID: nil, sourceAppName: nil
        )
    }

    /// Runs the classification one step at a time, as the scheduler lets it, until every text has an answer.
    func classifyEverything() async -> Int {
        var steps = 0
        while items.contains(where: { $0.codeDetection == nil && $0.content.kind == .text }), steps < 200 {
            harness.scheduler.advance(by: ClipboardModule.classifyStepDelay)
            await module.classification?.value
            steps += 1
        }
        return steps
    }

    @Test func startDoesNotClassifyOldTextsAndTheStepsThatDoSoStayWithinTheirBudget() async throws {
        let bigCode = Self.swiftCode.split(separator: "\n")[0] + "\n" + String(repeating: "print(\"total\", 1)\n", count: 300)
        let big = (0..<200).map { legacy(.text(bigCode + "print(\"\($0)\", 2)")) }
        let short = (0..<3_000).map { legacy(.text("ghi chú \($0)")) }
        let link = legacy(.link(URL(string: "https://example.com")!))
        await persist(ClipboardHistory(items: big + [link] + short))
        // The default limit of 500 would drop most of them when the module starts.
        let (settings, keys) = try settings()
        settings.set(5_000, for: keys.historyLimit)

        await start()

        // `start` only schedules the work: no text has an answer until the scheduler runs a step.
        #expect(items.allSatisfy { $0.codeDetection == nil })
        let steps = await classifyEverything()

        #expect(steps >= 4 && steps < 200)
        let batches = module.classificationBatches
        #expect(batches.count == steps)
        #expect(batches.map(\.items).reduce(0, +) == big.count + short.count)
        // A step looks at about 256 KB, which is 64 texts of the 4 KB detection reads, however many short ones there are.
        let limit = ClipboardModule.classifyBatchBytes + ClipboardCodeDetector.sampleBytes
        #expect(batches.allSatisfy { $0.bytes <= limit }, "\(batches)")
        #expect(items.filter { $0.content.kind == .text }.allSatisfy { $0.isCode == $0.content.plainText!.hasPrefix("let total") })
        #expect(items.filter(\.isCode).count == big.count)
        #expect(items.first { $0.content.kind == .link }?.codeDetection == nil)
        // Nothing moved while the answers came in.
        #expect(items.map(\.id) == (big + [link] + short).map(\.id))
    }

    @Test func theAnswersAreSavedAndFindableWithTheCodeFilter() async throws {
        let code = legacy(.text(Self.swiftCode))
        let prose = legacy(.text("Xin chào"))
        await persist(ClipboardHistory(items: [prose, code]))
        await start()
        _ = await classifyEverything()
        harness.scheduler.advance(by: .seconds(1))
        await module.store?.waitForWrites()

        #expect(makeStore().load().items.map(\.codeDetection) == [.notCode, .code(.swift)])
        state.query.text = "@code"
        #expect(state.visibleItems.map(\.id) == [code.id])
    }

    @Test func aCopyMadeWhileTheOldTextsWaitKeepsItsOwnAnswerAndPlace() async throws {
        let old = legacy(.text("Hôm nay trời đẹp"))
        await persist(ClipboardHistory(items: [old]))
        await start()

        copy(Self.swiftCode)
        let copied = try #require(items.first)
        #expect(copied.codeDetection != nil)
        _ = await classifyEverything()

        #expect(items.map(\.id) == [copied.id, old.id])
        #expect(items.map(\.codeDetection) == [copied.codeDetection, .notCode])
    }

    @Test func stoppingTheModuleStopsTheClassification() async throws {
        await persist(ClipboardHistory(items: (0..<50).map { legacy(.text("ghi chú \($0)")) }))
        await start()
        harness.scheduler.advance(by: ClipboardModule.classifyStepDelay)

        await module.stop()
        await module.classification?.value
        harness.scheduler.advance(by: .seconds(5))

        #expect(items.isEmpty)
        #expect(module.classification == nil || module.classification?.isCancelled == true)
    }

    @Test func nothingIsScheduledWhenEveryTextHasAnAnswer() async throws {
        let decided = ClipboardItem(
            id: UUID(), content: .text("Xin chào"), contentHash: "h", copiedAt: system.now, sourceBundleID: nil, sourceAppName: nil,
            codeDetection: .notCode
        )
        await persist(ClipboardHistory(items: [decided]))
        await start()
        harness.scheduler.advance(by: .seconds(5))
        #expect(module.classification == nil)
        #expect(module.classificationBatches.isEmpty)
    }
}

@Suite struct ClipboardCardMenuCodeTests {
    func item(_ content: ClipboardContent) -> ClipboardItem {
        ClipboardItem(
            id: UUID(), content: content, contentHash: ClipboardContent.hash(of: content), copiedAt: .now,
            sourceBundleID: nil, sourceAppName: nil, codeDetection: ClipboardCodeDetector.detect(content)
        )
    }

    @Test func plainTextPasteIsOfferedForRichTextWhetherOrNotItIsCode() {
        let rtf = Data("{\\rtf1 x}".utf8)
        #expect(ClipboardCardMenu.offersPlainTextPaste(for: item(.richText(plain: "Xin chào", rtf: rtf))))
        #expect(ClipboardCardMenu.offersPlainTextPaste(for: item(.richText(plain: "SELECT id FROM users;", rtf: rtf))))
    }

    @Test func plainTextPasteIsNotOfferedWhereItChangesNothing() {
        #expect(!ClipboardCardMenu.offersPlainTextPaste(for: item(.text("Xin chào"))))
        #expect(!ClipboardCardMenu.offersPlainTextPaste(for: item(.text("SELECT id FROM users;"))))
        #expect(!ClipboardCardMenu.offersPlainTextPaste(for: item(.link(URL(string: "https://example.com")!))))
        #expect(!ClipboardCardMenu.offersPlainTextPaste(for: item(.color(hex: "#FF8800"))))
        #expect(!ClipboardCardMenu.offersPlainTextPaste(for: item(.files([URL(fileURLWithPath: "/tmp/a")]))))
    }
}
