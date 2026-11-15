import AVFoundation
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
    var onVoicesChanged: (() -> Void)?
    private(set) var spoken: [Utterance] = []
    private(set) var stops = 0
    private(set) var voiceLoads = 0
    /// When true, listing the voices waits for `releaseVoices()`, like a slow system call. The list is the one the
    /// system had when the call started, as for the real one.
    var holdsVoices = false
    private var heldVoices: [(list: [SpeechVoice], resume: CheckedContinuation<[SpeechVoice], Never>)] = []
    /// Set when something was spoken while another utterance was still going.
    private(set) var overlapped = false
    private(set) var active: Utterance?

    func availableVoices() async -> [SpeechVoice] {
        voiceLoads += 1
        let listed = voices
        guard holdsVoices else { return listed }
        return await withCheckedContinuation { heldVoices.append((listed, $0)) }
    }

    /// Lets the listing at `index` of those in flight finish.
    func releaseVoices(at index: Int) {
        let held = heldVoices.remove(at: index)
        held.resume.resume(returning: held.list)
    }

    /// Lets every listing in flight finish, oldest first.
    func releaseVoices() {
        while !heldVoices.isEmpty { releaseVoices(at: 0) }
    }

    /// The system installed or removed a voice.
    func changeVoices(to list: [SpeechVoice]) {
        voices = list
        onVoicesChanged?()
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

    /// The voices are listed in the background when the tab appears; tests wait for that.
    func ready() async {
        await player.loadVoices().value
    }

    @Test func speaksTheTextInAVoiceOfItsLanguage() async {
        await ready()
        player.toggle(.original, text: "Hello", language: .en)
        #expect(synthesizer.spoken == [.init(text: "Hello", voice: "voice.en")])
        #expect(player.speaking == .original)
        player.stop()
        player.toggle(.translation, text: "Xin chào", language: .vi)
        #expect(synthesizer.spoken.last == .init(text: "Xin chào", voice: "voice.vi"))
        #expect(player.speaking == .translation)
    }

    @Test func tappingTheSameButtonAgainStops() async {
        await ready()
        player.toggle(.translation, text: "Xin chào", language: .vi)
        player.toggle(.translation, text: "Xin chào", language: .vi)
        #expect(player.speaking == nil)
        #expect(synthesizer.active == nil)
        #expect(synthesizer.spoken.count == 1)
        #expect(synthesizer.stops == 1)
    }

    @Test func onlyOneUtteranceAtATime() async {
        await ready()
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

    @Test func endingOnItsOwnClearsTheState() async {
        await ready()
        player.toggle(.original, text: "Hello", language: .en)
        synthesizer.finish()
        #expect(player.speaking == nil)
        // The next tap speaks again instead of counting as the one that stops.
        player.toggle(.original, text: "Hello", language: .en)
        #expect(player.speaking == .original)
        #expect(synthesizer.spoken.count == 2)
    }

    @Test func stopSilencesAndIsHarmlessWhenIdle() async {
        await ready()
        player.stop()
        #expect(synthesizer.stops == 0)
        player.toggle(.original, text: "Hello", language: .en)
        player.stop()
        #expect(player.speaking == nil)
        #expect(synthesizer.active == nil)
        #expect(synthesizer.stops == 1)
    }

    @Test func blankTextAndUnknownLanguagesSpeakNothing() async {
        await ready()
        player.toggle(.original, text: "  \n", language: .en)
        player.toggle(.original, text: "Hello", language: nil)
        player.toggle(.original, text: "こんにちは", language: .ja)
        #expect(synthesizer.spoken.isEmpty)
        #expect(player.speaking == nil)
    }

    @Test func aFailedTapStillSilencesTheOtherButton() async {
        await ready()
        player.toggle(.original, text: "Hello", language: .en)
        player.toggle(.translation, text: "こんにちは", language: .ja)
        #expect(player.speaking == nil)
        #expect(synthesizer.active == nil)
    }

    @Test func knowsWhichLanguagesHaveAVoice() async {
        await ready()
        #expect(player.canSpeak(.en))
        #expect(player.canSpeak(.vi))
        #expect(!player.canSpeak(.ja))
        #expect(!player.canSpeak(nil))
    }

    @Test func voicesAreListedOnceInTheBackgroundAndNeverBlockTheCaller() async {
        synthesizer.holdsVoices = true
        let first = player.loadVoices()
        // The caller has its turn back while the system call is still going, and nothing can be read yet.
        #expect(!player.canSpeak(.en))
        player.toggle(.original, text: "Hello", language: .en)
        #expect(synthesizer.spoken.isEmpty)
        #expect(player.speaking == nil)
        // Another appearance of the tab while that is going on starts nothing new.
        let second = player.loadVoices()
        await eventually { synthesizer.voiceLoads == 1 }

        synthesizer.releaseVoices()
        await first.value
        await second.value
        #expect(player.canSpeak(.en))
        #expect(synthesizer.voiceLoads == 1)

        // And once loaded they stay: later appearances read nothing.
        await player.loadVoices().value
        await player.loadVoices().value
        #expect(synthesizer.voiceLoads == 1)
        player.toggle(.original, text: "Hello", language: .en)
        #expect(player.speaking == .original)
    }

    @Test func aListThatCameBackEmptyIsAskedForAgain() async {
        synthesizer.voices = []
        await ready()
        #expect(!player.canSpeak(.en))
        synthesizer.voices = [SpeechVoice(identifier: "voice.en", language: "en-US", quality: 1, isNovelty: false)]
        await ready()
        #expect(player.canSpeak(.en))
        #expect(synthesizer.voiceLoads == 2)
    }

    @Test func aVoiceInstalledWhileRunningIsPickedUp() async {
        synthesizer.voices = [SpeechVoice(identifier: "voice.vi", language: "vi-VN", quality: 1, isNovelty: false)]
        await ready()
        #expect(!player.canSpeak(.en))
        synthesizer.changeVoices(to: [
            SpeechVoice(identifier: "voice.vi", language: "vi-VN", quality: 1, isNovelty: false),
            SpeechVoice(identifier: "voice.en", language: "en-US", quality: 1, isNovelty: false),
        ])
        await ready()
        #expect(player.canSpeak(.en))
        #expect(synthesizer.voiceLoads == 2)
    }

    @Test func aVoiceRemovedWhileRunningStopsEnablingTheButton() async {
        await ready()
        #expect(player.canSpeak(.en))
        synthesizer.changeVoices(to: [SpeechVoice(identifier: "voice.vi", language: "vi-VN", quality: 1, isNovelty: false)])
        await ready()
        #expect(!player.canSpeak(.en))
        #expect(player.canSpeak(.vi))
    }

    @Test func voicesChangingBeforeAnyAppearanceListNothing() async {
        synthesizer.changeVoices(to: [])
        await settle()
        #expect(synthesizer.voiceLoads == 0)
    }

    @Test func aListOvertakenByAChangeNeverReplacesTheNewerOne() async {
        let vi = SpeechVoice(identifier: "voice.vi", language: "vi-VN", quality: 1, isNovelty: false)
        let en = SpeechVoice(identifier: "voice.en", language: "en-US", quality: 1, isNovelty: false)
        synthesizer.voices = [vi]
        synthesizer.holdsVoices = true
        let first = player.loadVoices()
        await eventually { synthesizer.voiceLoads == 1 }
        // An English voice is installed while the first listing, which started without it, is still going.
        synthesizer.changeVoices(to: [vi, en])
        await eventually { synthesizer.voiceLoads == 2 }
        // The newer listing ends first, then the older one reports what it saw.
        synthesizer.releaseVoices(at: 1)
        await eventually { player.canSpeak(.en) }
        synthesizer.releaseVoices(at: 0)
        await first.value
        await settle()
        #expect(player.canSpeak(.en))
    }
}

@Suite struct SpeechModuleTests {
    let fixture = ModuleFixture()

    @Test func stoppingTheModuleSilencesTheVoice() async {
        await fixture.start()
        await fixture.module.speech.loadVoices().value
        fixture.module.speech.toggle(.translation, text: "Xin chào", language: .vi)
        #expect(fixture.synthesizer.active != nil)
        await fixture.harness.registry.setEnabled(false, for: "translation")
        #expect(fixture.synthesizer.active == nil)
        #expect(fixture.module.speech.speaking == nil)
    }
}

@Suite struct SystemSpeechSynthesizerTests {
    @Test func listsTheSystemVoicesWithoutSpeaking() async {
        let voices = await SystemSpeechSynthesizer().availableVoices()
        #expect(voices.allSatisfy { !$0.identifier.isEmpty && !$0.language.isEmpty && (1...3).contains($0.quality) })
    }

    @Test func reportsVoicesInstalledOrRemoved() {
        let center = NotificationCenter()
        let synthesizer = SystemSpeechSynthesizer(notifications: center)
        nonisolated(unsafe) var changes = 0
        synthesizer.onVoicesChanged = { changes += 1 }
        center.post(name: .init("SomethingElse"), object: nil)
        #expect(changes == 0)
        center.post(name: AVSpeechSynthesizer.availableVoicesDidChangeNotification, object: nil)
        #expect(changes == 1)
    }
}
