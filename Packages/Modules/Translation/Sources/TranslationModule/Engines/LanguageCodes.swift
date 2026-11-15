import Foundation

/// Each service's names for the languages: BCP-47 from the Translation framework ("en-GB", "zh-Hant") to what it takes.
nonisolated enum LanguageCodes {
    private static let english = Locale(identifier: "en_US")

    /// Cloud Translation v2: the language alone, and "zh-CN" or "zh-TW" for Chinese.
    static func google(_ language: Locale.Language) -> String {
        switch code(of: language) {
        case "zh": isTraditional(language) ? "zh-TW" : "zh-CN"
        case "nb": "no"
        case let code: code
        }
    }

    /// Translator v3: the language alone, "zh-Hans" or "zh-Hant" for Chinese, and "pt-pt" for Portugal.
    static func microsoft(_ language: Locale.Language) -> String {
        switch code(of: language) {
        case "zh": isTraditional(language) ? "zh-Hant" : "zh-Hans"
        case "pt": language.region?.identifier == "PT" ? "pt-pt" : "pt"
        case let code: code
        }
    }

    /// For a model, which reads names: "Vietnamese", "British English".
    static func englishName(_ language: Locale.Language) -> String {
        english.localizedString(forIdentifier: language.minimalIdentifier) ?? language.minimalIdentifier
    }

    private static func code(of language: Locale.Language) -> String {
        language.languageCode?.identifier ?? language.minimalIdentifier
    }

    /// Hong Kong and Taiwan write Chinese in traditional characters, as "zh-Hant" does; a bare "zh" is simplified.
    private static func isTraditional(_ language: Locale.Language) -> Bool {
        language.maximalIdentifier.contains("Hant")
    }
}
