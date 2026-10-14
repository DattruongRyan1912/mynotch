import Foundation
import Testing
@testable import TranslationModule

/// Speaks nothing: records what it is asked and plays the system's rule that only one utterance is ever active.
final class FakeSynthesizer: SpeechSynthesizing {
    struct Utterance: Equatable {
        var text: String
        var voice: String
    }

    var voices: [SpeechVoice] = [
        SpeechVoice(identifier: "voice.vi", language: "vi-VN", quality: 1, isNovelty: false),
        SpeechVoice(identifier: "voice.en", language: "en-US", quality: 1, isNovelty: false),
    ]
    var onFinish: (() -> Void)?
    private(set) var spoken: [Utterance] = []
    private(set) var stops = 0
    private(set) var voiceLoads = 0
    /// Set when something was spoken while another utterance was still going.
    private(set) var overlapped = false
    private(set) var active: Utterance?

    func availableVoices() -> [SpeechVoice] {
        voiceLoads += 1
        return voices
    }

    func speak(_ text: String, voice: SpeechVoice) {
        if active != nil { overlapped = true }
        let utterance = Utterance(text: text, voice: voice.identifier)
        spoken.append(utterance)
        active = utterance
    }

    func stop() {
        stops += 1
        active = nil
    }

    /// The utterance reaches its end on its own.
    func finish() {
        guard active != nil else { return }
        active = nil
        onFinish?()
    }
}

@Suite struct SpeechPlayerTests {
    let synthesizer = FakeSynthesizer()
    let player: SpeechPlayer

    init() {
        player = SpeechPlayer(synthesizer: synthesizer)
    }

    @Test func speaksTheTextInAVoiceOfItsLanguage() {
        player.toggle(.original, text: "Hello", language: .en)
        #expect(synthesizer.spoken == [.init(text: "Hello", voice: "voice.en")])
        #expect(player.speaking == .original)
        player.stop()
        player.toggle(.translation, text: "Xin chào", language: .vi)
        #expect(synthesizer.spoken.last == .init(text: "Xin chào", voice: "voice.vi"))
        #expect(player.speaking == .translation)
    }

    @Test func tappingTheSameButtonAgainStops() {
        player.toggle(.translation, text: "Xin chào", language: .vi)
        player.toggle(.translation, text: "Xin chào", language: .vi)
        #expect(player.speaking == nil)
        #expect(synthesizer.active == nil)
        #expect(synthesizer.spoken.count == 1)
        #expect(synthesizer.stops == 1)
    }

    @Test func onlyOneUtteranceAtATime() {
        player.toggle(.original, text: "Hello", language: .en)
        player.toggle(.translation, text: "Xin chào", language: .vi)
        #expect(player.speaking == .translation)
        #expect(synthesizer.active == .init(text: "Xin chào", voice: "voice.vi"))
        #expect(!synthesizer.overlapped)
        // Tapping the first again brings it back and stops the second.
        player.toggle(.original, text: "Hello", language: .en)
        #expect(player.speaking == .original)
        #expect(!synthesizer.overlapped)
        #expect(synthesizer.spoken.map(\.text) == ["Hello", "Xin chào", "Hello"])
    }

    @Test func endingOnItsOwnClearsTheState() {
        player.toggle(.original, text: "Hello", language: .en)
        synthesizer.finish()
        #expect(player.speaking == nil)
        // The next tap speaks again instead of counting as the one that stops.
        player.toggle(.original, text: "Hello", language: .en)
        #expect(player.speaking == .original)
        #expect(synthesizer.spoken.count == 2)
    }

    @Test func stopSilencesAndIsHarmlessWhenIdle() {
        player.stop()
        #expect(synthesizer.stops == 0)
        player.toggle(.original, text: "Hello", language: .en)
        player.stop()
        #expect(player.speaking == nil)
        #expect(synthesizer.active == nil)
        #expect(synthesizer.stops == 1)
    }

    @Test func blankTextAndUnknownLanguagesSpeakNothing() {
        player.toggle(.original, text: "  \n", language: .en)
        player.toggle(.original, text: "Hello", language: nil)
        player.toggle(.original, text: "こんにちは", language: .ja)
        #expect(synthesizer.spoken.isEmpty)
        #expect(player.speaking == nil)
    }

    @Test func aFailedTapStillSilencesTheOtherButton() {
        player.toggle(.original, text: "Hello", language: .en)
        player.toggle(.translation, text: "こんにちは", language: .ja)
        #expect(player.speaking == nil)
        #expect(synthesizer.active == nil)
    }

    @Test func knowsWhichLanguagesHaveAVoice() {
        player.refreshVoices()
        #expect(player.canSpeak(.en))
        #expect(player.canSpeak(.vi))
        #expect(!player.canSpeak(.ja))
        #expect(!player.canSpeak(nil))
    }

    @Test func voicesAreReadWhenFirstNeededAndAgainOnRefresh() {
        #expect(synthesizer.voiceLoads == 0)
        player.toggle(.original, text: "Hello", language: .en)
        #expect(synthesizer.voiceLoads == 1)
        player.toggle(.original, text: "Hello", language: .en)
        #expect(synthesizer.voiceLoads == 1)
        synthesizer.voices.append(SpeechVoice(identifier: "voice.ja", language: "ja-JP", quality: 1, isNovelty: false))
        #expect(!player.canSpeak(.ja))
        player.refreshVoices()
        #expect(player.canSpeak(.ja))
    }
}

@Suite struct SpeechModuleTests {
    let fixture = ModuleFixture()

    @Test func stoppingTheModuleSilencesTheVoice() async {
        await fixture.start()
        fixture.module.speech.toggle(.translation, text: "Xin chào", language: .vi)
        #expect(fixture.synthesizer.active != nil)
        await fixture.harness.registry.setEnabled(false, for: "translation")
        #expect(fixture.synthesizer.active == nil)
        #expect(fixture.module.speech.speaking == nil)
    }
}

@Suite struct SystemSpeechSynthesizerTests {
    @Test func listsTheSystemVoicesWithoutSpeaking() {
        let voices = SystemSpeechSynthesizer().availableVoices()
        #expect(voices.allSatisfy { !$0.identifier.isEmpty && !$0.language.isEmpty && (1...3).contains($0.quality) })
    }
}
