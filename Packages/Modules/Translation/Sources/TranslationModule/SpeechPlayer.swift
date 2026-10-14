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
    func availableVoices() -> [SpeechVoice]
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
    /// Read when first needed and when the tab appears, not at launch: listing the voices is not free.
    private var voices: [SpeechVoice] = []
    /// The pick for each language asked about: the buttons ask on every redraw, and picking weighs every voice.
    @ObservationIgnored private var picks: [Locale.Language: SpeechVoice?] = [:]

    init(synthesizer: any SpeechSynthesizing) {
        self.synthesizer = synthesizer
        synthesizer.onFinish = { [weak self] in self?.speaking = nil }
    }

    /// Whether a voice of `language` is installed, for enabling the button.
    func canSpeak(_ language: Locale.Language?) -> Bool {
        language.flatMap(voice(for:)) != nil
    }

    /// Voices can be installed in System Settings while the app runs.
    func refreshVoices() {
        voices = synthesizer.availableVoices()
        picks.removeAll()
    }

    /// The button's tap: reads `text`, or stops when this text is the one being read. Reading one text always stops the
    /// other, so two voices never overlap.
    func toggle(_ part: SpokenText, text: String, language: Locale.Language?) {
        if speaking == part {
            stop()
            return
        }
        stop()
        if voices.isEmpty { refreshVoices() }
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

    func availableVoices() -> [SpeechVoice] {
        AVSpeechSynthesisVoice.speechVoices().map {
            SpeechVoice(
                identifier: $0.identifier, language: $0.language, quality: $0.quality.rawValue,
                isNovelty: $0.voiceTraits.contains(.isNoveltyVoice)
            )
        }
    }

    func speak(_ text: String, voice: SpeechVoice) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(identifier: voice.identifier)
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
