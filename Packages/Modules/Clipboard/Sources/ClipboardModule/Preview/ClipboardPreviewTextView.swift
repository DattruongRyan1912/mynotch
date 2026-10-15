import AppKit
import SwiftUI

/// A text or code of any length, scrollable, in a text view: a SwiftUI `Text` lays out all of its text at once, which a long copy
/// would stall on. Nothing is edited, and nothing is written anywhere. The colours come in after the text, when they are ready.
struct ClipboardPreviewTextView: NSViewRepresentable {
    let text: String
    /// Monospaced when it is code.
    let isCode: Bool
    let runs: [ClipboardPreviewHighlight.Run]
    /// For the inspector's pane: smaller type and margins.
    var isCompact = false

    static let codeSize: CGFloat = 14
    static let textSize: CGFloat = 17
    static let compactCodeSize: CGFloat = 11
    static let compactTextSize: CGFloat = 13

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        if let textView = scroll.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.drawsBackground = false
            textView.textContainerInset = isCompact ? NSSize(width: 10, height: 8) : NSSize(width: 24, height: 20)
            textView.isAutomaticLinkDetectionEnabled = false
            textView.isRichText = true
            textView.textStorage?.setAttributedString(Self.attributed(text, isCode: isCode, isCompact: isCompact))
            context.coordinator.runs = []
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView, let storage = textView.textStorage else { return }
        if context.coordinator.runs != runs {
            context.coordinator.runs = runs
            let colors = Dictionary(uniqueKeysWithValues: [CodeTokenKind.keyword, .string, .comment, .number, .punctuation].map {
                ($0, CodePalette.adaptive.nsColor(for: $0))
            })
            storage.beginEditing()
            for run in runs where run.range.upperBound <= storage.length {
                storage.addAttribute(.foregroundColor, value: colors[run.kind] ?? NSColor.labelColor, range: run.range)
            }
            storage.endEditing()
        }
    }

    final class Coordinator {
        var runs: [ClipboardPreviewHighlight.Run] = []
    }

    /// Large and readable: a preview is for reading, not for fitting a card.
    static func attributed(_ text: String, isCode: Bool, isCompact: Bool = false) -> NSAttributedString {
        let codeSize = isCompact ? compactCodeSize : codeSize, textSize = isCompact ? compactTextSize : textSize
        let font = isCode ? NSFont.monospacedSystemFont(ofSize: codeSize, weight: .regular) : NSFont.systemFont(ofSize: textSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = isCode ? 2 : (isCompact ? 2 : 4)
        // A tab is four characters wide, as in an editor.
        paragraph.defaultTabInterval = font.maximumAdvancement.width * 4
        paragraph.tabStops = []
        return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph])
    }
}
