import Foundation
import Testing
@testable import ClipboardModule

@Suite struct ClipboardDragProviderTests {
    /// What a drop target gets of the provider as a string.
    static func string(of provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                continuation.resume(returning: (object as? NSString).map { $0 as String })
            }
        }
    }

    static func data(of provider: NSItemProvider, as type: String) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in continuation.resume(returning: data) }
        }
    }

    @Test func textAndColorsDragAsStrings() async {
        for content in [ClipboardContent.text("Xin chào"), .color(hex: "#FF8800")] {
            #expect(ClipboardDragProvider.make(for: content, fileURLs: []).registeredTypeIdentifiers == ["public.utf8-plain-text"])
        }
        #expect(await Self.string(of: ClipboardDragProvider.make(for: .text("Xin chào"), fileURLs: [])) == "Xin chào")
    }

    @Test func richTextDragsAsRTFAndThenAsPlainText() async {
        let rtf = Data("{\\rtf1 Bảng giá}".utf8)
        let provider = ClipboardDragProvider.make(for: .richText(plain: "Bảng giá", rtf: rtf), fileURLs: [])

        // RTF first, so a target that formats gets it; the plain text for one that takes only text.
        #expect(provider.registeredTypeIdentifiers == ["public.rtf", "public.utf8-plain-text"])
        #expect(await Self.data(of: provider, as: "public.rtf") == rtf)
        #expect(await Self.string(of: provider) == "Bảng giá")
    }

    @Test func richTextWithNoRTFDragsAsPlainTextOnly() {
        let provider = ClipboardDragProvider.make(for: .richText(plain: "Hi", rtf: Data()), fileURLs: [])
        #expect(provider.registeredTypeIdentifiers == ["public.utf8-plain-text"])
    }

    @Test func aCssColorDragsAsTheTextItWasCopiedAs() async {
        let provider = ClipboardDragProvider.make(for: .color(hex: "#FF8800", original: "rgb(255, 136, 0)"), fileURLs: [])
        #expect(provider.registeredTypeIdentifiers == ["public.utf8-plain-text"])
        #expect(await Self.string(of: provider) == "rgb(255, 136, 0)")
    }

    @Test func linksDragAsURLsAndThenAsStrings() async {
        let address = URL(string: "https://apple.com/vi")!
        let provider = ClipboardDragProvider.make(for: .link(address), fileURLs: [])

        #expect(provider.registeredTypeIdentifiers == ["public.url", "public.utf8-plain-text"])
        #expect(await Self.string(of: provider) == "https://apple.com/vi")
        let url = await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: NSURL.self) { object, _ in continuation.resume(returning: (object as? NSURL).map { $0 as URL }) }
        }
        #expect(url == address)
    }

    @Test func filesDragAsTheirFileURL() {
        let files = ClipboardContent.files([URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b.txt")])
        let provider = ClipboardDragProvider.make(for: files, fileURLs: [URL(fileURLWithPath: "/tmp/a.txt")])
        #expect(provider.registeredTypeIdentifiers.contains("public.file-url"))
        #expect(!provider.registeredTypeIdentifiers.contains("public.png"))
    }

    @Test func imagesDragAsTheFileURLOfTheirCopyAndThenAsPNGData() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ClipboardDragProviderTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let png = folder.appending(path: "abc.png")
        try Data([1, 2, 3]).write(to: png)
        let image = ClipboardContent.image(ClipboardImage(fileName: "abc.png", pixelWidth: 1, pixelHeight: 1, byteCount: 3))
        let provider = ClipboardDragProvider.make(for: image, fileURLs: [png])

        // The file's URL first (a file URL is a URL too), then the picture itself.
        #expect(provider.registeredTypeIdentifiers == ["public.file-url", "public.url", "public.png"])
        // Read when a target asks, not when the drag starts: the file is changed in between.
        try Data([9, 9]).write(to: png)
        #expect(await Self.data(of: provider, as: "public.png") == Data([9, 9]))
    }

    @Test func aPictureWhoseFileIsGoneByTheTimeATargetAsksGivesNoData() async throws {
        let png = FileManager.default.temporaryDirectory.appending(path: "ClipboardDragProviderTests-gone-\(UUID().uuidString).png")
        let image = ClipboardContent.image(ClipboardImage(fileName: "abc.png", pixelWidth: 1, pixelHeight: 1, byteCount: 3))
        let provider = ClipboardDragProvider.make(for: image, fileURLs: [png])
        #expect(await Self.data(of: provider, as: "public.png") == nil)
    }

    @Test func anImageWhoseFileIsGoneDragsNothing() {
        let image = ClipboardContent.image(ClipboardImage(fileName: "abc.png", pixelWidth: 1, pixelHeight: 1, byteCount: 1))
        #expect(ClipboardDragProvider.make(for: image, fileURLs: []).registeredTypeIdentifiers.isEmpty)
    }

    @Test func draggedImagesAreNamedAfterTheirCopyTime() {
        let date = Date(timeIntervalSince1970: 1_791_916_630) // 2026-10-13 18:37:10 UTC
        #expect(ClipboardDragProvider.imageFileName(copiedAt: date, timeZone: TimeZone(identifier: "UTC")!)
            == "Ảnh clipboard 2026-10-13 18.37.10.png")
    }

    /// A drop must never move or rename the stored file, so each drag gets its own copy.
    @Test func imagesAreDraggedAsACopyAndTheStoredFileStays() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ClipboardDragProviderTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let stored = root.appending(path: Data("png".utf8).sha256Hex + ".png")
        try Data([1, 2, 3]).write(to: stored)
        let drags = root.appending(path: "Drags")
        let date = Date(timeIntervalSince1970: 1_791_916_630)

        let first = try ClipboardDragProvider.copyImage(at: stored, copiedAt: date, into: drags)
        let second = try ClipboardDragProvider.copyImage(at: stored, copiedAt: date, into: drags)

        #expect(first != second)
        for copy in [first, second] {
            #expect(copy.lastPathComponent == ClipboardDragProvider.imageFileName(copiedAt: date))
            #expect(copy.path(percentEncoded: false).hasPrefix(drags.path(percentEncoded: false)))
            #expect(try Data(contentsOf: copy) == Data([1, 2, 3]))
        }
        #expect(try Data(contentsOf: stored) == Data([1, 2, 3]))
    }
}
