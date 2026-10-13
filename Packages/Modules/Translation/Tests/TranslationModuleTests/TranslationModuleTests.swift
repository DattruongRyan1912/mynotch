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
    let installer = FakeInstaller()
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("MyNotchTests.\(UUID().uuidString)"))
    let module: TranslationModule
    let harness: RegistryHarness

    init() {
        module = TranslationModule(
            engine: engine,
            selection: SelectionReader(accessibility: accessibility) { _ in },
            languages: SupportedLanguages { [.vi, .en, .ja] },
            installer: installer,
            pasteboard: pasteboard,
            shortcut: nil
        )
        harness = RegistryHarness([module])
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
        #expect(descriptor.permissions.isEmpty)
        #expect(descriptor.optionalPermissions == [.accessibility])
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
        await fixture.module.translateSelection()
        #expect(fixture.harness.presenter.openedTabs == ["translation"])
        #expect(fixture.state.input == "Hello, how are you today?")
        await fixture.translated()
        #expect(fixture.state.output == "Hello, how are you today? [en→vi]")
        #expect(fixture.state.detectedSource?.minimalIdentifier == "en")
        #expect(fixture.state.target.minimalIdentifier == "vi")
        #expect(fixture.state.pairStatus == .installed)
        #expect(!fixture.state.isTranslating)
    }

    @Test func noSelectionOpensTheTabEmptyAndFocused() async {
        await fixture.start()
        fixture.module.translator?.edit("Câu cũ")
        let focusRequest = fixture.state.focusRequest
        await fixture.module.translateSelection()
        #expect(fixture.harness.presenter.openedTabs == ["translation"])
        #expect(fixture.state.input.isEmpty)
        #expect(fixture.state.output.isEmpty)
        #expect(fixture.state.focusRequest == focusRequest + 1)
        fixture.harness.scheduler.advance(by: .seconds(1))
        #expect(fixture.engine.requests.isEmpty)
    }

    @Test func withoutAccessibilityTheTabOpensEmpty() async {
        await fixture.start()
        fixture.accessibility.isTrusted = false
        fixture.accessibility.selections = ["Hello"]
        await fixture.module.translateSelection()
        #expect(fixture.harness.presenter.openedTabs == ["translation"])
        #expect(fixture.state.input.isEmpty)
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
        #expect(fixture.engine.requests.isEmpty)
    }

    @Test func autoTranslateCanBeTurnedOff() async {
        fixture.set(false, for: \.autoTranslateOnOpen)
        await fixture.start()
        #expect(fixture.harness.services.handle(name: "translate", text: "Hello"))
        #expect(fixture.state.input == "Hello")
        fixture.harness.scheduler.advance(by: .seconds(1))
        #expect(fixture.engine.requests.isEmpty)
        #expect(fixture.state.output.isEmpty)
    }

    @Test func chromiumAccessibilitySettingReachesTheSelectionReader() async {
        fixture.set(false, for: \.useChromiumAccessibility)
        await fixture.start()
        fixture.accessibility.application = FocusedApplication(processID: 42, bundleID: "com.google.Chrome")
        fixture.accessibility.selections = [nil, "Hello"]
        await fixture.module.translateSelection()
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

    @Test func languagesAreLoadedForTheMenus() async {
        await fixture.start()
        await eventually { !fixture.state.languages.isEmpty }
        #expect(fixture.state.languages.map(\.minimalIdentifier) == ["en", "ja", "vi"])
    }

    @Test func stoppingUnregistersAndCancelsPendingWork() async {
        await fixture.start()
        fixture.engine.holds = true
        #expect(fixture.harness.services.handle(name: "translate", text: "Good morning"))
        await eventually { fixture.engine.waiting }
        fixture.module.translator?.edit("Hello")   // its translation is still waiting for the typing delay
        await fixture.harness.registry.setEnabled(false, for: "translation")
        #expect(!fixture.harness.services.handle(name: "translate", text: "Hello"))
        #expect(fixture.harness.hotkeys.registrations.isEmpty)
        #expect(fixture.engine.invalidations == 1)
        #expect(fixture.module.translator == nil)
        #expect(fixture.state.input.isEmpty)
        #expect(!fixture.state.isTranslating)
        fixture.harness.scheduler.advance(by: .seconds(1))
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
}
