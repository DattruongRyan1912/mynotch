import Foundation
import Observation

/// What the "Dịch" tab shows. Changed only by `Translator` and `TranslationModule`.
@Observable
final class TranslationState {
    /// A language-pack problem the tab explains instead of a result.
    enum Banner: Equatable {
        case notInstalled(LanguagePair)
        case unsupported
    }

    var input = ""
    var output = ""
    /// Chosen in the source menu; nil means "Tự nhận diện".
    var source: Locale.Language?
    var target = Locale.Language(identifier: "vi")
    /// What detection picked for the last translation while `source` is nil.
    var detectedSource: Locale.Language?
    /// Of the direction last translated; nil until a translation of it finished.
    var pairStatus: PairStatus?
    var isTranslating = false
    /// Why the last translation failed, other than a missing or unsupported language pack.
    var error: String?
    /// Every language Translation supports, for the menus; empty until loaded.
    var languages: [Locale.Language] = []
    /// Bumped whenever the module opens the tab; the input field takes focus on each change.
    var focusRequest = 0

    /// The direction shown in the menus, once the source is known.
    var currentPair: LanguagePair? {
        (source ?? detectedSource).map { LanguagePair(source: $0, target: target) }
    }

    var banner: Banner? {
        switch pairStatus {
        case .supported: currentPair.map(Banner.notInstalled)
        case .unsupported: .unsupported
        case .installed, nil: nil
        }
    }

    /// Swapping needs a source, so it waits for the first detection when the source is automatic.
    var canSwap: Bool { currentPair != nil }
}
