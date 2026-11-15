import Foundation

/// A translation direction. Languages are BCP-47 `Locale.Language`s such as "vi" or "en-GB".
nonisolated struct LanguagePair: Hashable, Sendable {
    var source: Locale.Language
    var target: Locale.Language
}
