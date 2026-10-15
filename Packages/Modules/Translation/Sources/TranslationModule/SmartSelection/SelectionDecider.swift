import Foundation
import MyNotchCore

/// What a selection is worth showing: its conversion when it is a quantity, a calculation or a zoned time, else a preview
/// of its translation when it is in another language, else nothing.
///
/// The preview is made by Apple's on-device engine only: the type of `preview` is `OnDeviceTranslationEngine`, which no
/// engine that needs a key conforms to, so the text of a selection cannot leave the Mac from here; the engine the user chose
/// runs when they open the result.
final class SelectionDecider {
    /// The chip shows one line of the translation, so no more than this many characters of the selection are translated.
    static let previewLimit = 300

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

    func hint(for source: SelectionSource) async -> SelectionHint? {
        let text = source.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        // Quick convert first: a clear quantity is shown converted, whatever language the rest is in. A price waits for the
        // day's rates, which are the only thing fetched, and no text goes with the request.
        if QuickConverter.mightHaveQuantities(text) {
            let plan = await converter.plan(for: text)
            if !plan.conversions.isEmpty {
                let conversions = await converter.resolve(plan)
                guard !Task.isCancelled, let line = conversions.lazy.compactMap(SelectionHint.conversionText).first else { return nil }
                return SelectionHint(kind: .conversion, text: SelectionHint.shortened(line), source: source)
            }
        }
        return await translation(of: text, from: source)
    }

    private func translation(of text: String, from source: SelectionSource) async -> SelectionHint? {
        let target = Locale.Language(identifier: settings.value(keys.targetLanguage))
        let preferred = settings.value(keys.preferredPair).languages
        let candidates = [preferred.0, preferred.1, target] + (await languages.all())
        guard let from = await SelectionLanguage.sourceInBackground(of: text, target: target, candidates: candidates),
              !Task.isCancelled,
              let translated = try? await preview.translate(String(text.prefix(Self.previewLimit)), from: from, to: target),
              !Task.isCancelled,
              let line = SelectionHint.firstLine(of: translated) else { return nil }
        return SelectionHint(kind: .translation, text: line, source: source)
    }
}
