import Foundation
import NaturalLanguage

/// Guesses the language of typed or selected text and picks the translation direction from it.
nonisolated struct LanguageDetector: Sendable {
    /// Below this the guess is too unreliable to override the language the user picked last.
    static let minimumConfidence = 0.5

    /// The most likely of `candidates`, or nil for text with fewer than two letters or in none of them.
    /// Returns the candidate itself (e.g. "en-GB"), not the plain language Natural Language reports.
    func detect(_ text: String, among candidates: [Locale.Language]) -> (language: Locale.Language, confidence: Double)? {
        guard text.lazy.filter(\.isLetter).prefix(2).count == 2 else { return nil }
        let languages = candidates.compactMap(Self.writtenLanguage(of:))
        guard !languages.isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = Array(Set(languages))
        recognizer.processString(text)
        guard let (best, confidence) = recognizer.languageHypotheses(withMaximum: 1).max(by: { $0.value < $1.value }),
              let language = candidates.first(where: { Self.writtenLanguage(of: $0) == best }) else { return nil }
        return (language, confidence)
    }

    /// Direction for `text`: the detected language, else the source used last, else the pair's other language.
    /// When the source is the target's language, the target flips to the other language of the preferred pair,
    /// so Vietnamese text with target Vietnamese translates to English.
    func resolveDirection(
        text: String,
        preferredPair: (Locale.Language, Locale.Language),
        target: Locale.Language,
        lastSource: Locale.Language?
    ) -> (source: Locale.Language, target: Locale.Language) {
        // Only the languages the user works with, so a short phrase isn't mistaken for an unrelated language.
        let candidates = [preferredPair.0, preferredPair.1, target] + (lastSource.map { [$0] } ?? [])
        return Self.resolveDirection(detected: detect(text, among: candidates), preferredPair: preferredPair, target: target, lastSource: lastSource)
    }

    /// The rule itself, given a detection result; separate so every confidence level is testable.
    static func resolveDirection(
        detected: (language: Locale.Language, confidence: Double)?,
        preferredPair: (Locale.Language, Locale.Language),
        target: Locale.Language,
        lastSource: Locale.Language?
    ) -> (source: Locale.Language, target: Locale.Language) {
        let confident = detected.flatMap { $0.confidence >= minimumConfidence ? $0.language : nil }
        let source = confident ?? lastSource ?? other(than: target, in: preferredPair)
        return (source, isSameLanguage(source, target) ? other(than: source, in: preferredPair) : target)
    }

    /// The pair's language that isn't `language`; the pair's first one when `language` is outside the pair.
    private static func other(than language: Locale.Language, in pair: (Locale.Language, Locale.Language)) -> Locale.Language {
        isSameLanguage(language, pair.0) ? pair.1 : pair.0
    }

    /// Regional variants ("en", "en-GB") count as the same language; Chinese scripts do not.
    private static func isSameLanguage(_ lhs: Locale.Language, _ rhs: Locale.Language) -> Bool {
        lhs == rhs || writtenLanguage(of: lhs).map { $0 == writtenLanguage(of: rhs) } ?? false
    }

    /// Natural Language names Chinese by script ("zh-Hans", "zh-Hant") and every other language by its code.
    private static func writtenLanguage(of language: Locale.Language) -> NLLanguage? {
        guard let code = language.languageCode?.identifier else { return nil }
        guard code == "zh" else { return NLLanguage(rawValue: code) }
        return language.script?.identifier == "Hant" ? .traditionalChinese : .simplifiedChinese
    }
}
