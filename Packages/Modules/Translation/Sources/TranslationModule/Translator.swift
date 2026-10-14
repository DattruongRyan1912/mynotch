import AppKit
import MyNotchCore

/// The tab's translation flow: picks the direction, translates after typing pauses, and shows only the newest result.
final class Translator {
    /// Typing translates once the user pauses this long.
    static let typingDelay = Duration.milliseconds(600)

    let state: TranslationState
    /// The newest translation; tests await it.
    private(set) var translation: Task<Void, Never>?
    /// The wait for exchange rates after the newest request, if its text had an amount of money; tests await it.
    private(set) var conversion: Task<Void, Never>?

    private let engine: any TranslationEngine
    private let converter: QuickConverter
    private let detector = LanguageDetector()
    private let scheduler: any Scheduler
    private let settings: ModuleSettings
    private let keys: TranslationKeys
    private let pasteboard: NSPasteboard
    private var pendingTyping: ScheduledAction?
    /// Bumped by every request; a result is shown only while its request is still the newest.
    private var generation = 0
    /// Source the user chose last (menu or swap); detection falls back to it when unsure.
    private var lastSource: Locale.Language?
    /// The direction `state.pairStatus` was found for.
    private var statusPair: LanguagePair?
    /// Target setting last applied, so a flip (which leaves the setting alone) isn't mistaken for a change.
    private var appliedTarget: String
    private var isStopped = false

    init(
        state: TranslationState, engine: any TranslationEngine, converter: QuickConverter, scheduler: any Scheduler,
        settings: ModuleSettings, pasteboard: NSPasteboard
    ) {
        self.state = state
        self.engine = engine
        self.converter = converter
        self.scheduler = scheduler
        self.settings = settings
        self.pasteboard = pasteboard
        keys = TranslationKeys(settings)
        appliedTarget = settings.value(keys.targetLanguage)
        state.target = Locale.Language(identifier: appliedTarget)
    }

    /// Text from the selection or Services replaces the input; nil or blank text leaves the tab empty.
    func receive(_ text: String?, translate translates: Bool) {
        guard !isStopped else { return }
        pendingTyping?.cancel()
        state.input = text.flatMap { $0.allSatisfy(\.isWhitespace) ? nil : $0 } ?? ""
        state.output = ""
        state.error = nil
        if translates {
            translate()
        } else {
            supersede()
            clearResult()
        }
    }

    /// The user typed. Translates after a pause; a blank input clears the result at once.
    func edit(_ text: String) {
        guard !isStopped else { return }
        userSet(text)
        pendingTyping?.cancel()
        guard !text.allSatisfy(\.isWhitespace) else {
            translate()
            return
        }
        pendingTyping = scheduler.schedule(after: Self.typingDelay) { [weak self] in self?.translate() }
    }

    /// Translates the input now (Return, a menu change, new text), superseding any translation in flight.
    func translate() {
        guard !isStopped else { return }
        pendingTyping?.cancel()
        supersede()
        let text = state.input
        guard !text.allSatisfy(\.isWhitespace) else {
            clearResult()
            return
        }
        let plan = converter.plan(for: text)
        state.conversions = plan.conversions
        state.showsConversionsOnly = plan.isPure
        let request = generation
        resolveMoney(of: plan, for: request)
        // A text that is nothing but quantities has nothing to translate.
        guard !plan.isPure else {
            showNoTranslation()
            return
        }
        let pair = direction(for: text)
        state.detectedSource = state.source == nil ? pair.source : nil
        state.target = pair.target
        state.replaceFailure = nil
        // Same direction: keep the banner up while retranslating, so it doesn't flicker with every pause in typing.
        if pair != statusPair { state.pairStatus = nil }
        state.isTranslating = true
        translation = Task { [weak self, engine] in
            let result: Result<String, TranslationFailure>
            do throws(TranslationFailure) {
                result = .success(try await engine.translate(text, from: pair.source, to: pair.target))
            } catch {
                result = .failure(error)
            }
            guard let self, request == self.generation else { return }
            self.show(result, for: pair)
        }
    }

    /// Return. `text` is what the field shows, which can differ from the input while an input method composes.
    func submit(_ text: String) {
        guard !isStopped else { return }
        userSet(text)
        translate()
    }

    /// nil picks the source by detection.
    func setSource(_ language: Locale.Language?) {
        state.source = language
        if let language { lastSource = language }
        translate()
    }

    /// Also becomes the target setting, so the choice outlives the app.
    func setTarget(_ language: Locale.Language) {
        state.target = language
        appliedTarget = language.minimalIdentifier
        settings.set(appliedTarget, for: keys.targetLanguage)
        translate()
    }

    /// Reverses the direction; the result, if any, becomes the text to translate back.
    func swap() {
        guard let pair = state.currentPair else { return }
        state.source = pair.target
        state.target = pair.source
        lastSource = pair.target
        if !state.output.isEmpty { userSet(state.output) }
        translate()
    }

    func copyOutput() {
        copy(state.output)
    }

    /// The copy button of a translation or of one conversion result.
    func copy(_ text: String) {
        guard !text.isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// A language pack may have been installed: translate again, which also re-checks the pair.
    func languagePackChanged() {
        translate()
    }

    /// The target setting changed, in the tab or in Settings.
    func targetSettingChanged(_ identifier: String) {
        guard identifier != appliedTarget else { return }
        appliedTarget = identifier
        state.target = Locale.Language(identifier: identifier)
        translate()
    }

    /// The module stopped: nothing runs or shows up any more.
    func stop() {
        isStopped = true
        pendingTyping?.cancel()
        supersede()
    }

    /// The user changed the text to translate. A result of other text must not be offered as the replacement of the
    /// selection the input came from; a field reporting the text it already shows changes nothing.
    private func userSet(_ text: String) {
        if text != state.input { state.selectionSource = nil }
        state.input = text
    }

    private func direction(for text: String) -> LanguagePair {
        let preferred = settings.value(keys.preferredPair).languages
        let direction = if let source = state.source {
            // A chosen source is certain; only the flip rule still applies.
            LanguageDetector.resolveDirection(detected: (source, 1), preferredPair: preferred, target: state.target, lastSource: lastSource)
        } else {
            detector.resolveDirection(
                text: text, candidates: state.languages, preferredPair: preferred, target: state.target, lastSource: lastSource
            )
        }
        return LanguagePair(source: direction.source, target: direction.target)
    }

    /// The translation in flight, if any, must not show its result over newer text.
    private func supersede() {
        generation += 1
        translation?.cancel()
        conversion?.cancel()
        state.isTranslating = false
    }

    /// Fills in the amounts of money once the rates are there, unless newer text took over meanwhile.
    private func resolveMoney(of plan: ConversionPlan, for request: Int) {
        guard !plan.pending.isEmpty else { return }
        conversion = Task { [weak self, converter] in
            let resolved = await converter.resolve(plan)
            guard let self, request == generation, !Task.isCancelled else { return }
            state.conversions = resolved
        }
    }

    /// Nothing is translated: whatever an earlier translation left is gone.
    private func showNoTranslation() {
        state.output = ""
        state.error = nil
        state.detectedSource = nil
        state.pairStatus = nil
        statusPair = nil
        state.replaceFailure = nil
    }

    private func show(_ result: Result<String, TranslationFailure>, for pair: LanguagePair) {
        state.isTranslating = false
        switch result {
        case .success(let text):
            state.output = text
            state.error = nil
            setStatus(.installed, for: pair)
        case .failure(.notInstalled):
            state.output = ""
            state.error = nil
            setStatus(.supported, for: pair)
        case .failure(.unsupported):
            state.output = ""
            state.error = nil
            setStatus(.unsupported, for: pair)
        case .failure(.failed(let message)):
            state.output = ""
            state.error = message
        case .failure(.cancelled):
            break   // nothing newer replaced it, so whatever the tab shows stays
        }
    }

    private func setStatus(_ status: PairStatus, for pair: LanguagePair) {
        state.pairStatus = status
        statusPair = pair
    }

    private func clearResult() {
        state.conversions = []
        state.showsConversionsOnly = false
        state.output = ""
        state.error = nil
        state.detectedSource = nil
        state.pairStatus = nil
        statusPair = nil
    }
}
