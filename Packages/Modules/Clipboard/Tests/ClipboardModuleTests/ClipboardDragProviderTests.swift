import Foundation
import Testing
@testable import ClipboardModule

@Suite struct ClipboardDragProviderTests {
    @Test func textRichTextAndColorsDragAsStrings() {
        for content in [ClipboardContent.text("Xin chào"), .richText(plain: "Hi", rtf: Data()), .color(hex: "#FF8800")] {
            #expect(ClipboardDragProvider.make(for: content, fileURLs: []).registeredTypeIdentifiers == ["public.utf8-plain-text"])
        }
    }

    @Test func linksDragAsURLs() {
        let provider = ClipboardDragProvider.make(for: .link(URL(string: "https://apple.com")!), fileURLs: [])
        #expect(provider.registeredTypeIdentifiers == ["public.url"])
    }

    @Test func imagesAndFilesDragAsFileURLs() {
        let png = URL(fileURLWithPath: "/tmp/abc.png")
        let image = ClipboardContent.image(ClipboardImage(fileName: "abc.png", pixelWidth: 1, pixelHeight: 1, byteCount: 1))
        #expect(ClipboardDragProvider.make(for: image, fileURLs: [png]).registeredTypeIdentifiers.contains("public.file-url"))
        let files = ClipboardContent.files([URL(fileURLWithPath: "/tmp/a.txt")])
        #expect(ClipboardDragProvider.make(for: files, fileURLs: [URL(fileURLWithPath: "/tmp/a.txt")])
            .registeredTypeIdentifiers.contains("public.file-url"))
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
