import Foundation
// `LanguageAvailability` isn't Sendable; each one is created for a single call and never shared.
@preconcurrency import Translation

/// Languages the Translation framework supports, sorted by Vietnamese name for the language menus.
/// The list is loaded once, since it only changes with an OS update; an empty answer is asked for again.
final class SupportedLanguages {
    private nonisolated static let vietnamese = Locale(identifier: "vi")
    private let load: @MainActor () async -> [Locale.Language]
    private var loaded: Task<[Locale.Language], Never>?

    init(load: @escaping @MainActor () async -> [Locale.Language] = { await LanguageAvailability().supportedLanguages }) {
        self.load = load
    }

    func all() async -> [Locale.Language] {
        let load = load
        let task = loaded ?? Task { Self.sorted(await load()) }
        loaded = task
        let languages = await task.value
        if languages.isEmpty, loaded == task { loaded = nil }
        return languages
    }

    /// Menu title, e.g. "Tiếng Anh (Vương quốc Anh)".
    nonisolated static func name(of language: Locale.Language) -> String {
        vietnamese.localizedString(forIdentifier: language.minimalIdentifier) ?? language.minimalIdentifier
    }

    private nonisolated static func sorted(_ languages: [Locale.Language]) -> [Locale.Language] {
        languages
            .map { (name: name(of: $0), language: $0) }
            .sorted { $0.name.compare($1.name, locale: vietnamese) == .orderedAscending }
            .map(\.language)
    }
}
