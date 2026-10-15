import Foundation

/// What the editor finds out about the words in the background, a moment after the user stops typing: whether they are code, and the
/// coloured stretches if so. From the same detector, tokenizer and bounds as the cards and the large preview.
nonisolated enum ClipboardEditorHighlight {
    struct Analysis: Equatable, Sendable {
        let language: CodeLanguage?
        let runs: [ClipboardPreviewHighlight.Run]
    }

    static func analysis(of text: String) -> Analysis {
        guard let language = ClipboardCodeDetector.detect(text: text).language else { return Analysis(language: nil, runs: []) }
        return Analysis(language: language, runs: ClipboardPreviewHighlight.runs(for: text, language: language))
    }

    /// Off the main actor, so typing in a long text is never held up by it.
    @concurrent static func analyze(_ text: String) async -> Analysis {
        analysis(of: text)
    }
}
