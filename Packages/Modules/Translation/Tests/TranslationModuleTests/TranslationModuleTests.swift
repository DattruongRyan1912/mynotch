import AppKit
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import TranslationModule

/// A translation module wired to fakes, with nothing that reaches Translation, Accessibility or the system pasteboard.
struct ModuleFixture {
    let engine = FakeEngine()
    let accessibility = FakeAccessibility()
    let pauses = PauseGate()
    /// The wait of the replacement before the clipboard goes back (500 ms).
    let replacePauses = PauseGate()
    /// Its other waits: for the app to come to the front, and for the keyboard to come back before a paste.
    let handBackPauses = PauseGate()
    let applications = FakeApplications()
    let keystroke = FakeKeystroke()
    let synthesizer = FakeSynthesizer()
    let installer = FakeInstaller()
    /// The network: nothing in the tests reaches it, and rates are only asked for when the text has an amount of money.
    let ratesClient = FakeRatesClient()
    /// 15 January 2026, noon UTC: winter in the northern hemisphere and 19:00 in Hanoi.
    let clock = TestClock("2026-01-15T12:00:00Z")
    /// Reads quantities like the real one, and records when and where.
    let recognizer = SpyRecognizer()
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("MyNotchTests.\(UUID().uuidString)"))
    let module: TranslationModule
    let harness: RegistryHarness

    init() {
        module = TranslationModule(
            engine: engine,
            selection: SelectionReader(accessibility: accessibility) { [pauses] _ in try await pauses.pause() },
            languages: SupportedLanguages { [.vi, .en, .ja] },
            installer: installer,
            pasteboard: pasteboard,
            speech: SpeechPlayer(synthesizer: synthesizer),
            replacer: SelectionReplacer(
                accessibility: accessibility, applications: applications, keystroke: keystroke, pasteboard: pasteboard
            ) { [replacePauses, handBackPauses] duration in
                try await (duration == .milliseconds(500) ? replacePauses : handBackPauses).pause()
            },
            conversion: ConversionSetup(
                rates: ratesClient,
                // Hanoi and a metric region, whatever the Mac running the tests is set to.
                environment: ConversionEnvironment(
                    now: { [clock] in clock.now }, localZone: { TimeZone(identifier: "Asia/Ho_Chi_Minh")! }, system: { .metric }
                ),
                recognize: { [recognizer] text, currency in recognizer.recognize(text, currency) }
            ),
            shortcut: nil
        )
        harness = RegistryHarness([module])
        // The notch panel holds the keyboard until the module closes the notch.
        applications.holds = { [harness] in harness.presenter.closeCount == 0 }
    }

    var state: TranslationState { module.state }
    var keys: TranslationKeys { TranslationKeys(harness.settingsEnvironment(for: "translation")!.settings) }

    func start() async {
        await harness.registry.bootstrap()
    }

    /// Waits for the translation the last action started.
    func translated() async {
        await module.translator?.translation?.value
    }

    /// ⌃⌥T, until the selection read it started has finished.
    func pressShortcutAndRead() async {
        module.selectionShortcutPressed()
        await module.selectionRead?.value
    }

    func focus(_ bundleID: String) {
        accessibility.application = FocusedApplication(processID: 42, bundleID: bundleID)
    }

    func set<Value>(_ value: Value, for key: (TranslationKeys) -> SettingKey<Value>) {
        harness.settingsEnvironment(for: "translation")!.settings.set(value, for: key(keys))
    }
}

@Suite struct TranslationModuleTests {
    let fixture = ModuleFixture()

    @Test func describesItself() {
        let descriptor = fixture.module.descriptor
        #expect(descriptor.id == "translation")
        #expect(descriptor.displayName == "Dịch")
        #expect(descriptor.systemImage == "translate")
        #expect(descriptor.order == 400)
    }

    @Test func declaresThePermissionsItUsesAndWhy() {
        let descriptor = fixture.module.descriptor
        #expect(descriptor.permissions.isEmpty)
        #expect(descriptor.optionalPermissions == [.accessibility])
        #expect(descriptor.permissionReasons == [
            .accessibility: "Đọc văn bản bạn đang chọn ở app khác để dịch, và thay nó bằng bản dịch.",
        ])
    }

    @Test func registersTheHotkeyAndTheService() async {
        await fixture.start()
        #expect(fixture.harness.registry.state(of: "translation") == .running)
        let hotkey = fixture.harness.hotkeys.registrations.first { $0.id == "translation_translateSelection" }
        #expect(hotkey?.title == "Dịch đoạn chữ đang chọn")
        #expect(TranslationModule.defaultShortcut == KeyboardShortcuts.Shortcut(.t, modifiers: [.control, .option]))
        #expect(fixture.harness.services.handle(name: "translate", text: "Hello"))
    }

    @Test func tabTakesTheKeyboard() async throws {
        await fixture.start()
        let tab = try #require(fixture.harness.registry.tabs.first)
        #expect(tab.id == "translation")
        #expect(tab.title == "Dịch")
        #expect(tab.acceptsKeyboard)
        #expect(tab.preferredHeight == 220)
    }

    @Test func selectionOpensTheTabAndTranslates() async {
        await fixture.start()
        fixture.accessibility.selections = ["Hello, how are you today?"]
        await fixture.pressShortcutAndRead()
        #expect(fixture.harness.presenter.openedTabs == ["translation"])
        #expect(fixture.state.input == "Hello, how are you today?")
        #expect(!fixture.state.isReadingSelection)
        await fixture.translated()
        #expect(fixture.state.output == "Hello, how are you today? [en→vi]")
        #expect(fixture.state.detectedSource?.minimalIdentifier == "en")
        #expect(fixture.state.target.minimalIdentifier == "vi")
        #expect(fixture.state.pairStatus == .installed)
        #expect(!fixture.state.isTranslating)
    }

    @Test func shortcutOpensTheTabBeforeTheSelectionIsRead() async {
        await fixture.start()
        fixture.focus("com.google.Chrome")
        fixture.accessibility.selections = [nil, "Hello, how are you today?"]
        fixture.pauses.holds = true
        let focusRequest = fixture.state.focusRequest
        fixture.module.selectionShortcutPressed()
        #expect(fixture.harness.presenter.openedTabs == ["translation"])
        #expect(fixture.state.isReadingSelection)
        #expect(fixture.state.input.isEmpty)
        #expect(fixture.state.focusRequest == focusRequest + 1)

        await eventually { fixture.pauses.isWaiting }
        fixture.pauses.release()
        await fixture.module.selectionRead?.value
        #expect(!fixture.state.isReadingSelection)
        #expect(fixture.state.input == "Hello, how are you today?")
        await fixture.translated()
        #expect(fixture.state.output == "Hello, how are you today? [en→vi]")
        #expect(fixture.harness.presenter.openedTabs == ["translation"])
    }

    @Test func aSecondPressSupersedesTheFirstRead() async {
        await fixture.start()
        fixture.focus("com.google.Chrome")
        fixture.pauses.holds = true
        fixture.module.selectionShortcutPressed()
        await eventually { fixture.pauses.isWaiting }
        let first = fixture.module.selectionRead

        fixture.focus("com.apple.Safari")
        fixture.accessibility.selections = [nil, "Good morning, my friend"]
        fixture.pauses.holds = false
        fixture.module.selectionShortcutPressed()
        await first?.value
        await fixture.module.selectionRead?.value
        #expect(fixture.state.input == "Good morning, my friend")
        #expect(!fixture.state.isReadingSelection)
        await fixture.translated()
        await settle()
        #expect(fixture.engine.requests.map(\.text) == ["Good morning, my friend"])
    }

    @Test func serviceTextSupersedesAPendingRead() async {
        await fixture.start()
        fixture.focus("com.google.Chrome")
        fixture.accessibility.selections = [nil, "Hello"]
        fixture.pauses.holds = true
        fixture.module.selectionShortcutPressed()
        await eventually { fixture.pauses.isWaiting }
        let read = fixture.module.selectionRead
        #expect(fixture.harness.services.handle(name: "translate", text: "Xin chào, hôm nay trời đẹp quá"))
        await read?.value
        #expect(fixture.state.input == "Xin chào, hôm nay trời đẹp quá")
        #expect(!fixture.state.isReadingSelection)
    }

    @Test func typingWhileTheSelectionIsReadWins() async {
        await fixture.start()
        fixture.focus("com.google.Chrome")
        fixture.accessibility.selections = [nil, "Hello"]
        fixture.pauses.holds = true
        fixture.module.selectionShortcutPressed()
        await eventually { fixture.pauses.isWaiting }
        fixture.module.translator?.edit("Typed meanwhile")
        fixture.pauses.release()
        await fixture.module.selectionRead?.value
        #expect(fixture.state.input == "Typed meanwhile")
        #expect(!fixture.state.isReadingSelection)
    }

    @Test func noSelectionOpensTheTabEmptyAndFocused() async {
        await fixture.start()
        fixture.module.translator?.edit("Câu cũ")
        let focusRequest = fixture.state.focusRequest
        await fixture.pressShortcutAndRead()
        #expect(fixture.harness.presenter.openedTabs == ["translation"])
        #expect(fixture.state.input.isEmpty)
        #expect(fixture.state.output.isEmpty)
        #expect(!fixture.state.isReadingSelection)
        #expect(fixture.state.focusRequest == focusRequest + 1)
        fixture.harness.scheduler.advance(by: .seconds(1))
        #expect(fixture.module.translator?.translation == nil)
        #expect(!fixture.state.isTranslating)
        await settle()
        #expect(fixture.engine.requests.isEmpty)
    }

    @Test func withoutAccessibilityTheTabOpensEmpty() async {
        await fixture.start()
        fixture.accessibility.isTrusted = false
        fixture.accessibility.selections = ["Hello"]
        await fixture.pressShortcutAndRead()
        #expect(fixture.harness.presenter.openedTabs == ["translation"])
        #expect(fixture.state.input.isEmpty)
        #expect(fixture.module.translator?.translation == nil)
        await settle()
        #expect(fixture.engine.requests.isEmpty)
    }

    @Test func serviceTextOpensTheTabAndTranslates() async {
        await fixture.start()
        #expect(fixture.harness.services.handle(name: "translate", text: "Xin chào, hôm nay trời đẹp quá"))
        #expect(fixture.harness.presenter.openedTabs == ["translation"])
        await fixture.translated()
        // Vietnamese text with target Vietnamese flips to English.
        #expect(fixture.state.output == "Xin chào, hôm nay trời đẹp quá [vi→en]")
        #expect(fixture.state.target.minimalIdentifier == "en")
    }

    @Test func blankServiceTextOpensTheTabEmpty() async {
        await fixture.start()
        #expect(fixture.harness.services.handle(name: "translate", text: " \n"))
        #expect(fixture.harness.presenter.openedTabs == ["translation"])
        #expect(fixture.state.input.isEmpty)
        #expect(fixture.module.translator?.translation == nil)
        await settle()
        #expect(fixture.engine.requests.isEmpty)
    }

    @Test func autoTranslateCanBeTurnedOff() async {
        fixture.set(false, for: \.autoTranslateOnOpen)
        await fixture.start()
        #expect(fixture.harness.services.handle(name: "translate", text: "Hello"))
        #expect(fixture.state.input == "Hello")
        fixture.harness.scheduler.advance(by: .seconds(1))
        #expect(fixture.module.translator?.translation == nil)
        #expect(!fixture.state.isTranslating)
        await settle()
        #expect(fixture.engine.requests.isEmpty)
        #expect(fixture.state.output.isEmpty)
    }

    @Test func chromiumAccessibilitySettingReachesTheSelectionReader() async {
        fixture.set(false, for: \.useChromiumAccessibility)
        await fixture.start()
        fixture.focus("com.google.Chrome")
        fixture.accessibility.selections = [nil, "Hello"]
        await fixture.pressShortcutAndRead()
        #expect(fixture.accessibility.enabled.isEmpty)
        #expect(fixture.state.input.isEmpty)
    }

    @Test func missingLanguagePackShowsTheInstallBannerAndInstalls() async {
        await fixture.start()
        fixture.engine.failure = .notInstalled
        #expect(fixture.harness.services.handle(name: "translate", text: "Hello, how are you today?"))
        await fixture.translated()
        let pair = LanguagePair(source: .en, target: .vi)
        #expect(fixture.state.pairStatus == .supported)
        #expect(fixture.state.banner == .notInstalled(pair))
        #expect(fixture.state.output.isEmpty)
        #expect(fixture.state.error == nil)

        fixture.module.installLanguagePack()
        #expect(fixture.installer.pairs == [pair])
        fixture.engine.failure = nil   // the user downloaded the pack
        fixture.installer.onStatusChange?()
        await fixture.translated()
        #expect(fixture.state.banner == nil)
        #expect(fixture.state.output == "Hello, how are you today? [en→vi]")
    }

    @Test func unsupportedPairShowsItsBanner() async {
        await fixture.start()
        fixture.engine.failure = .unsupported
        #expect(fixture.harness.services.handle(name: "translate", text: "Hello, how are you today?"))
        await fixture.translated()
        #expect(fixture.state.pairStatus == .unsupported)
        #expect(fixture.state.banner == .unsupported)
    }

    @Test func targetChangedInSettingsReachesTheTab() async {
        await fixture.start()
        fixture.set("ja", for: \.targetLanguage)
        await eventually { fixture.state.target.minimalIdentifier == "ja" }
        #expect(fixture.state.target.minimalIdentifier == "ja")
    }

    @Test func theTabsOwnTargetChoiceTranslatesOnce() async throws {
        await fixture.start()
        let translator = try #require(fixture.module.translator)
        translator.edit("Hello, how are you today?")
        translator.setTarget(.ja)
        let chosen = translator.translation
        await fixture.translated()
        await settle()   // the setting's observation has seen "ja" by now
        #expect(translator.translation == chosen)
        #expect(fixture.engine.requests.map(\.pair) == [LanguagePair(source: .en, target: .ja)])
    }

    @Test func languagesAreLoadedForTheMenus() async {
        await fixture.start()
        await eventually { !fixture.state.languages.isEmpty }
        #expect(fixture.state.languages.map(\.minimalIdentifier) == ["en", "ja", "vi"])
    }

    @Test func stoppingUnregistersAndCancelsPendingWork() async throws {
        await fixture.start()
        fixture.engine.holds = true
        #expect(fixture.harness.services.handle(name: "translate", text: "Good morning"))
        await eventually { fixture.engine.waiting }
        let translator = try #require(fixture.module.translator)
        translator.edit("Hello")   // its translation is still waiting for the typing delay
        let inFlight = translator.translation
        await fixture.harness.registry.setEnabled(false, for: "translation")
        _ = fixture.harness.services.handle(name: "translate", text: "Hello")   // queued (newer core) or refused (older); either way the stopped module must not see it
        #expect(fixture.harness.presenter.openedTabs == ["translation"])
        #expect(fixture.harness.hotkeys.registrations.isEmpty)
        #expect(fixture.engine.invalidations == 1)
        #expect(fixture.module.translator == nil)
        #expect(fixture.state.input.isEmpty)
        #expect(!fixture.state.isTranslating)
        fixture.harness.scheduler.advance(by: .seconds(1))
        #expect(translator.translation == inFlight)
        #expect(!fixture.state.isTranslating)
        await settle()
        // Neither the typing delay nor the Services request reached the engine.
        #expect(fixture.engine.requests.map(\.text) == ["Good morning"])
    }

    @Test func settingsRowsExistBeforeTheModuleEverStarts() throws {
        #expect(fixture.harness.registry.state(of: "translation") == .disabled)
        let view = try #require(fixture.harness.registry.settingsView(for: "translation"))
        #expect(String(describing: view).hasPrefix("AnyView(TranslationSettingsView("))
    }

    @Test func settingsListsEachDirectionTheUserTranslates() {
        let inPair = TranslationSettingsView.statusPairs(preferred: PreferredPair(first: "vi", second: "en"), target: "vi")
        #expect(inPair == [LanguagePair(source: .vi, target: .en), LanguagePair(source: .en, target: .vi)])
        let outside = TranslationSettingsView.statusPairs(preferred: PreferredPair(first: "vi", second: "en"), target: "ja")
        #expect(outside.map { "\($0.source.minimalIdentifier)→\($0.target.minimalIdentifier)" } == ["vi→en", "en→vi", "vi→ja", "en→ja"])
    }

    @Test func preferredPairPickersNeverOfferTheOtherLanguage() {
        #expect(TranslationSettingsView.options(available: [.vi, .en, .ja], including: "en", excluding: "vi") == ["en", "ja"])
        // A saved value stays listed while the languages load, or if Translation dropped it.
        #expect(TranslationSettingsView.options(available: [.vi, .en], including: "de", excluding: "vi") == ["de", "en"])
    }

    @Test func quickConvertSettingsStartOffAndInVietnam() {
        #expect(fixture.keys.convertCurrency.defaultValue == false)
        #expect(fixture.keys.currencyTarget.defaultValue == "VND")
        #expect(fixture.keys.firstZone.defaultValue == "America/Los_Angeles")
        #expect(fixture.keys.secondZone.defaultValue == "Europe/London")
        #expect(fixture.keys.convertCurrency.name == "module.translation.convertCurrency")
    }

    @Test func currencyPickerOffersTheUsualOnesAndKeepsTheSavedOne() {
        let usual = TranslationSettingsView.currencyOptions(including: "VND")
        #expect(usual.map(\.code) == CurrencyCatalog.codes)
        #expect(usual.first?.name == "Đồng Việt Nam")
        #expect(TranslationSettingsView.currencyOptions(including: "CLP").map(\.code) == ["CLP"] + CurrencyCatalog.codes)
    }
}
