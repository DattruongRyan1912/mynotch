import AppKit
import MyNotchCore
import Observation
import SwiftUI

/// "Dịch" tab: on-device translation of typed text, of the selection (⌃⌥T, through Accessibility) and of text sent
/// through the "Dịch bằng MyNotch" service. Either text can be read aloud, and a translation of a selection can replace
/// it in the app it was selected in. A text that is a quantity (a unit, a time, an expression, an amount of money) is
/// converted above its translation, or instead of one when it is nothing else. A word or short phrase also gets its
/// entry from the Mac's dictionary. Apple translates unless the user chose an engine that needs their own key (Google,
/// Microsoft, an OpenAI-compatible server); its key stays in the Keychain, and when it fails the tab says so and offers
/// Apple's translation instead of switching by itself. With "Bôi đen là hiểu" on, a selection in any app is understood
/// without a keystroke: its conversion or a preview of its translation (Apple's on-device engine only) shows in a small chip
/// beside it, and the chip's "Mở" opens the full result in this tab. A selection it does not translate by itself, for a
/// reason that is only a guess (a name or heading, a doubtful language, the user's own language), gets a small translate
/// button instead, whose click does what the shortcut does.
public final class TranslationModule: FeatureModule {
    public let descriptor = ModuleDescriptor(
        id: "translation",
        displayName: "Dịch",
        systemImage: "translate",
        defaultEnabled: true,
        // Only the shortcut, the replacement and "Bôi đen là hiểu" need it, to read the selection and write over it;
        // Services, typing and speaking work without.
        optionalPermissions: [.accessibility],
        permissionReasons: [.accessibility: "Đọc văn bản bạn đang chọn ở app khác để dịch hoặc quy đổi, và thay nó bằng bản dịch."],
        order: 400
    )

    static let defaultShortcut = KeyboardShortcuts.Shortcut(.t, modifiers: [.control, .option])

    let state = TranslationState()
    let speech: SpeechPlayer
    private(set) var translator: Translator?
    private let engine: any TranslationEngine
    private let selection: SelectionReader
    private let languages: SupportedLanguages
    private let installer: any LanguageInstalling
    private let replacer: SelectionReplacer
    private let pasteboard: NSPasteboard
    private let conversion: ConversionSetup
    private let dictionary: any DictionaryLooking
    private let opener: any URLOpening
    private let engineSetup: EngineSetup
    private let smartSelectionSetup: SmartSelectionSetup
    /// "Bôi đen là hiểu", while the module runs.
    private(set) var smartSelection: SmartSelection?
    /// The Settings rows of the engines. The page asks for its views again whenever it redraws, and what the model knows
    /// (the saved keys, a check under way) must not start over each time, so there is one.
    private(set) var engineSettings: EngineSettingsModel?
    private let shortcut: KeyboardShortcuts.Shortcut?
    private var context: ModuleContext?
    /// The shortcut's selection read; tests await it. A new press, Services text or stopping supersedes it.
    private(set) var selectionRead: Task<Void, Never>?
    /// The replacement in progress; tests await it. Stopping cancels it, and waits for it to put the clipboard back.
    private(set) var replacement: Task<Void, Never>?
    /// The replacement closed the notch to paste, so a failure has to bring it back to be seen.
    private var closedNotchForPaste = false

    /// The module the app runs: Apple's on-device engine, the system Accessibility API, the system voices and the
    /// general pasteboard.
    public convenience init() {
        let engine = AppleTranslationEngine()
        let accessibility = SystemAccessibilityClient()
        self.init(
            engine: engine,
            selection: SelectionReader(accessibility: accessibility),
            languages: SupportedLanguages(),
            installer: LanguageInstallerWindow { await engine.status(from: $0.source, to: $0.target) },
            pasteboard: .general,
            speech: SpeechPlayer(synthesizer: SystemSpeechSynthesizer()),
            replacer: SelectionReplacer(accessibility: accessibility, pasteboard: .general),
            conversion: ConversionSetup(),
            dictionary: SystemDictionary(),
            opener: WorkspaceURLOpener(),
            engines: EngineSetup(),
            smartSelection: SmartSelectionSetup(accessibility: accessibility),
            shortcut: Self.defaultShortcut
        )
    }

    /// - Parameter shortcut: initial key combination of the selection shortcut; tests pass nil, so they neither
    ///   store a shortcut nor take ⌃⌥T from the system.
    init(
        engine: any TranslationEngine,
        selection: SelectionReader,
        languages: SupportedLanguages,
        installer: any LanguageInstalling,
        pasteboard: NSPasteboard,
        speech: SpeechPlayer,
        replacer: SelectionReplacer,
        conversion: ConversionSetup,
        dictionary: any DictionaryLooking,
        opener: any URLOpening,
        engines: EngineSetup,
        smartSelection: SmartSelectionSetup,
        shortcut: KeyboardShortcuts.Shortcut?
    ) {
        self.engine = engine
        self.selection = selection
        self.languages = languages
        self.installer = installer
        self.pasteboard = pasteboard
        self.speech = speech
        self.replacer = replacer
        self.conversion = conversion
        self.dictionary = dictionary
        self.opener = opener
        self.engineSetup = engines
        self.smartSelectionSetup = smartSelection
        self.shortcut = shortcut
    }

    public func start(_ context: ModuleContext) async throws(ModuleError) {
        self.context = context
        let rates = ExchangeRateService(
            client: conversion.rates, cacheFile: context.storage.cachesDirectory.appending(path: "exchange-rates.json"),
            now: conversion.environment.now
        )
        let converter = QuickConverter(
            settings: context.settings, keys: TranslationKeys(context.settings), rates: rates, environment: conversion.environment,
            recognize: conversion.recognize
        )
        let remote = remoteEngines(context.settings)
        translator = Translator(
            state: state, engines: EngineSet(apple: engine, remote: remote.engine(for:)), dictionary: DictionaryFinder(dictionary),
            converter: converter, scheduler: context.scheduler, settings: context.settings, pasteboard: pasteboard
        )
        let smart = SmartSelection(
            context: context, setup: smartSelectionSetup,
            decider: SelectionDecider(converter: converter, preview: smartSelectionSetup.preview, languages: languages, settings: context.settings),
            open: { [weak self] in self?.openSelection($0) },
            translate: { [weak self] in self?.selectionShortcutPressed() }
        )
        smartSelection = smart
        context.hotkeys.register("translateSelection", title: "Dịch đoạn chữ đang chọn", initial: shortcut) { [weak self] in
            self?.selectionShortcutPressed()
        }
        context.services.register("translate") { [weak self] text in
            self?.open(with: text)
        }
        context.run { [weak self, languages] in
            let all = await languages.all()
            self?.state.languages = all
        }
        let settings = context.settings
        let keys = TranslationKeys(settings)
        state.offersReplace = settings.value(keys.showReplaceButton)
        context.run { [weak self] in
            for await target in Observations({ settings.value(keys.targetLanguage) }) {
                self?.translator?.targetSettingChanged(target)
            }
        }
        context.run { [weak self] in
            for await offers in Observations({ settings.value(keys.showReplaceButton) }) {
                self?.state.offersReplace = offers
            }
        }
        smart.start()
    }

    public func stop() async {
        smartSelection?.stop()
        smartSelection = nil
        selectionRead?.cancel()
        selectionRead = nil
        speech.stop()
        translator?.stop()
        translator = nil
        engine.invalidate()
        // A paste waiting to put the user's clipboard back must finish: cancelling only keeps one from starting.
        let replacement = replacement
        replacement?.cancel()
        await replacement?.value
        self.replacement = nil
        context = nil
        state.input = ""
        state.output = ""
        state.dictionary = nil
        state.source = nil
        state.detectedSource = nil
        state.pairStatus = nil
        state.isTranslating = false
        state.error = nil
        state.offersAppleFallback = false
        state.conversions = []
        state.showsConversionsOnly = false
        state.isReadingSelection = false
        state.selectionSource = nil
        state.isReplacing = false
        state.needsAccessibility = false
        state.replaceFailure = nil
    }

    public func makeTab() -> NotchTab? {
        guard let translator else { return nil }
        let actions = TranslationTabActions(
            install: { [weak self] in self?.installLanguagePack() },
            replace: { [weak self] in self?.replaceSelection() },
            requestAccessibility: { [weak self] in self?.requestAccessibility() },
            refreshAccessibility: { [weak self] in self?.refreshAccessibility() },
            openDictionary: { [weak self] in self?.openInDictionary() }
        )
        return NotchTab(
            id: descriptor.id,
            title: "Dịch",
            systemImage: "translate",
            preferredHeight: 220,
            acceptsKeyboard: true,
            content: AnyView(TranslationTabView(state: state, translator: translator, speech: speech, actions: actions))
        )
    }

    public func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView? {
        let settings = environment.settings
        let keys = TranslationKeys(settings)
        let engineSettings = engineSettings ?? EngineSettingsModel(
            keys: engineSetup.keys, engines: remoteEngines(settings), log: engineSetup.log
        )
        self.engineSettings = engineSettings
        return AnyView(TranslationSettingsView(
            preferredPair: settings.binding(keys.preferredPair),
            targetLanguage: settings.binding(keys.targetLanguage),
            autoTranslateOnOpen: settings.binding(keys.autoTranslateOnOpen),
            useChromiumAccessibility: settings.binding(keys.useChromiumAccessibility),
            showReplaceButton: settings.binding(keys.showReplaceButton),
            smartSelection: settings.binding(keys.smartSelection),
            showSelectionChip: settings.binding(keys.selectionChip),
            showSelectionButton: settings.binding(keys.selectionButton),
            showSelectionActivity: settings.binding(keys.selectionActivity),
            selectionDenyList: settings.binding(keys.selectionDenyList),
            convertCurrency: settings.binding(keys.convertCurrency),
            currencyTarget: settings.binding(keys.currencyTarget),
            firstZone: settings.binding(keys.firstZone),
            secondZone: settings.binding(keys.secondZone),
            engine: settings.binding(keys.engine),
            microsoftRegion: settings.binding(keys.microsoftRegion),
            openAIBaseURL: settings.binding(keys.openAIBaseURL),
            openAIModel: settings.binding(keys.openAIModel),
            engines: engineSettings,
            languages: languages,
            status: { [engine] pair in await engine.status(from: pair.source, to: pair.target) },
            install: { [weak self, installer] pair in
                installer.install(pair) { self?.translator?.languagePackChanged() }
            }
        ))
    }

    /// The engines that need the user's key, reading their non-secret settings when they translate.
    private func remoteEngines(_ settings: ModuleSettings) -> RemoteEngines {
        let keys = TranslationKeys(settings)
        return RemoteEngines(keys: engineSetup.keys, transport: engineSetup.transport, log: engineSetup.log) {
            EngineConfig(
                microsoftRegion: settings.value(keys.microsoftRegion), openAIBaseURL: settings.value(keys.openAIBaseURL),
                openAIModel: settings.value(keys.openAIModel)
            )
        }
    }

    /// The shortcut. The tab opens at once, empty and saying it is reading, since a slow app can take most of a
    /// second to answer; the selection fills it when the read ends. Nothing read leaves it empty, ready for typing.
    func selectionShortcutPressed() {
        guard let context, let translator else { return }
        selectionRead?.cancel()
        translator.receive(nil, translate: false)
        forgetSelection()
        state.isReadingSelection = true
        showTab(context)
        selection.useChromiumAccessibility = context.settings.value(TranslationKeys(context.settings).useChromiumAccessibility)
        selectionRead = Task { [weak self, selection] in
            let source = await selection.selection()
            // A newer press, Services text or stopping took over while the app was being read.
            guard let self, !Task.isCancelled else { return }
            selectionRead = nil
            state.isReadingSelection = false
            // Text typed meanwhile is what the user wants translated.
            guard state.input.isEmpty else { return }
            state.selectionSource = source
            receive(source?.text)
        }
    }

    /// Opens the tab with `text` (from Services), translated right away if the user wants that.
    func open(with text: String?) {
        guard let context else { return }
        selectionRead?.cancel()
        selectionRead = nil
        state.isReadingSelection = false
        forgetSelection()
        receive(text)
        showTab(context)
    }

    /// The chip's "Mở": the tab opens on a selection that was understood without a keystroke. It is translated at once whatever
    /// the auto-translate setting says, since the user asked to see it, and by the engine chosen in Settings, which is the
    /// first time anything but Apple's on-device engine sees it. The selection's app is kept, so the result can be spoken
    /// and written back over it like one read by the shortcut.
    func openSelection(_ source: SelectionSource) {
        guard let context, let translator else { return }
        selectionRead?.cancel()
        selectionRead = nil
        state.isReadingSelection = false
        forgetSelection()
        translator.receive(source.text, translate: true)
        state.selectionSource = source
        refreshAccessibility()
        showTab(context)
    }

    /// The card's "Mở trong Từ điển" button: Dictionary opens at the word, over the notch, which closes.
    func openInDictionary() {
        guard let url = state.dictionary?.dictionaryURL else { return }
        opener.open(url)
        context?.presenter.close()
    }

    /// The banner's "Cài đặt…" button.
    func installLanguagePack() {
        guard let pair = state.currentPair else { return }
        installer.install(pair) { [weak self] in self?.translator?.languagePackChanged() }
    }

    /// The button under a result that came from a selection: puts the translation in place of that selection, in the
    /// app it was selected in. nil when there is nothing to replace or it cannot be done now.
    @discardableResult
    func replaceSelection() -> Task<Void, Never>? {
        guard context != nil, state.canReplace, let source = state.selectionSource else { return nil }
        let text = state.output
        state.isReplacing = true
        state.replaceFailure = nil
        closedNotchForPaste = false
        let task = Task { [weak self, replacer] in
            let outcome = await replacer.replace(text, expecting: source.text, in: source.application) { [weak self] in
                self?.closeNotchForPaste()
            }
            // Stopping cancelled it and resets the state itself.
            guard let self, !Task.isCancelled else { return }
            finishReplacing(outcome, of: source)
        }
        replacement = task
        return task
    }

    /// Whether the hint "Cần quyền Accessibility" should show: a result could be replaced, but MyNotch may not write
    /// to other apps. Reading trust never prompts. The tab checks when it appears and every 2 s while shown, so the
    /// hint goes by itself once the permission is granted.
    func refreshAccessibility() {
        let needs = state.showsReplace && !replacer.isTrusted
        if state.needsAccessibility != needs { state.needsAccessibility = needs }
    }

    /// The hint's button: the system's prompt (which lists MyNotch in the Accessibility pane), then that pane when the
    /// prompt alone did not allow it. nil while stopped; await the task for completion.
    @discardableResult
    func requestAccessibility() -> Task<Void, Never>? {
        guard let context else { return nil }
        return Task { [weak self] in
            if await context.permissions.request(.accessibility) != .granted {
                context.permissions.openSystemSettings(for: .accessibility)
            }
            self?.refreshAccessibility()
        }
    }

    /// The tab no longer shows a translation of a selection, so there is nothing to replace and nothing to explain.
    private func forgetSelection() {
        state.selectionSource = nil
        state.replaceFailure = nil
        refreshAccessibility()
    }

    /// A paste needs the keyboard back in the app the text came from, and the notch panel holds it while the Translation
    /// input has it, so the notch closes first, as it does for a paste from Clipboard.
    private func closeNotchForPaste() {
        closedNotchForPaste = true
        context?.presenter.close()
    }

    private func finishReplacing(_ outcome: ReplaceOutcome, of source: SelectionSource) {
        replacement = nil
        state.isReplacing = false
        let closedForPaste = closedNotchForPaste
        closedNotchForPaste = false
        // A newer press took over the tab while this one ran: what it found is not about the new selection, which it
        // must not explain, drop or close the notch over.
        guard state.selectionSource == source else { return }
        switch outcome {
        case .replaced, .pasted:
            // The selection now holds the translation: there is nothing left for the button to replace.
            state.selectionSource = nil
            state.needsAccessibility = false
            // A paste closed it already, and the user may have opened it again while the clipboard was coming back.
            if !closedForPaste { context?.presenter.close() }
        case .needsAccessibility:
            state.needsAccessibility = true
        case .selectionChanged:
            state.replaceFailure = "Vùng chọn đã đổi, nên chưa thay được"
            if closedForPaste { context?.presenter.open() }
        case .failed:
            state.replaceFailure = "Không thay được chữ ở app kia"
            if closedForPaste { context?.presenter.open() }
        }
    }

    private func receive(_ text: String?) {
        guard let context, let translator else { return }
        translator.receive(text, translate: context.settings.value(TranslationKeys(context.settings).autoTranslateOnOpen))
    }

    private func showTab(_ context: ModuleContext) {
        state.focusRequest += 1
        context.presenter.open()
    }
}
