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
}
