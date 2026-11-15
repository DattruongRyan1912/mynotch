import Foundation

/// The OCR language setting as a multi-select: identifiers are stored as the user picked them, and a language
/// counts as selected when `OCRService` would match one of them to it.
nonisolated enum OCRLanguages {
    /// Settings rows are in Vietnamese, so language names are too.
    private static let locale = Locale(identifier: "vi")

    static func isSelected(_ language: Locale.Language, in selected: [String], supported: [Locale.Language]) -> Bool {
        OCRService.recognitionLanguages(for: selected, supported: supported).contains(language)
    }

    /// `selected` with `language` added, or with every identifier that matches it removed.
    static func toggling(_ language: Locale.Language, in selected: [String], supported: [Locale.Language]) -> [String] {
        guard isSelected(language, in: selected, supported: supported) else {
            return selected + [language.maximalIdentifier]
        }
        return selected.filter { !OCRService.recognitionLanguages(for: [$0], supported: supported).contains(language) }
    }

    /// "Tiếng Việt", "Tiếng Trung (Đài Loan)"; the raw identifier when the system has no name for it.
    static func name(of language: Locale.Language) -> String {
        locale.localizedString(forIdentifier: language.minimalIdentifier)
            ?? language.languageCode.flatMap { locale.localizedString(forLanguageCode: $0.identifier) }
            ?? language.maximalIdentifier
    }

    /// The names of the selected languages, or "Tự động" when none is (Vision then picks its own).
    static func summary(of selected: [String], supported: [Locale.Language]) -> String {
        let names = OCRService.recognitionLanguages(for: selected, supported: supported).map(name(of:))
        return names.isEmpty ? "Tự động" : names.joined(separator: ", ")
    }
}
