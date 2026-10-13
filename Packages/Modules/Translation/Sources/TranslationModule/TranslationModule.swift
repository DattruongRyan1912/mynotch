import AppKit
import MyNotchCore
import Observation
import SwiftUI

/// "Dịch" tab: on-device translation of typed text, of the selection (⌃⌥T, through Accessibility) and of text sent
/// through the "Dịch bằng MyNotch" service.
public final class TranslationModule: FeatureModule {
    public let descriptor = ModuleDescriptor(
        id: "translation",
        displayName: "Dịch",
        systemImage: "translate",
        defaultEnabled: true,
        // Only the shortcut needs it, to read the selection; Services and typing work without.
        optionalPermissions: [.accessibility],
        order: 400
    )

    static let defaultShortcut = KeyboardShortcuts.Shortcut(.t, modifiers: [.control, .option])

    let state = TranslationState()
    private(set) var translator: Translator?
    private let engine: any TranslationEngine
    private let selection: SelectionReader
    private let languages: SupportedLanguages
    private let installer: any LanguageInstalling
    private let pasteboard: NSPasteboard
    private let shortcut: KeyboardShortcuts.Shortcut?
    private var context: ModuleContext?
    /// The shortcut's selection read; tests await it. A new press, Services text or stopping supersedes it.
    private(set) var selectionRead: Task<Void, Never>?

    /// The module the app runs: Apple's on-device engine, the system Accessibility API and the general pasteboard.
    public convenience init() {
        let engine = AppleTranslationEngine()
        self.init(
            engine: engine,
            selection: SelectionReader(),
            languages: SupportedLanguages(),
            installer: LanguageInstallerWindow { await engine.status(from: $0.source, to: $0.target) },
            pasteboard: .general,
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
        shortcut: KeyboardShortcuts.Shortcut?
    ) {
        self.engine = engine
        self.selection = selection
        self.languages = languages
        self.installer = installer
        self.pasteboard = pasteboard
        self.shortcut = shortcut
    }

    public func start(_ context: ModuleContext) async throws(ModuleError) {
        self.context = context
        translator = Translator(
            state: state, engine: engine, scheduler: context.scheduler, settings: context.settings, pasteboard: pasteboard
        )
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
        context.run { [weak self] in
            for await target in Observations({ settings.value(keys.targetLanguage) }) {
                self?.translator?.targetSettingChanged(target)
            }
        }
    }

    public func stop() async {
        selectionRead?.cancel()
        selectionRead = nil
        translator?.stop()
        translator = nil
        engine.invalidate()
        context = nil
        state.input = ""
        state.output = ""
        state.source = nil
        state.detectedSource = nil
        state.pairStatus = nil
        state.isTranslating = false
        state.error = nil
        state.isReadingSelection = false
    }

    public func makeTab() -> NotchTab? {
        guard let translator else { return nil }
        return NotchTab(
            id: descriptor.id,
            title: "Dịch",
            systemImage: "translate",
            preferredHeight: 220,
            acceptsKeyboard: true,
            content: AnyView(TranslationTabView(state: state, translator: translator) { [weak self] in self?.installLanguagePack() })
        )
    }

    public func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView? {
        let settings = environment.settings
        let keys = TranslationKeys(settings)
        return AnyView(TranslationSettingsView(
            preferredPair: settings.binding(keys.preferredPair),
            targetLanguage: settings.binding(keys.targetLanguage),
            autoTranslateOnOpen: settings.binding(keys.autoTranslateOnOpen),
            useChromiumAccessibility: settings.binding(keys.useChromiumAccessibility),
            languages: languages,
            status: { [engine] pair in await engine.status(from: pair.source, to: pair.target) },
            install: { [weak self, installer] pair in
                installer.install(pair) { self?.translator?.languagePackChanged() }
            }
        ))
    }

    /// The shortcut. The tab opens at once, empty and saying it is reading, since a slow app can take most of a
    /// second to answer; the selection fills it when the read ends. Nothing read leaves it empty, ready for typing.
    func selectionShortcutPressed() {
        guard let context, let translator else { return }
        selectionRead?.cancel()
        translator.receive(nil, translate: false)
        state.isReadingSelection = true
        showTab(context)
        selection.useChromiumAccessibility = context.settings.value(TranslationKeys(context.settings).useChromiumAccessibility)
        selectionRead = Task { [weak self, selection] in
            let text = await selection.selectedText()
            // A newer press, Services text or stopping took over while the app was being read.
            guard let self, !Task.isCancelled else { return }
            selectionRead = nil
            state.isReadingSelection = false
            // Text typed meanwhile is what the user wants translated.
            guard state.input.isEmpty else { return }
            receive(text)
        }
    }

    /// Opens the tab with `text` (from Services), translated right away if the user wants that.
    func open(with text: String?) {
        guard let context else { return }
        selectionRead?.cancel()
        selectionRead = nil
        state.isReadingSelection = false
        receive(text)
        showTab(context)
    }

    /// The banner's "Cài đặt…" button.
    func installLanguagePack() {
        guard let pair = state.currentPair else { return }
        installer.install(pair) { [weak self] in self?.translator?.languagePackChanged() }
    }

    private func receive(_ text: String?) {
        guard let context, let translator else { return }
        translator.receive(text, translate: context.settings.value(TranslationKeys(context.settings).autoTranslateOnOpen))
    }

    private func showTab(_ context: ModuleContext) {
        state.focusRequest += 1
        context.presenter.open(tab: descriptor.id)
    }
}
