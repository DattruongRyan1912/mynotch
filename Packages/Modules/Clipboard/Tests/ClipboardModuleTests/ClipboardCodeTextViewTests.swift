import AppKit
import SwiftUI
import Testing
@testable import ClipboardModule

/// Draws the view into an image in memory (no window, no screen) and looks at the pixels, so the colours that reach the
/// screen are checked and not only the attributes that were set.
@Suite struct ClipboardCodeTextViewTests {
    /// The pixels of `view` on a black background, as (red, green, blue) in 0...255.
    func pixels(of view: some View) throws -> [(Int, Int, Int)] {
        let renderer = ImageRenderer(content: view.background(Color.black).frame(width: 400, height: 80))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let bitmap = NSBitmapImageRep(cgImage: image)
        return (0..<bitmap.pixelsHigh).flatMap { y in
            (0..<bitmap.pixelsWide).compactMap { x in
                bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB).map {
                    (Int($0.redComponent * 255), Int($0.greenComponent * 255), Int($0.blueComponent * 255))
                }
            }
        }
    }

    func contains(_ pixels: [(Int, Int, Int)], near color: (Int, Int, Int), tolerance: Int = 24) -> Bool {
        pixels.contains { abs($0.0 - color.0) <= tolerance && abs($0.1 - color.1) <= tolerance && abs($0.2 - color.2) <= tolerance }
    }

    @Test func codeIsDrawnInTheColoursOfItsTokens() throws {
        let view = ClipboardCodeText(
            text: "let x = 1 // hi", language: .swift, palette: .dark, size: 36, lines: 1, color: .white
        )
        let drawn = try pixels(of: view)
        #expect(contains(drawn, near: (252, 94, 163)), "keyword")
        #expect(contains(drawn, near: (209, 191, 105)), "number")
        #expect(contains(drawn, near: (130, 143, 158)), "comment")
        #expect(contains(drawn, near: (255, 255, 255)), "the colour of what has no token")
    }

    @Test func aTextWithoutALanguageStaysOneColour() throws {
        let view = ClipboardContentPreview(
            content: .text("let x = 1"), imageURL: nil, thumbnails: ClipboardThumbnailCache(),
            style: ClipboardContentPreview.Style(
                primary: .white, secondary: .gray, swatchBorder: .white, textLines: 1, textSize: 36, detailSize: 10, fileIconSize: 32
            )
        )
        let drawn = try pixels(of: view)
        #expect(!contains(drawn, near: (252, 94, 163)))
        #expect(contains(drawn, near: (255, 255, 255)))
    }

    @Test func aCodeItemInThePreviewIsColouredByItsLanguage() throws {
        let view = ClipboardContentPreview(
            content: .text("let x = 1"), codeLanguage: .swift, imageURL: nil, thumbnails: ClipboardThumbnailCache(),
            style: ClipboardContentPreview.Style(
                primary: .white, secondary: .gray, swatchBorder: .white, textLines: 1, textSize: 36, detailSize: 10, fileIconSize: 32,
                codePalette: .dark
            )
        )
        #expect(contains(try pixels(of: view), near: (252, 94, 163)))
    }
}
