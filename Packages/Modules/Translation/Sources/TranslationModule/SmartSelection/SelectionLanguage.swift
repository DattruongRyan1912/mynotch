import Foundation
import NaturalLanguage

/// Whether a selection is foreign text worth a preview: the language it is in, how sure that is, and whether there is enough
/// of it. Pure and on-device.
nonisolated enum SelectionLanguage {
    /// Below this the recognizer is not sure enough to tell the user their text is foreign.
    static let minimumConfidence = 0.6

    /// The most likely language, if it is likely enough.
    static func pick(from hypotheses: [NLLanguage: Double]) -> NLLanguage? {
        guard let best = hypotheses.max(by: { $0.value < $1.value }), best.value >= minimumConfidence else { return nil }
        return best.key
    }

    static func dominant(of text: String) -> NLLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return pick(from: recognizer.languageHypotheses(withMaximum: 1))
    }

    /// Two words, or four characters of Chinese, Japanese or Korean, which have no spaces between words. One word is a
    /// dictionary's business, and the recognizer is often wrong about it.
    static func hasEnoughToTranslate(_ text: String) -> Bool {
        if text.unicodeScalars.count(where: isCJK) >= 4 { return true }
        let words = text.split { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "’" }
        return words.count(where: { $0.contains(where: \.isLetter) }) >= 2
    }

    /// The language to translate `text` from: the one it is written in, when it is not the target's, enough of it is there,
    /// and some candidate is that language. Candidates are tried in order, so the one the user prefers wins ("en" before "en-AU").
    static func source(of text: String, target: Locale.Language, candidates: [Locale.Language]) -> Locale.Language? {
        guard hasEnoughToTranslate(text), let dominant = dominant(of: text) else { return nil }
        guard LanguageDetector.writtenLanguage(of: target) != dominant else { return nil }
        return candidates.first { LanguageDetector.writtenLanguage(of: $0) == dominant }
    }

    /// `source`, off the main actor: recognizing a long text is not instant.
    @concurrent static func sourceInBackground(of text: String, target: Locale.Language, candidates: [Locale.Language]) async -> Locale.Language? {
        source(of: text, target: target, candidates: candidates)
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF,        // hiragana, katakana
             0x3400...0x4DBF,        // Han, extension A
             0x4E00...0x9FFF,        // Han
             0xAC00...0xD7AF,        // Hangul syllables
             0xF900...0xFAFF,        // Han compatibility
             0x20000...0x2A6DF:      // Han, extension B
            true
        default:
            false
        }
    }
}
