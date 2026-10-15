import Foundation
import NaturalLanguage
import Testing
@testable import TranslationModule

/// Which text is foreign enough to preview, with the real on-device recognizer on text it cannot mistake.
@Suite struct SelectionLanguageTests {
    let candidates: [Locale.Language] = [.vi, .en, .ja, Locale.Language(identifier: "zh-Hans")]

    // MARK: confidence

    @Test func aGuessIsTrustedFromSixTenths() {
        #expect(SelectionLanguage.pick(from: [.english: 0.6]) == .english)
        #expect(SelectionLanguage.pick(from: [.english: 0.59]) == nil)
        #expect(SelectionLanguage.pick(from: [.english: 0.55, .german: 0.4]) == nil)
        #expect(SelectionLanguage.pick(from: [.english: 0.7, .german: 0.3]) == .english)
        #expect(SelectionLanguage.pick(from: [:]) == nil)
    }

    @Test func theMostLikelyOfSeveralIsTheOneTested() {
        #expect(SelectionLanguage.pick(from: [.german: 0.3, .english: 0.65]) == .english)
    }

    @Test func recognisesObviousSentences() {
        #expect(SelectionLanguage.dominant(of: "The quick brown fox jumps over the lazy dog") == .english)
        #expect(SelectionLanguage.dominant(of: "Hôm nay trời đẹp quá, chúng ta đi dạo nhé") == .vietnamese)
        #expect(SelectionLanguage.dominant(of: "こんにちは、お元気ですか") == .japanese)
    }

    // MARK: enough to translate

    @Test(arguments: [
        ("Hello", false), ("Hello.", false), ("Hello world", true), ("Hello, world", true), ("  Hello  ", false),
        ("don't", false), ("12 34", false), ("你好吗", false), ("你好吗？", false), ("你好吗朋", true), ("今天天气很好我们去散步吧", true),
        ("こんにちは", true), ("カタカナ", true), ("안녕하세요", true), ("Bonjour tout le monde", true), ("", false),
    ])
    func needsTwoWordsOrFourCJKCharacters(text: String, enough: Bool) {
        #expect(SelectionLanguage.hasEnoughToTranslate(text) == enough, "\(text)")
    }

    // MARK: source language

    @Test func foreignTextHasItsLanguageAsTheSource() {
        #expect(SelectionLanguage.source(of: "The quick brown fox jumps over the lazy dog", target: .vi, candidates: candidates) == .en)
        #expect(SelectionLanguage.source(of: "こんにちは世界、お元気ですか", target: .vi, candidates: candidates) == .ja)
    }

    @Test func textInTheTargetLanguageHasNoSource() {
        #expect(SelectionLanguage.source(of: "Hôm nay trời đẹp quá, chúng ta đi dạo nhé", target: .vi, candidates: candidates) == nil)
    }

    @Test func aRegionalVariantOfTheTargetIsTheSameLanguage() {
        let british = Locale.Language(identifier: "en-GB")
        #expect(SelectionLanguage.source(of: "The quick brown fox jumps over the lazy dog", target: british, candidates: candidates) == nil)
    }

    @Test func aLanguageThatCannotBeTranslatedHasNoSource() {
        #expect(SelectionLanguage.source(of: "The quick brown fox jumps over the lazy dog", target: .vi, candidates: [.vi, .ja]) == nil)
    }

    @Test func tooLittleTextHasNoSource() {
        #expect(SelectionLanguage.source(of: "Hello", target: .vi, candidates: candidates) == nil)
        #expect(SelectionLanguage.source(of: "你好吗", target: .vi, candidates: candidates) == nil)
    }

    @Test func theFirstCandidateOfTheLanguageIsTheSource() {
        let british = Locale.Language(identifier: "en-GB")
        #expect(SelectionLanguage.source(of: "The quick brown fox jumps over the lazy dog", target: .vi, candidates: [.vi, .en, british]) == .en)
        #expect(SelectionLanguage.source(of: "The quick brown fox jumps over the lazy dog", target: .vi, candidates: [british, .en]) == british)
    }

    @Test func chineseIsToldByScript() {
        let simplified = Locale.Language(identifier: "zh-Hans")
        let traditional = Locale.Language(identifier: "zh-Hant")
        #expect(SelectionLanguage.source(of: "今天天气很好，我们一起去公园散步吧", target: .vi, candidates: [.vi, simplified]) == simplified)
        #expect(SelectionLanguage.source(of: "今天天气很好，我们一起去公园散步吧", target: traditional, candidates: [traditional, simplified]) == simplified)
        #expect(SelectionLanguage.source(of: "今天天气很好，我们一起去公园散步吧", target: simplified, candidates: [traditional, simplified]) == nil)
    }
}
