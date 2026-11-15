import Foundation
import MyNotchCore

/// What a selection is worth showing: its conversion when it is a quantity, a calculation or a zoned time, else a preview
/// of its translation when it is in another language (or just a "Dịch" button when the preview cannot be made), else nothing.
///
/// The preview is made by Apple's on-device engine only: the type of `preview` is `OnDeviceTranslationEngine`, which no
/// engine that needs a key conforms to, so the text of a selection cannot leave the Mac from here; the engine the user chose
/// runs when they open the result.
final class SelectionDecider {
    /// The most of a selection an automatic preview translates: it runs for every foreign selection in every app, and the chip is
    /// up for a few seconds, so it cannot be read in full past about this much. "Mở" translates all of it.
    static let previewLimit = 600

    private let converter: QuickConverter
    private let preview: any OnDeviceTranslationEngine
    private let languages: SupportedLanguages
    private let settings: ModuleSettings
    private let keys: TranslationKeys

    init(converter: QuickConverter, preview: any OnDeviceTranslationEngine, languages: SupportedLanguages, settings: ModuleSettings) {
        self.converter = converter
        self.preview = preview
        self.languages = languages
        self.settings = settings
        keys = TranslationKeys(settings)
    }

    /// What to show for a selection, or why nothing.
    func decide(for source: SelectionSource) async -> SelectionDecision {
        let normalizedText = SelectionShape.normalizeGluedSentences(source.text)
        let normalizedSource = SelectionSource(text: normalizedText, application: source.application)
        let text = normalizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .skip(.blank) }
        // Quick convert first: a clear quantity is shown converted, whatever language the rest is in. A price waits for the
        // day's rates, which are the only thing fetched, and no text goes with the request.
        if QuickConverter.mightHaveQuantities(text) {
            let plan = await converter.plan(for: text)
            if !plan.conversions.isEmpty {
                let conversions = await converter.resolve(plan)
                guard !Task.isCancelled else { return .skip(.cancelled) }
                guard let line = conversions.lazy.compactMap(SelectionHint.conversionText).first else { return .skip(.noConversion) }
                return .hint(SelectionHint(kind: .conversion, text: SelectionHint.shortened(line), source: normalizedSource))
            }
        }
        return await translation(of: text, from: normalizedSource)
    }

    /// The hint `decide` found, if any.
    func hint(for source: SelectionSource) async -> SelectionHint? {
        if case .hint(let hint, _) = await decide(for: source) { hint } else { nil }
    }

    private func translation(of text: String, from source: SelectionSource) async -> SelectionDecision {
        let target = Locale.Language(identifier: settings.value(keys.targetLanguage))
        let preferred = settings.value(keys.preferredPair).languages
        let candidates = [preferred.0, preferred.1, target] + (await languages.all())
        let assessment = await SelectionLanguage.assessInBackground(text, target: target, candidates: candidates)
        guard !Task.isCancelled else { return .skip(.cancelled) }
        let from: Locale.Language
        switch assessment {
        case .skip(let reason): return .skip(reason)
        case .source(let language): from = language
        }
        let cut = Self.previewCut(of: text, limit: Self.previewLimit)
        let result: Result<String, TranslationFailure>
        do throws(TranslationFailure) {
            result = .success(try await preview.translate(cut.text, from: from, to: target))
        } catch {
            result = .failure(error)
        }
        guard !Task.isCancelled else { return .skip(.cancelled) }
        switch result {
        case .success(let translated):
            // Nothing readable came back, which is as good as a failure: the text is foreign, so the button is still offered.
            let whole = translated.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !whole.isEmpty else { return button(for: source, failure: .error) }
            // A translation of the start only says so: it ends with an ellipsis and the chip notes that "Mở" does the rest.
            return .hint(SelectionHint(
                kind: .translation, text: cut.wasCut ? whole + "…" : whole, source: source, note: cut.wasCut ? SelectionHint.partialNote : nil
            ))
        case .failure(.cancelled): return .skip(.cancelled)
        case .failure(.notInstalled): return button(for: source, failure: .notInstalled)
        case .failure(.unsupported): return button(for: source, failure: .unsupported)
        case .failure(.failed): return button(for: source, failure: .error)
        }
    }

    /// The start of `text` that the preview translates: all of it up to `limit` characters, else up to the last sentence end (a
    /// full stop, a question or exclamation mark, a line break or the Chinese and Japanese full stop) in the second half of the
    /// window, else up to the last space, else the first `limit` characters. Trimmed.
    static func previewCut(of text: String, limit: Int) -> (text: String, wasCut: Bool) {
        let whole = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard whole.count > limit else { return (whole, false) }
        let characters = Array(whole)
        let half = limit / 2
        // Candidate ends, as the number of characters kept.
        var sentenceEnd: Int?
        var wordEnd: Int?
        for index in 0..<limit {
            let character = characters[index]
            if "。！？".contains(character) || (".!?".contains(character) && characters[index + 1].isWhitespace) {
                if index + 1 >= half { sentenceEnd = index + 1 }
            } else if character.isNewline {
                if index >= half { sentenceEnd = index }
            }
            if character.isWhitespace, index > 0 { wordEnd = index }
        }
        let end = sentenceEnd ?? wordEnd ?? limit
        return (String(characters[..<end]).trimmingCharacters(in: .whitespacesAndNewlines), true)
    }

    /// The text is in another language but its preview could not be made: a "Dịch" button that opens the tab, which says what
    /// is missing and can install it, and a note when the language pack is what is missing.
    private func button(for source: SelectionSource, failure: PreviewFailure) -> SelectionDecision {
        let note = failure == .notInstalled ? SelectionHint.languagePackNote : ""
        return .hint(SelectionHint(kind: .button, text: note, source: source), previewFailure: failure)
    }
}

/// What the decider found for a selection.
nonisolated enum SelectionDecision: Equatable, Sendable {
    /// Something to show. `previewFailure` is why the preview is only a button, when it is.
    case hint(SelectionHint, previewFailure: PreviewFailure? = nil)
    case skip(SelectionSkip)
}
