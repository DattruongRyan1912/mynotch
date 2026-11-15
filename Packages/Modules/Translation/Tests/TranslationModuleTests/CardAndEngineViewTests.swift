import AppKit
import SwiftUI
import Testing
@testable import TranslationModule

/// The dictionary card and the engine rows, hosted in a window that is never shown.
@Suite struct CardAndEngineViewTests {
    let fixture = ModuleFixture()

    /// The output box is about 205 pt wide and a good 160 pt tall; a card with three senses must leave room under it for
    /// the first lines of the translation.
    @Test func aCardWithThreeLongSensesLeavesRoomForTheTranslation() throws {
        let entry = try #require(DictionaryParser.entry(from: DictionarySamples.run, for: "run"))
        #expect(entry.senses.count == 3)
        let card = DictionaryCardView(entry: entry, open: {})
        #expect(NSHostingView(rootView: card.frame(width: 189)).fittingSize.height <= 120)
    }

    @Test func theTabHoldsACardAboveATranslation() async throws {
        fixture.dictionary.definitions["hello"] = DictionarySamples.hello
        await fixture.start()
        let tab = try #require(fixture.module.makeTab())
        let translator = try #require(fixture.module.translator)
        translator.submit("hello")
        await fixture.translated()
        await translator.lookup?.value
        let hosting = NSHostingView(rootView: AnyView(tab.content.frame(width: 452, height: 176)))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 452, height: 176), styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        #expect(fixture.state.showsDictionary)
        #expect(hosting.fittingSize.height <= 176)
        window.contentView = nil
    }

    @Test func theSettingsPageKeepsOneEngineModelWhenItRedraws() async throws {
        _ = fixture.keyStore.save("some-key", for: .googleKey)
        fixture.set("google", for: \.engine)
        let page = try #require(fixture.harness.registry.settingsView(for: "translation"))
        let model = try #require(fixture.module.engineSettings)
        // The page asks again on every redraw; what the model knows must not start over.
        _ = fixture.harness.registry.settingsView(for: "translation")
        #expect(fixture.module.engineSettings === model)

        let hosting = NSHostingView(rootView: Form { page }.formStyle(.grouped).frame(width: 560, height: 520))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 560, height: 520), styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = hosting
        // Appearing is what looks up which keys are saved, in the background.
        await eventuallyAfterWaiting { model.hasLoaded }
        #expect(model.savedKeys == [.google])
        // Showing the rows sends nothing anywhere.
        #expect(fixture.transport.requests.isEmpty)
        window.contentView = nil
    }

    @Test func theRowsOfEveryEngineLayOutWithoutAKey() async throws {
        for choice in EngineChoice.allCases {
            let model = EngineSettingsModel(
                keys: fixture.keyStore,
                engines: RemoteEngines(keys: fixture.keyStore, transport: fixture.transport, log: fixture.engineLog, config: { EngineConfig() }),
                log: fixture.engineLog
            )
            let view = Form {
                TranslationEngineSettingsView(
                    engine: .constant(choice.rawValue), microsoftRegion: .constant(""), openAIBaseURL: .constant(""),
                    openAIModel: .constant(""), model: model
                )
            }
            .formStyle(.grouped)
            let size = NSHostingView(rootView: view.frame(width: 560)).fittingSize
            #expect(size.height > 60, "\(choice)")
        }
        #expect(fixture.transport.requests.isEmpty)
        #expect(fixture.keyStore.values.isEmpty)
    }
}
