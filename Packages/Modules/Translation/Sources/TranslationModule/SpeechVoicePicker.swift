import Foundation

/// A system voice, reduced to what choosing one needs.
nonisolated struct SpeechVoice: Equatable, Sendable {
    var identifier: String
    /// BCP-47 as `AVSpeechSynthesisVoice` reports it: "en-US", "vi-VN", "zh-TW".
    var language: String
    /// `AVSpeechSynthesisVoiceQuality`'s raw value: 1 default, 2 enhanced, 3 premium.
    var quality: Int
    /// A joke voice ("Bad News", "Cellos") that nobody wants a translation read in.
    var isNovelty: Bool
}

/// Picks the voice that reads a text in its language. Pure, so every rule is testable without a synthesizer.
nonisolated enum SpeechVoicePicker {
    /// Identifier prefix of the voices macOS ships and downloads; the older engines' voices sound far worse.
    private static let systemVoicePrefix = "com.apple.voice."

    /// The best voice of `language`, or nil when none is installed. A voice of another language is never returned:
    /// it would read the text as gibberish. Within the language, in order of weight: the script (Chinese, so
    /// "zh-Hant" is read as Taiwan or Hong Kong, not mainland), the region (the one the language names, else the
    /// system's, else the language's usual one), quality, a system voice, then the identifier so the pick is stable.
    static func pick(for language: Locale.Language, from voices: [SpeechVoice], systemRegion: String? = Locale.current.region?.identifier) -> SpeechVoice? {
        guard let code = language.languageCode?.identifier else { return nil }
        let wanted = maximal(language)
        let regions = language.region.map { [$0.identifier] } ?? [systemRegion, wanted.region?.identifier].compactMap { $0 }
        return voices
            .filter { !$0.isNovelty && Locale.Language(identifier: $0.language).languageCode?.identifier == code }
            .min { rank($0, wanted: wanted, regions: regions) < rank($1, wanted: wanted, regions: regions) }
    }

    private static func rank(_ voice: SpeechVoice, wanted: Locale.Language, regions: [String]) -> (Int, Int, Int, Int, String) {
        let spoken = maximal(Locale.Language(identifier: voice.language))
        return (
            spoken.script == wanted.script ? 0 : 1,
            spoken.region.flatMap { regions.firstIndex(of: $0.identifier) } ?? regions.count,
            -voice.quality,
            voice.identifier.hasPrefix(systemVoicePrefix) ? 0 : 1,
            voice.identifier
        )
    }

    /// With the script and region the language implies filled in: "zh" is "zh-Hans-CN", "zh-Hant" is "zh-Hant-TW".
    private static func maximal(_ language: Locale.Language) -> Locale.Language {
        Locale.Language(identifier: language.maximalIdentifier)
    }
}
