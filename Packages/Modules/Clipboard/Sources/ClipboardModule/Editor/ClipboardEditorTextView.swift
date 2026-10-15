import AppKit
import SwiftUI

/// The editor's text: a plain-text view where nothing is changed behind the user's back (no smart quotes, dashes or replacements, which
/// would alter what is copied back), with undo, find, and, for code, the colours of the cards a moment after typing stops.
struct ClipboardEditorTextView: NSViewRepresentable {
    let model: ClipboardEditorModel

    static let proseSize: CGFloat = 15
    static let codeSize: CGFloat = 13

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.delegate = context.coordinator
        Self.configure(textView)
        context.coordinator.textView = textView
        context.coordinator.apply(font: Self.font(monospaced: model.isMonospaced), to: textView)
        textView.string = model.text
        context.coordinator.restyle(textView)
        context.coordinator.scheduleAnalysis()
        // The window is not there yet; the text takes the keyboard once it is.
        Task { [weak textView] in textView?.window?.makeFirstResponder(textView) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        let font = Self.font(monospaced: model.isMonospaced)
        if textView.font != font {
            context.coordinator.apply(font: font, to: textView)
            context.coordinator.restyle(textView)
        }
        // Only a change that did not come from typing (the model forgetting its words) needs the view told.
        if textView.string != model.text, !textView.hasMarkedText() {
            textView.string = model.text
            context.coordinator.restyle(textView)
        }
        Self.applyDroppedState(textView, for: model)
    }

    /// An editor whose words a lock dropped shows nothing and takes no typing, and forgets what could be undone: the undo stack holds
    /// the words it replaced, which must not outlive the lock either.
    static func applyDroppedState(_ textView: NSTextView, for model: ClipboardEditorModel) {
        textView.isEditable = !model.isDroppedOnLock
        guard model.isDroppedOnLock else { return }
        if !textView.string.isEmpty { textView.string = "" }
        textView.undoManager?.removeAllActions()
    }

    /// Plain text, editable, with undo and find, and nothing changed behind the user's back (no smart quotes, dashes or replacements,
    /// which would alter what is copied back).
    static func configure(_ textView: NSTextView) {
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isEditable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 14, height: 12)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        // What is typed here may be a secret of an open board: nothing reads it to complete, predict or rewrite it.
        textView.isAutomaticTextCompletionEnabled = false
        textView.inlinePredictionType = .no
        textView.writingToolsBehavior = .none
        textView.setAccessibilityLabel("Nội dung đang sửa")
    }

    static func font(monospaced: Bool) -> NSFont {
        monospaced ? NSFont.monospacedSystemFont(ofSize: codeSize, weight: .regular) : NSFont.systemFont(ofSize: proseSize)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let model: ClipboardEditorModel
        weak var textView: NSTextView?
        private var analysis: Task<Void, Never>?
        private var runs: [ClipboardPreviewHighlight.Run] = []
        /// A short wait after the last key, so highlighting a long text never runs per letter.
        static let pause: Duration = .milliseconds(250)

        init(model: ClipboardEditorModel) {
            self.model = model
        }

        func textDidChange(_ notification: Notification) {
            // Colouring changes the text's attributes and never its words: only a change of the words is a change.
            guard let textView, model.text != textView.string else { return }
            model.text = textView.string
            // The next letter takes the plain colour, not that of the word it follows.
            textView.typingAttributes = baseAttributes(for: textView)
            scheduleAnalysis()
        }

        func apply(font: NSFont, to textView: NSTextView) {
            textView.font = font
            textView.typingAttributes = baseAttributes(for: textView)
        }

        func baseAttributes(for textView: NSTextView) -> [NSAttributedString.Key: Any] {
            let font = textView.font ?? ClipboardEditorTextView.font(monospaced: model.isMonospaced)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = model.isMonospaced ? 2 : 3
            paragraph.defaultTabInterval = font.maximumAdvancement.width * 4
            paragraph.tabStops = []
            return [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
        }

        /// The whole text in the plain look, then the colours of the last analysis over it.
        func restyle(_ textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            storage.beginEditing()
            storage.setAttributes(baseAttributes(for: textView), range: NSRange(location: 0, length: storage.length))
            storage.endEditing()
            colour(textView)
        }

        func scheduleAnalysis() {
            analysis?.cancel()
            analysis = Task { [weak self] in
                try? await Task.sleep(for: Self.pause)
                guard !Task.isCancelled, let self, let textView else { return }
                let text = textView.string
                let result = await ClipboardEditorHighlight.analyze(text)
                // The words moved on while it was worked out: its answer is for words that are gone.
                guard !Task.isCancelled, textView.string == text else { return }
                model.detectedLanguage = result.language
                runs = result.runs
                // Not while an input method is composing: changing the text's attributes would end it.
                if !textView.hasMarkedText() { restyle(textView) }
            }
        }

        private func colour(_ textView: NSTextView) {
            guard let storage = textView.textStorage, !runs.isEmpty else { return }
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
}
