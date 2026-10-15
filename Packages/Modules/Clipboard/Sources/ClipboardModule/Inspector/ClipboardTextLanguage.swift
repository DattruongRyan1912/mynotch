import Foundation
import NaturalLanguage

/// The language a prose text is written in, found on the Mac (Apple's language recognizer, no network), from the start of it only.
nonisolated enum ClipboardTextLanguage {
    /// How much of the start is read; more would not change the answer, and a copy can be megabytes.
    static let sampleCharacters = 1_000
    /// Fewer letters than this are too little to tell: "ok" could be in any language.
    static let minimumLetters = 12
    /// How sure the recognizer must be.
    static let minimumConfidence = 0.6

    /// The language code ("vi", "en", "zh-Hans"), or nil when the text is too short, has no letters to speak of, or is not clear.
    static func code(of text: String) -> String? {
        let sample = String(text.prefix(sampleCharacters))
        guard sample.count(where: \.isLetter) >= minimumLetters else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        guard let best = recognizer.languageHypotheses(withMaximum: 1).first, best.value >= minimumConfidence else { return nil }
        return best.key.rawValue
    }

    /// "Tiếng Việt", "Tiếng Anh": the language's name in Vietnamese; the code itself when the system has no name for it.
    static func name(forCode code: String) -> String {
        guard let name = Locale(identifier: "vi").localizedString(forLanguageCode: code), !name.isEmpty else { return code }
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}
