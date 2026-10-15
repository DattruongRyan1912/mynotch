import AppKit
import NotchUI
import SwiftUI
import Testing
@testable import TranslationModule

/// How much room a translation takes in the chip: all of it up to about eight lines, then it scrolls inside the chip, and the
/// chip is never taller than the room beside the selection. Measured with the font the chip draws in.
@Suite struct SelectionChipLayoutTests {
    let line = SelectionChipLayout.lineHeight

    func lines(_ count: Int, _ word: String = "Xin chào") -> String {
        (1...count).map { "\(word) \($0)" }.joined(separator: "\n")
    }

    @Test func oneShortLineIsOneLineOnTheNarrowestChip() {
        let metrics = SelectionChipLayout.metrics(for: "Xin chào", caption: nil)
        #expect(metrics.textHeight == line)
        #expect(!metrics.scrolls)
        #expect(metrics.textWidth == SelectionChipLayout.minTextWidth)
    }

    @Test func aLongLineWrapsAtTheWidestChip() {
        let text = String(repeating: "Hôm nay trời đẹp quá, chúng ta đi dạo nhé. ", count: 4)
        let metrics = SelectionChipLayout.metrics(for: text, caption: nil)
        #expect(metrics.textWidth == SelectionChipLayout.maxTextWidth)
        #expect(metrics.textHeight > 2 * line)
        #expect(!metrics.scrolls)
    }

    @Test func eachLineOfATranslationTakesItsOwnRow() {
        #expect(SelectionChipLayout.metrics(for: lines(3), caption: nil).textHeight == 3 * line)
        #expect(SelectionChipLayout.metrics(for: lines(5), caption: nil).textHeight == 5 * line)
    }

    @Test func eightLinesFitAndANinthScrolls() {
        let eight = SelectionChipLayout.metrics(for: lines(8), caption: nil)
        #expect(eight.textHeight == 8 * line)
        #expect(!eight.scrolls)
        let nine = SelectionChipLayout.metrics(for: lines(9), caption: nil)
        #expect(nine.textHeight == 8 * line)
        #expect(nine.scrolls)
    }

    @Test func aVeryLongTranslationScrollsInsideAChipThatStaysUnderTheLimit() {
        let text = String(repeating: "Hôm nay trời đẹp quá, chúng ta đi dạo nhé. ", count: 45)
        #expect(text.count > 1_900)
        let metrics = SelectionChipLayout.metrics(for: text, caption: "Good morning")
        #expect(metrics.scrolls)
        #expect(metrics.textHeight == 8 * line)
        #expect(metrics.chipHeight <= SelectionChipLayout.maxHeight)
    }

    @Test func aChipWithLittleRoomShrinksItsTextAndDropsTheCaption() {
        let text = lines(8)
        let roomy = SelectionChipLayout.metrics(for: text, caption: "Good morning", maxHeight: 280)
        #expect(roomy.showsCaption)
        let tight = SelectionChipLayout.metrics(for: text, caption: "Good morning", maxHeight: 120)
        #expect(!tight.showsCaption)
        #expect(tight.scrolls)
        #expect(tight.textHeight < roomy.textHeight)
        #expect(tight.chipHeight <= 120)
    }

    @Test func aChipNeverGetsLessThanTwoLines() {
        let metrics = SelectionChipLayout.metrics(for: lines(8), caption: nil, maxHeight: 10)
        #expect(metrics.textHeight == 2 * line)
        #expect(metrics.scrolls)
    }

    @Test func theCaptionIsOnlyThereWhenThereIsOne() {
        #expect(!SelectionChipLayout.metrics(for: "Xin chào", caption: nil).showsCaption)
        #expect(SelectionChipLayout.metrics(for: "Xin chào", caption: "Hello").showsCaption)
    }

    @Test func aChipWithACaptionIsTallerByTheCaption() {
        let without = SelectionChipLayout.metrics(for: "Xin chào", caption: nil)
        let with = SelectionChipLayout.metrics(for: "Xin chào", caption: "Hello")
        #expect(with.chipHeight == without.chipHeight + SelectionChipLayout.captionHeight)
    }

    @Test func theSmallestChipIsTwoLinesAndItsChrome() {
        #expect(SelectionChipLayout.minChipHeight == 2 * line + SelectionChipLayout.chromeHeight)
        #expect(SelectionChipLayout.metrics(for: lines(8), caption: nil, maxHeight: SelectionChipLayout.minChipHeight).chipHeight
            == SelectionChipLayout.minChipHeight)
    }

    // MARK: what the view really draws

    func content(_ text: String, caption: String? = nil) -> SelectionChipContent {
        SelectionChipContent(kind: .translation, text: text, caption: caption, open: {}, deny: {}, hover: { _ in })
    }

    func size(of text: String, caption: String? = nil, maxHeight: CGFloat = SelectionChipLayout.maxHeight) -> CGSize {
        let view = SelectionChipView(content: content(text, caption: caption), interface: NotchInterface(), maxHeight: maxHeight)
        return NSHostingView(rootView: view).fittingSize
    }

    @Test func theViewIsAsTallAsTheLayoutSays() {
        for (text, caption) in [("Xin chào", nil), (lines(3), "Hello"), (lines(8), nil), (lines(30), "Hello")] as [(String, String?)] {
            let metrics = SelectionChipLayout.metrics(for: text, caption: caption)
            let drawn = size(of: text, caption: caption)
            #expect(abs(drawn.height - metrics.chipHeight) < 4, "\(text.prefix(12)) \(drawn.height) vs \(metrics.chipHeight)")
            #expect(drawn.width <= SelectionChipLayout.maxWidth)
        }
    }

    @Test func aLongTranslationNeverMakesTheViewTallerThanTheLimit() {
        #expect(size(of: lines(200), caption: "Hello").height <= SelectionChipLayout.maxHeight)
        #expect(size(of: lines(200), maxHeight: 100).height <= 100)
    }

    @Test func theNoteBesideTheButtonDoesNotMakeTheChipTaller() {
        func height(note: String?) -> CGFloat {
            let model = SelectionChipContent(kind: .translation, text: lines(3), caption: "Hello", note: note, open: {}, deny: {}, hover: { _ in })
            return NSHostingView(rootView: SelectionChipView(content: model, interface: NotchInterface())).fittingSize.height
        }
        #expect(abs(height(note: "Mở để dịch đủ") - height(note: nil)) < 1)
    }

    @Test func theNoteIsDrawnBesideTheButton() throws {
        func brightPixelsInTheBottomRow(note: String?) throws -> Int {
            let model = SelectionChipContent(kind: .translation, text: lines(3), caption: nil, note: note, open: {}, deny: nil, hover: { _ in })
            let renderer = ImageRenderer(content: SelectionChipLabel(content: model).environment(\.colorScheme, .dark).background(Color.black))
            renderer.scale = 1
            let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
            var count = 0
            // The row under the text: the icon, the note, the button.
            for y in (bitmap.pixelsHigh - 28)..<(bitmap.pixelsHigh - 8) {
                for x in 0..<(bitmap.pixelsWide / 2) {
                    if let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), pixel.brightnessComponent > 0.35 { count += 1 }
                }
            }
            return count
        }
        #expect(try brightPixelsInTheBottomRow(note: "Mở để dịch đủ") > brightPixelsInTheBottomRow(note: nil) + 20)
    }

    @Test func theChipsPreviewEngineLetsACancelledPreviewGoAfterAShortGrace() {
        #expect(SmartSelectionSetup.systemPreview().graceForCancelled == SmartSelectionSetup.previewGrace)
        #expect(SmartSelectionSetup.previewGrace <= .milliseconds(200))
        // The tab's own engine keeps requests strictly one at a time.
        #expect(AppleTranslationEngine().graceForCancelled == nil)
    }

    @Test func aShortTranslationStaysCompact() {
        #expect(size(of: "Xin chào").height < 90)
    }

    @Test func theViewKeepsTheWholeText() {
        // The model is never cut to fit: it is what the chip scrolls through.
        let text = lines(40)
        let model = content(text)
        #expect(model.text == text)
        #expect(model.text.split(separator: "\n").count == 40)
    }
}
