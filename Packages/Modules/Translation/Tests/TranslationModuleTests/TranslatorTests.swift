import AppKit
import Foundation
import MyNotchCore
import Testing
@testable import TranslationModule

@Suite struct TranslatorTests {
    let fixture = ModuleFixture()

    func startedTranslator() async throws -> Translator {
        await fixture.start()
        return try #require(fixture.module.translator)
    }

    @Test func typingTranslatesAfter600MillisecondsIdle() async throws {
        let translator = try await startedTranslator()
        translator.edit("Hel")
        fixture.harness.scheduler.advance(by: .milliseconds(599))
        translator.edit("Hello, how are you today?")
        fixture.harness.scheduler.advance(by: .milliseconds(599))
        #expect(translator.translation == nil)
        #expect(!fixture.state.isTranslating)
        await settle()
        #expect(fixture.engine.requests.isEmpty)
        fixture.harness.scheduler.advance(by: .milliseconds(1))
        await fixture.translated()
        #expect(fixture.engine.requests.map(\.text) == ["Hello, how are you today?"])
        #expect(fixture.state.output == "Hello, how are you today? [en→vi]")
    }

    @Test func returnTranslatesAtOnceAndDropsThePendingDelay() async throws {
        let translator = try await startedTranslator()
        translator.edit("Hello, how are you today?")
        translator.translate()
        let returned = translator.translation
        await fixture.translated()
        #expect(fixture.engine.requests.count == 1)
        fixture.harness.scheduler.advance(by: .seconds(1))
        #expect(translator.translation == returned)
        await settle()
        #expect(fixture.engine.requests.count == 1)
    }

    @Test func returnTranslatesTheTextTheFieldShows() async throws {
        let translator = try await startedTranslator()
        translator.submit("Hello, how are you today?")
        #expect(fixture.state.input == "Hello, how are you today?")
        await fixture.translated()
        #expect(fixture.engine.requests.map(\.text) == ["Hello, how are you today?"])
    }

    @Test func clearingTheInputClearsTheResultAtOnce() async throws {
        let translator = try await startedTranslator()
        translator.edit("Hello, how are you today?")
        translator.translate()
        await fixture.translated()
        let translated = translator.translation
        translator.edit("  ")
        #expect(fixture.state.output.isEmpty)
        #expect(fixture.state.detectedSource == nil)
        fixture.harness.scheduler.advance(by: .seconds(1))
        #expect(translator.translation == translated)
        await settle()
        #expect(fixture.engine.requests.count == 1)
    }

    @Test func onlyTheLatestResultIsShown() async throws {
        let translator = try await startedTranslator()
        fixture.engine.holds = true
        translator.edit("Hello, how are you today?")
        translator.translate()
        await eventually { fixture.engine.waiting }
        translator.edit("Good morning, my friend")
        translator.translate()
        await eventually { fixture.engine.requests.count == 2 }
        // The engine cancelled the first request; that is not an error to show.
        #expect(fixture.state.error == nil)
        #expect(fixture.state.isTranslating)
        fixture.engine.release()
        await fixture.translated()
        #expect(fixture.state.output == "Good morning, my friend [en→vi]")
        #expect(!fixture.state.isTranslating)
    }

    @Test func aSupersededResultNeverOverwritesNewerText() async throws {
        let translator = try await startedTranslator()
        fixture.engine.holds = true
        translator.edit("Hello, how are you today?")
        translator.translate()
        await eventually { fixture.engine.waiting }
        let first = translator.translation
        translator.edit("")
        fixture.engine.release()
        await first?.value
        #expect(fixture.state.output.isEmpty)
        #expect(!fixture.state.isTranslating)
    }

    @Test func failureShowsItsMessage() async throws {
        let translator = try await startedTranslator()
        fixture.engine.failure = .failed("Hỏng rồi")
        translator.edit("Hello, how are you today?")
        translator.translate()
        await fixture.translated()
        #expect(fixture.state.error == "Hỏng rồi")
        #expect(fixture.state.output.isEmpty)
        #expect(fixture.state.banner == nil)
        fixture.engine.failure = nil
        translator.translate()
        await fixture.translated()
        #expect(fixture.state.error == nil)
    }

    @Test func cancelledTranslationIsNotAnError() async throws {
        let translator = try await startedTranslator()
        fixture.engine.failure = .cancelled
        translator.edit("Hello, how are you today?")
        translator.translate()
        await fixture.translated()
        #expect(fixture.state.error == nil)
        #expect(!fixture.state.isTranslating)
    }

    @Test func bannerStaysWhileRetranslatingTheSamePair() async throws {
        let translator = try await startedTranslator()
        fixture.engine.failure = .notInstalled
        translator.edit("Hello, how are you today?")
        translator.translate()
        await fixture.translated()
        fixture.engine.holds = true
        translator.edit("Hello, how are you doing today?")
        translator.translate()
        #expect(fixture.state.banner == .notInstalled(LanguagePair(source: .en, target: .vi)))
        await eventually { fixture.engine.waiting }
        fixture.engine.release()
        await fixture.translated()
    }

    @Test func swapReversesTheDirectionAndTranslatesTheResultBack() async throws {
        let translator = try await startedTranslator()
        #expect(!fixture.state.canSwap)
        translator.edit("Hello, how are you today?")
        translator.translate()
        await fixture.translated()
        #expect(fixture.state.canSwap)
        translator.swap()
        #expect(fixture.state.source?.minimalIdentifier == "vi")
        #expect(fixture.state.target.minimalIdentifier == "en")
        #expect(fixture.state.input == "Hello, how are you today? [en→vi]")
        await fixture.translated()
        #expect(fixture.engine.requests.last == FakeEngine.Request(text: "Hello, how are you today? [en→vi]", pair: LanguagePair(source: .vi, target: .en)))
    }

    @Test func chosenSourceOverridesDetection() async throws {
        let translator = try await startedTranslator()
        translator.edit("Hello, how are you today?")
        translator.setSource(.ja)
        await fixture.translated()
        #expect(fixture.engine.requests.last?.pair == LanguagePair(source: .ja, target: .vi))
        #expect(fixture.state.detectedSource == nil)

        translator.setSource(nil)
        await fixture.translated()
        #expect(fixture.engine.requests.last?.pair == LanguagePair(source: .en, target: .vi))
        #expect(fixture.state.detectedSource?.minimalIdentifier == "en")
    }

    @Test func chosenTargetIsRememberedAndTranslatesAgain() async throws {
        let translator = try await startedTranslator()
        translator.edit("Hello, how are you today?")
        translator.setTarget(.ja)
        await fixture.translated()
        #expect(fixture.engine.requests.last?.pair == LanguagePair(source: .en, target: .ja))
        let settings = try #require(fixture.harness.settingsEnvironment(for: "translation")).settings
        #expect(settings.value(fixture.keys.targetLanguage) == "ja")
    }

    @Test func detectsAnySupportedLanguage() async throws {
        let translator = try await startedTranslator()
        await eventually { !fixture.state.languages.isEmpty }
        translator.edit("今日はとても良い天気ですね。散歩に行きましょう。")
        translator.translate()
        await fixture.translated()
        #expect(fixture.engine.requests.last?.pair == LanguagePair(source: .ja, target: .vi))
    }

    @Test func preferredPairDrivesTheFlip() async throws {
        fixture.set(PreferredPair(first: "vi", second: "ja"), for: \.preferredPair)
        let translator = try await startedTranslator()
        translator.edit("Xin chào, hôm nay trời đẹp quá")
        translator.translate()
        await fixture.translated()
        #expect(fixture.engine.requests.last?.pair == LanguagePair(source: .vi, target: .ja))
    }

    @Test func copiesTheResultToThePasteboard() async throws {
        defer { fixture.pasteboard.releaseGlobally() }
        let translator = try await startedTranslator()
        translator.edit("Hello, how are you today?")
        translator.translate()
        await fixture.translated()
        translator.copyOutput()
        #expect(fixture.pasteboard.string(forType: .string) == "Hello, how are you today? [en→vi]")
    }
}
