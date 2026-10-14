import AppKit
import Testing
@testable import ClipboardModule

/// Uses a private named pasteboard per test; the system pasteboard is never touched.
@Suite final class SystemPasteboardTests {
    let pasteboard = NSPasteboard(name: .init("MyNotchTests.\(UUID().uuidString)"))
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "SystemPasteboardTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    let classifier = ClipboardClassifier(ignoreSensitive: true, colorsWithoutHash: true)
    lazy var access = SystemPasteboard(pasteboard: pasteboard)

    isolated deinit {
        pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: directory)
    }

    /// `nonisolated` because test arguments are built off the main actor.
    nonisolated static let rtf = Data("{\\rtf1\\ansi Xin {\\b chào}}".utf8)

    static let sourceType = "org.nspasteboard.source"

    func writeAndRead(
        _ content: ClipboardContent, imageURL: URL? = nil, plainTextOnly: Bool = false, sourceBundleID: String? = nil
    ) throws -> PasteboardSnapshot {
        try #require(access.write(content, imageURL: imageURL, plainTextOnly: plainTextOnly, sourceBundleID: sourceBundleID))
        return try #require(access.snapshot())
    }

    /// Another app's text is on the pasteboard; a write that cannot happen must leave it exactly as it was.
    func expectWriteFailsWithoutTouchingThePasteboard(_ content: ClipboardContent, imageURL: URL?) throws {
        pasteboard.clearContents()
        pasteboard.setString("keep me", forType: .string)
        let changeCount = access.changeCount

        #expect(!access.write(content, imageURL: imageURL, plainTextOnly: false))
        #expect(access.changeCount == changeCount)
        #expect(try #require(access.snapshot()).string == "keep me")
    }

    /// What the monitor would record if the marker were missing, so a write must read back as the content written.
    func unmarked(_ snapshot: PasteboardSnapshot) -> ClassificationResult {
        var snapshot = snapshot
        snapshot.types.removeAll { $0 == ClipboardClassifier.ownWriteType }
        return classifier.classify(snapshot)
    }

    @Test(arguments: [
        ClipboardContent.text("Xin chào"),
        .richText(plain: "Xin chào", rtf: rtf),
        .link(URL(string: "https://example.com/a?b=1")!),
        .color(hex: "#FF8800"),
        .color(hex: "#FF8800", original: "rgb(255, 136, 0)"),
        .color(hex: "#33669980", original: "hsla(210 50% 40% / 50%)"),
    ])
    func textualContentReadsBackWithTheMarker(content: ClipboardContent) throws {
        let snapshot = try writeAndRead(content)

        #expect(snapshot.types.contains(ClipboardClassifier.ownWriteType))
        #expect(classifier.classify(snapshot) == .skipped(.ownWrite))
        #expect(unmarked(snapshot) == .content(content, imageData: nil))
    }

    @Test func linkIsWrittenAsURLAndString() throws {
        let url = URL(string: "https://example.com/a?b=1")!
        let snapshot = try writeAndRead(.link(url))

        #expect(snapshot.url == url)
        #expect(snapshot.string == url.absoluteString)
    }

    @Test func plainTextOnlyDropsTheRTF() throws {
        let snapshot = try writeAndRead(.richText(plain: "Xin chào", rtf: Self.rtf), plainTextOnly: true)

        #expect(snapshot.rtf == nil)
        #expect(snapshot.types.contains(ClipboardClassifier.ownWriteType))
        #expect(unmarked(snapshot) == .content(.text("Xin chào"), imageData: nil))
    }

    @Test func imageIsWrittenAsThePNGFromItsFile() throws {
        let png = ClipboardClassifierTests.png
        guard case .content(let content, _) = classifier.classify(PasteboardSnapshot(types: ["public.png"], png: png)),
              case .image(let image) = content else {
            Issue.record("Fixture PNG did not classify as an image")
            return
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let imageURL = directory.appending(path: image.fileName)
        try png.write(to: imageURL)

        let snapshot = try writeAndRead(content, imageURL: imageURL)

        #expect(snapshot.png == png)
        #expect(snapshot.types.contains(ClipboardClassifier.ownWriteType))
        #expect(unmarked(snapshot) == .content(content, imageData: png))
    }

    @Test func filesRoundTripWithTheMarkersOnTheFirstItem() throws {
        let urls = [URL(fileURLWithPath: "/tmp/MyNotchTests/a.txt"), URL(fileURLWithPath: "/tmp/MyNotchTests/b c.txt")]
        let snapshot = try writeAndRead(.files(urls), sourceBundleID: "com.apple.finder")

        #expect(snapshot.fileURLs == urls)
        #expect(pasteboard.pasteboardItems?.count == 2)
        #expect(snapshot.types.contains(ClipboardClassifier.ownWriteType))
        #expect(snapshot.types.contains(Self.sourceType))
        #expect(unmarked(snapshot) == .content(.files(urls), imageData: nil))
    }

    @Test func eachWriteReplacesThePreviousContent() throws {
        access.write(.files([URL(fileURLWithPath: "/tmp/MyNotchTests/a.txt")]), imageURL: nil, plainTextOnly: false)
        let before = access.changeCount
        let snapshot = try writeAndRead(.text("Xin chào"))

        #expect(access.changeCount > before)
        #expect(snapshot.fileURLs.isEmpty)
        #expect(pasteboard.pasteboardItems?.count == 1)
    }

    @Test func theSourceAppIsRecordedOnlyWhenKnown() throws {
        _ = try writeAndRead(.text("Xin chào"), sourceBundleID: "com.apple.Safari")
        #expect(pasteboard.pasteboardItems?.first?.string(forType: .init(Self.sourceType)) == "com.apple.Safari")

        let withoutSource = try writeAndRead(.text("Xin chào"))
        #expect(!withoutSource.types.contains(Self.sourceType))
    }

    @Test func contentThatCannotBeWrittenLeavesThePasteboardUntouched() throws {
        let image = ClipboardContent.image(ClipboardImage(fileName: "a.png", pixelWidth: 1, pixelHeight: 1, byteCount: 4))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let emptyFile = directory.appending(path: "empty.png")
        try Data().write(to: emptyFile)

        try expectWriteFailsWithoutTouchingThePasteboard(image, imageURL: nil)
        try expectWriteFailsWithoutTouchingThePasteboard(image, imageURL: directory.appending(path: "missing.png"))
        try expectWriteFailsWithoutTouchingThePasteboard(image, imageURL: emptyFile)
        try expectWriteFailsWithoutTouchingThePasteboard(.files([]), imageURL: nil)
    }

    @Test func tiffIsReadOnlyWithoutPNG() throws {
        let png = ClipboardClassifierTests.png
        let tiff = ClipboardClassifierTests.tiff
        pasteboard.clearContents()
        let both = NSPasteboardItem()
        both.setData(png, forType: .png)
        both.setData(tiff, forType: .tiff)
        pasteboard.writeObjects([both])

        let withPNG = try #require(access.snapshot())
        #expect(withPNG.png == png)
        #expect(withPNG.tiff == nil)

        pasteboard.clearContents()
        let tiffOnly = NSPasteboardItem()
        tiffOnly.setData(tiff, forType: .tiff)
        pasteboard.writeObjects([tiffOnly])

        let withoutPNG = try #require(access.snapshot())
        #expect(withoutPNG.png == nil)
        #expect(withoutPNG.tiff == tiff)
    }

    @Test func anotherAppsTextIsReadWithoutTheMarker() throws {
        pasteboard.clearContents()
        pasteboard.setString("from Notes", forType: .string)

        let snapshot = try #require(access.snapshot())
        #expect(snapshot.types == [NSPasteboard.PasteboardType.string.rawValue])
        #expect(classifier.classify(snapshot) == .content(.text("from Notes"), imageData: nil))
    }

    @Test func anEmptyPasteboardHasNoSnapshot() {
        pasteboard.clearContents()

        #expect(access.snapshot() == nil)
    }
}
