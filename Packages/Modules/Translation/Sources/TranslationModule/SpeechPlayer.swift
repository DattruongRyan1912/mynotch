import AVFoundation
import Observation

/// Which text of the tab is being read.
nonisolated enum SpokenText: Sendable {
    case original, translation
}

/// The speech calls `SpeechPlayer` makes, so tests never speak.
protocol SpeechSynthesizing: AnyObject {
    /// Called when the utterance last passed to `speak` ends on its own. Never for one that `stop` cut off, nor for an
    /// earlier one, so a late report cannot clear the state of the utterance that replaced it.
    var onFinish: (() -> Void)? { get set }
    /// Listing the voices is slow (about 0.15 s), so it must not run on the caller's actor.
    func availableVoices() async -> [SpeechVoice]
    func speak(_ text: String, voice: SpeechVoice)
    func stop()
}

/// Reads the original or the translation aloud, one at a time. The synthesizer is on-device and the rate is the
/// system's default.
@Observable
final class SpeechPlayer {
    /// What is being read now.
    private(set) var speaking: SpokenText?

    @ObservationIgnored private let synthesizer: any SpeechSynthesizing
    /// Listed in the background when the tab first appears, not at launch and not on every appearance: listing them
    /// takes a good tenth of a second.
    private var voices: [SpeechVoice] = []
    @ObservationIgnored private var loading: Task<Void, Never>?
    /// The pick for each language asked about: the buttons ask on every redraw, and picking weighs every voice.
    @ObservationIgnored private var picks: [Locale.Language: SpeechVoice?] = [:]

    init(synthesizer: any SpeechSynthesizing) {
        self.synthesizer = synthesizer
        synthesizer.onFinish = { [weak self] in self?.speaking = nil }
    }

    /// Whether a voice of `language` is installed, for enabling the button. False until the voices are listed.
    func canSpeak(_ language: Locale.Language?) -> Bool {
        language.flatMap(voice(for:)) != nil
    }

    /// Starts listing the system's voices in the background, once, and returns at once: the buttons stay off until
    /// the list arrives. Voices installed while MyNotch runs show up after it restarts. A list that came back empty
    /// (the system may still have been starting) is asked for again next time.
    @discardableResult
    func loadVoices() -> Task<Void, Never> {
        if let loading { return loading }
        let task = Task { [weak self, synthesizer] in
            let listed = await synthesizer.availableVoices()
            guard let self else { return }
            voices = listed
            picks.removeAll()
            if listed.isEmpty { loading = nil }
        }
        loading = task
        return task
    }

    /// The button's tap: reads `text`, or stops when this text is the one being read. Reading one text always stops the
    /// other, so two voices never overlap. Does nothing before the voices are listed, which the buttons do not allow.
    func toggle(_ part: SpokenText, text: String, language: Locale.Language?) {
        if speaking == part {
            stop()
            return
        }
        stop()
        guard !text.allSatisfy(\.isWhitespace), let language, let voice = voice(for: language) else { return }
        speaking = part
        synthesizer.speak(text, voice: voice)
    }

    private func voice(for language: Locale.Language) -> SpeechVoice? {
        if let known = picks[language] { return known }
        let voice = SpeechVoicePicker.pick(for: language, from: voices)
        picks.updateValue(voice, forKey: language)
        return voice
    }

    /// Also when the tab goes away or the module stops.
    func stop() {
        guard speaking != nil else { return }
        speaking = nil
        synthesizer.stop()
    }
}

/// `AVSpeechSynthesizer`, which speaks on the device with no network.
final class SystemSpeechSynthesizer: NSObject, SpeechSynthesizing, AVSpeechSynthesizerDelegate {
    var onFinish: (() -> Void)?

    private lazy var synthesizer: AVSpeechSynthesizer = {
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
        return synthesizer
    }()
    /// The utterance whose end counts. Cleared by `stop`, so the end the system reports for a cut-off one is ignored.
    private var current: AVSpeechUtterance?

    func availableVoices() async -> [SpeechVoice] {
        await Task.detached(priority: .utility) { Self.systemVoices() }.value
    }

    private nonisolated static func systemVoices() -> [SpeechVoice] {
        AVSpeechSynthesisVoice.speechVoices().map {
            SpeechVoice(
                identifier: $0.identifier, language: $0.language, quality: $0.quality.rawValue,
                isNovelty: $0.voiceTraits.contains(.isNoveltyVoice)
            )
        }
    }

    func speak(_ text: String, voice: SpeechVoice) {
        // A voice removed since it was listed would be replaced by the default one, which reads the wrong language.
        guard let systemVoice = AVSpeechSynthesisVoice(identifier: voice.identifier) else {
            onFinish?()
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = systemVoice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        current = utterance
        synthesizer.speak(utterance)
    }

    func stop() {
        current = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        ended(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        ended(utterance)
    }

    /// Delegate calls may come from any thread.
    private nonisolated func ended(_ utterance: AVSpeechUtterance) {
        let identity = ObjectIdentifier(utterance)
        Task { @MainActor in
            guard let current, ObjectIdentifier(current) == identity else { return }
            self.current = nil
            onFinish?()
        }
    }
}
