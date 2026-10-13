import Foundation
import Testing
@testable import TranslationModule

@Suite struct LanguageDetectorTests {
    let detector = LanguageDetector()
    let vi = Locale.Language(identifier: "vi")
    let en = Locale.Language(identifier: "en")
    let ja = Locale.Language(identifier: "ja")

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
        let direction = detector.resolveDirection(text: "Hello, how are you today?", preferredPair: (vi, en), target: vi, lastSource: ja)
        #expect(direction.source == en)
        #expect(direction.target == vi)
    }

    @Test func lowConfidenceFallsBackToTheLastSource() {
        let unsure = LanguageDetector.resolveDirection(detected: (en, 0.4), preferredPair: (vi, en), target: vi, lastSource: ja)
        #expect(unsure.source == ja)
        #expect(unsure.target == vi)
        let undetectable = detector.resolveDirection(text: "42", preferredPair: (vi, en), target: vi, lastSource: en)
        #expect(undetectable.source == en)
        #expect(undetectable.target == vi)
    }

    @Test func withoutDetectionOrHistoryTheSourceIsThePairsOtherLanguage() {
        let toVietnamese = detector.resolveDirection(text: "", preferredPair: (vi, en), target: vi, lastSource: nil)
        #expect(toVietnamese.source == en)
        #expect(toVietnamese.target == vi)
        let toEnglish = detector.resolveDirection(text: "", preferredPair: (vi, en), target: en, lastSource: nil)
        #expect(toEnglish.source == vi)
        #expect(toEnglish.target == en)
    }

    @Test func sourceEqualToTheTargetFlipsTheTarget() {
        let detected = detector.resolveDirection(text: "Xin chào, hôm nay trời đẹp quá", preferredPair: (vi, en), target: vi, lastSource: en)
        #expect(detected.source == vi)
        #expect(detected.target == en)
        let remembered = LanguageDetector.resolveDirection(detected: nil, preferredPair: (vi, en), target: en, lastSource: en)
        #expect(remembered.source == en)
        #expect(remembered.target == vi)
    }

    @Test func flipComparesTheWrittenLanguageNotTheRegion() {
        let british = Locale.Language(identifier: "en-GB")
        let direction = detector.resolveDirection(text: "Hello, how are you today?", preferredPair: (vi, en), target: british, lastSource: nil)
        #expect(direction.source == en)
        #expect(direction.target == vi)
    }

    @Test func targetOutsideThePairFlipsToThePairsFirstLanguage() {
        let direction = detector.resolveDirection(text: "こんにちは、元気ですか", preferredPair: (vi, en), target: ja, lastSource: nil)
        #expect(direction.source == ja)
        #expect(direction.target == vi)
    }
}
