import Foundation
// Translation predates Swift concurrency annotations; its types are only used on the main actor here.
@preconcurrency import Translation

/// Languages the Translation framework supports, sorted by Vietnamese name for the language menus.
/// The list is loaded once: it only changes with an OS update.
final class SupportedLanguages {
    private nonisolated static let vietnamese = Locale(identifier: "vi")
    private let load: @MainActor () async -> [Locale.Language]
    private var loaded: Task<[Locale.Language], Never>?

    init(load: @escaping @MainActor () async -> [Locale.Language] = { await LanguageAvailability().supportedLanguages }) {
        self.load = load
    }

    func all() async -> [Locale.Language] {
        if let loaded { return await loaded.value }
        let load = load
        let task = Task { Self.sorted(await load()) }
        loaded = task
        return await task.value
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
