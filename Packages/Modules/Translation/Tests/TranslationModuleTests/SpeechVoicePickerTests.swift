import Foundation
import Testing
@testable import TranslationModule

@Suite struct SpeechVoicePickerTests {
    func voice(_ language: String, name: String = "Voice", quality: Int = 1, novelty: Bool = false) -> SpeechVoice {
        SpeechVoice(identifier: "com.apple.voice.compact.\(language).\(name)", language: language, quality: quality, isNovelty: novelty)
    }

    func pick(_ language: String, from voices: [SpeechVoice], systemRegion: String? = nil) -> SpeechVoice? {
        SpeechVoicePicker.pick(for: Locale.Language(identifier: language), from: voices, systemRegion: systemRegion)
    }

    @Test func picksAVoiceOfTheLanguageAndNeverAnotherOne() {
        let vietnamese = voice("vi-VN")
        #expect(pick("vi", from: [voice("en-US"), vietnamese, voice("ja-JP")]) == vietnamese)
        #expect(pick("vi", from: [voice("en-US"), voice("ja-JP")]) == nil)
        #expect(pick("vi", from: []) == nil)
    }

    @Test func aRegionTheLanguageNamesWins() {
        let british = voice("en-GB")
        #expect(pick("en-GB", from: [voice("en-US"), british, voice("en-AU")]) == british)
        // Even over a better voice of another region.
        #expect(pick("en-GB", from: [voice("en-US", quality: 3), british]) == british)
        // Without that region, another one of the language still reads it.
        #expect(pick("en-IN", from: [voice("en-US"), voice("vi-VN")]) == voice("en-US"))
    }

    @Test func aLanguageWithoutRegionPrefersTheSystemRegionThenTheUsualOne() {
        let american = voice("en-US")
        let australian = voice("en-AU")
        #expect(pick("en", from: [american, australian], systemRegion: "AU") == australian)
        #expect(pick("en", from: [australian, american], systemRegion: "VN") == american)
        #expect(pick("en", from: [australian, american]) == american)
        #expect(pick("es", from: [voice("es-MX"), voice("es-ES")], systemRegion: "MX") == voice("es-MX"))
    }

    @Test func chineseFollowsItsScript() {
        let mainland = voice("zh-CN")
        let taiwan = voice("zh-TW")
        let hongKong = voice("zh-HK")
        #expect(pick("zh-Hans", from: [taiwan, hongKong, mainland]) == mainland)
        #expect(pick("zh", from: [taiwan, mainland]) == mainland)
        #expect(pick("zh-Hant", from: [mainland, hongKong, taiwan]) == taiwan)
        #expect(pick("zh-Hant", from: [mainland, hongKong]) == hongKong)
        #expect(pick("zh-HK", from: [mainland, taiwan, hongKong]) == hongKong)
    }

    @Test func betterQualityWinsInTheSameRegion() {
        let plain = voice("vi-VN", name: "Plain")
        let enhanced = voice("vi-VN", name: "Enhanced", quality: 2)
        let premium = voice("vi-VN", name: "Premium", quality: 3)
        #expect(pick("vi", from: [plain, premium, enhanced]) == premium)
        #expect(pick("vi", from: [plain, enhanced]) == enhanced)
    }

    @Test func noveltyVoicesAreNeverPicked() {
        let joke = voice("en-US", name: "Bad News", quality: 3, novelty: true)
        let normal = voice("en-US", name: "Samantha")
        #expect(pick("en", from: [joke, normal]) == normal)
        #expect(pick("en", from: [joke]) == nil)
    }

    @Test func systemVoicesComeBeforeOtherEnginesOnATie() {
        let eloquence = SpeechVoice(identifier: "com.apple.eloquence.en-US.Flo", language: "en-US", quality: 1, isNovelty: false)
        let system = voice("en-US", name: "Samantha")
        #expect(pick("en", from: [eloquence, system]) == system)
    }

    @Test func aFullTieIsBrokenByIdentifierSoThePickIsStable() {
        let first = voice("vi-VN", name: "A")
        let second = voice("vi-VN", name: "B")
        #expect(pick("vi", from: [second, first]) == first)
        #expect(pick("vi", from: [first, second]) == first)
    }

    @Test func aLanguageWithoutACodeHasNoVoice() {
        #expect(SpeechVoicePicker.pick(for: Locale.Language(identifier: ""), from: [voice("en-US")], systemRegion: nil) == nil)
    }
}
