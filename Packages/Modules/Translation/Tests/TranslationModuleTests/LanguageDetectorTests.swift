import Foundation
import Testing
@testable import TranslationModule

@Suite struct LanguageDetectorTests {
    let detector = LanguageDetector()
    let vi = Locale.Language(identifier: "vi")
    let en = Locale.Language(identifier: "en")
    let ja = Locale.Language(identifier: "ja")
    let de = Locale.Language(identifier: "de")
    /// `LanguageAvailability().supportedLanguages` on macOS 26.5.
    let supported = [
        "ar-AE", "da", "de", "de-CH", "en", "en-AU", "en-CA", "en-GB", "en-IE", "en-IN", "en-NZ", "en-SG", "en-ZA",
        "es", "es-MX", "es-US", "fr", "fr-CA", "hi", "id", "it", "it-CH", "ja", "ko", "nb", "nl", "pl", "pt", "pt-PT",
        "ru", "sv", "th", "tr", "uk", "vi", "zh", "zh-HK", "zh-TW",
    ].map(Locale.Language.init(identifier:))

    @Test func detectsVietnameseAndEnglish() throws {
        let vietnamese = try #require(detector.detect("Xin chào, hôm nay trời đẹp quá", among: [vi, en]))
        #expect(vietnamese.language == vi)
        #expect(vietnamese.confidence > 0.9)
        let english = try #require(detector.detect("Hello, how are you today?", among: [vi, en]))
        #expect(english.language == en)
        #expect(english.confidence > 0.9)
    }

    @Test func mixedTextFollowsTheDominantLanguage() {
        #expect(detector.detect("Meeting lúc 3 giờ chiều nhé", among: [vi, en])?.language == vi)
        #expect(detector.detect("OK thanks, see you", among: [vi, en])?.language == en)
    }

    @Test func onlyTheCandidatesAreConsidered() {
        let german = "Guten Morgen, wie geht es dir heute?"
        #expect(detector.detect(german, among: supported)?.language == de)
        let constrained = detector.detect(german, among: [vi, en])?.language
        #expect(constrained == nil || [vi, en].contains(constrained))
    }

    @Test func returnsTheCandidateThatWasPassedIn() {
        let british = Locale.Language(identifier: "en-GB")
        #expect(detector.detect("Hello, how are you today?", among: [vi, british])?.language == british)
        let simplified = Locale.Language(identifier: "zh")
        let traditional = Locale.Language(identifier: "zh-TW")
        #expect(detector.detect("我们今天去公园散步，天气很好。", among: [simplified, traditional])?.language == simplified)
        #expect(detector.detect("我們今天去公園散步，天氣很好。", among: [simplified, traditional])?.language == traditional)
    }

    @Test func shortOrLetterlessTextIsNotDetected() {
        #expect(detector.detect("", among: [vi, en]) == nil)
        #expect(detector.detect("a", among: [vi, en]) == nil)
        #expect(detector.detect("42 !!", among: [vi, en]) == nil)
    }

    @Test func textOutsideTheCandidatesIsNotDetected() {
        #expect(detector.detect("こんにちは、元気ですか", among: [vi, en]) == nil)
        #expect(detector.detect("Hello, how are you today?", among: []) == nil)
    }

    @Test func detectedLanguageBecomesTheSource() {
        let english = direction("Hello, how are you today?", target: vi, lastSource: ja)
        #expect(english.source == en)
        #expect(english.target == vi)
        let german = direction("Guten Morgen, wie geht es dir heute?", target: vi, lastSource: en)
        #expect(german.source == de)
        #expect(german.target == vi)
    }

    @Test func lowConfidenceFallsBackToTheLastSource() {
        let unsure = LanguageDetector.resolveDirection(detected: (en, 0.4), preferredPair: (vi, en), target: vi, lastSource: ja)
        #expect(unsure.source == ja)
        #expect(unsure.target == vi)
        // Among every supported language "Hi" is only a weak guess.
        let greeting = direction("Hi", target: vi, lastSource: en)
        #expect(greeting.source == en)
        #expect(greeting.target == vi)
        let undetectable = direction("42", target: vi, lastSource: en)
        #expect(undetectable.source == en)
        #expect(undetectable.target == vi)
    }

    @Test func confidenceOfOneHalfIsEnough() {
        #expect(LanguageDetector.resolveDirection(detected: (en, 0.5), preferredPair: (vi, en), target: vi, lastSource: ja).source == en)
        #expect(LanguageDetector.resolveDirection(detected: (en, 0.4999), preferredPair: (vi, en), target: vi, lastSource: ja).source == ja)
    }

    @Test func withoutDetectionOrHistoryTheSourceIsThePairsOtherLanguage() {
        let toVietnamese = direction("", target: vi, lastSource: nil)
        #expect(toVietnamese.source == en)
        #expect(toVietnamese.target == vi)
        let toEnglish = direction("", target: en, lastSource: nil)
        #expect(toEnglish.source == vi)
        #expect(toEnglish.target == en)
    }

    @Test func sourceEqualToTheTargetFlipsTheTarget() {
        let detected = direction("Xin chào, hôm nay trời đẹp quá", target: vi, lastSource: en)
        #expect(detected.source == vi)
        #expect(detected.target == en)
        let remembered = LanguageDetector.resolveDirection(detected: nil, preferredPair: (vi, en), target: en, lastSource: en)
        #expect(remembered.source == en)
        #expect(remembered.target == vi)
    }

    @Test func flipComparesTheWrittenLanguageNotTheRegion() {
        let english = direction("Hello, how are you today?", target: Locale.Language(identifier: "en-GB"), lastSource: nil)
        #expect(english.source == en)   // the pair's language, not one of the supported English variants
        #expect(english.target == vi)
    }

    @Test func targetOutsideThePairFlipsToThePairsFirstLanguage() {
        let japanese = direction("こんにちは、元気ですか", target: ja, lastSource: nil)
        #expect(japanese.source == ja)
        #expect(japanese.target == vi)
    }

    private func direction(_ text: String, target: Locale.Language, lastSource: Locale.Language?) -> (source: Locale.Language, target: Locale.Language) {
        detector.resolveDirection(text: text, candidates: supported, preferredPair: (vi, en), target: target, lastSource: lastSource)
    }
}
