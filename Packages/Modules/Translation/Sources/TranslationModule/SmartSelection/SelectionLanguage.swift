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
        guess(of: text)?.language
    }

    private static func guess(of text: String) -> (language: NLLanguage, confidence: Double)? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
        return pick(from: hypotheses).map { ($0, hypotheses[$0] ?? 0) }
    }

    /// Two words, or four characters of Chinese, Japanese or Korean, which have no spaces between words. Words are what sits
    /// between spaces and has a letter in it: a URL, an email address and a path are one each, however many parts they have.
    /// One word is a dictionary's business, and the recognizer is often wrong about it.
    static func hasEnoughToTranslate(_ text: String) -> Bool {
        if text.unicodeScalars.count(where: isCJK) >= 4 { return true }
        return wordCount(of: text) >= 2
    }

    private static func wordCount(of text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count(where: { $0.contains(where: \.isLetter) })
    }

    /// What to make of a selection: the language to translate it from, or the reason there is none.
    nonisolated enum Assessment: Equatable, Sendable {
        case source(Locale.Language)
        case skip(SelectionSkip)
    }

    /// The language to translate `text` from: the one it is written in, when it is not the target's, enough of it is there,
    /// it is a text somebody wrote to be read (see `SelectionShape`), and some candidate is that language. Candidates are tried
    /// in order, so the one the user prefers wins ("en" before "en-AU").
    ///
    /// For a Vietnamese user, text with no accents is held to more: Vietnamese typed that way is often taken for Italian or
    /// Romanian, so a text with several common Vietnamese words shows nothing, and any guess needs 0.9 and three words.
    static func assess(_ text: String, target: Locale.Language, candidates: [Locale.Language]) -> Assessment {
        let text = SelectionShape.normalizeGluedSentences(text)
        switch SelectionShape.kind(of: text) {
        case .code: return .skip(.shapeCode)
        case .name: return .skip(.shapeName)
        case .prose: break
        }
        guard hasEnoughToTranslate(text) else { return .skip(.shapeShort) }
        guard let guess = guess(of: text) else { return .skip(.lowConfidence) }
        guard LanguageDetector.writtenLanguage(of: target) != guess.language else { return .skip(.sameLanguage) }
        guard passesUnaccentedRules(text: text, target: target, confidence: guess.confidence) else { return .skip(.lowConfidence) }
        guard let source = candidates.first(where: { LanguageDetector.writtenLanguage(of: $0) == guess.language }) else {
            return .skip(.unsupportedLanguage)
        }
        return .source(source)
    }

    static func source(of text: String, target: Locale.Language, candidates: [Locale.Language]) -> Locale.Language? {
        if case .source(let language) = assess(text, target: target, candidates: candidates) { language } else { nil }
    }

    /// `assess`, off the main actor: recognizing a long text is not instant.
    @concurrent static func assessInBackground(_ text: String, target: Locale.Language, candidates: [Locale.Language]) async -> Assessment {
        assess(text, target: target, candidates: candidates)
    }

    /// Whether a guess about `text` of that confidence stands once the rules for a Vietnamese user's unaccented text are
    /// applied: no several common Vietnamese words in it, and a sure enough guess about enough words.
    static func passesUnaccentedRules(text: String, target: Locale.Language, confidence: Double) -> Bool {
        guard appliesUnaccentedRules(target: target, text: text) else { return true }
        return !SelectionShape.looksLikeUnaccentedVietnamese(text)
            && trustsGuessOnUnaccentedText(confidence: confidence, wordCount: wordCount(of: text))
    }

    /// The Vietnamese user's text with no accents at all.
    static func appliesUnaccentedRules(target: Locale.Language, text: String) -> Bool {
        target.languageCode?.identifier == "vi" && text.unicodeScalars.allSatisfy(\.isASCII)
    }

    /// Text with no accents says little about its language, so a guess about it needs 0.9 and three words.
    static func trustsGuessOnUnaccentedText(confidence: Double, wordCount: Int) -> Bool {
        confidence >= 0.9 && wordCount >= 3
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
