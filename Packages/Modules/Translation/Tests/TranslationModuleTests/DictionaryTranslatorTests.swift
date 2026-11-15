import Foundation
import Testing
@testable import TranslationModule

/// The dictionary card next to the translation: when it is asked for, what clears it, and its button.
@Suite struct DictionaryTranslatorTests {
    let fixture = ModuleFixture()

    func startedTranslator() async throws -> Translator {
        await fixture.start()
        return try #require(fixture.module.translator)
    }

    /// Types `text`, then waits for the translation and for the lookup beside it.
    func submit(_ translator: Translator, _ text: String) async {
        translator.submit(text)
        await fixture.translated()
        await translator.lookup?.value
    }

    @Test func aWordShowsItsCardBesideTheTranslation() async throws {
        fixture.dictionary.definitions["hello"] = DictionarySamples.hello
        let translator = try await startedTranslator()
        await submit(translator, "hello")
        let entry = try #require(fixture.state.dictionary)
        #expect(entry.headword == "hello")
        #expect(entry.partOfSpeech == "exclamation")
        #expect(entry.senses.count == 3)
        #expect(fixture.state.output.hasPrefix("hello ["))
        #expect(fixture.state.showsDictionary)
    }

    @Test func aShortPhraseIsLookedUpAndALongerTextIsNot() async throws {
        fixture.dictionary.definitions["good morning"] = DictionarySamples.goodMorning
        let translator = try await startedTranslator()
        await submit(translator, "good morning")
        #expect(fixture.state.dictionary?.headword == "good morning")

        fixture.dictionary.definitions["good morning my friend"] = DictionarySamples.goodMorning
        await submit(translator, "good morning my friend")
        #expect(fixture.state.dictionary == nil)
        #expect(fixture.dictionary.requests == ["good morning"])
    }

    @Test func aNewTextDropsTheOldCard() async throws {
        fixture.dictionary.definitions["hello"] = DictionarySamples.hello
        let translator = try await startedTranslator()
        await submit(translator, "hello")
        #expect(fixture.state.dictionary != nil)
        await submit(translator, "zzyzx")
        #expect(fixture.state.dictionary == nil)
        #expect(fixture.state.output.hasPrefix("zzyzx ["))
    }

    @Test func clearingTheInputDropsTheCard() async throws {
        fixture.dictionary.definitions["hello"] = DictionarySamples.hello
        let translator = try await startedTranslator()
        await submit(translator, "hello")
        translator.edit("")
        #expect(fixture.state.dictionary == nil)
    }

    @Test func aLookupOfOlderTextNeverOverwritesTheNewer() async throws {
        fixture.dictionary.definitions["hello"] = DictionarySamples.hello
        fixture.dictionary.definitions["good morning"] = DictionarySamples.goodMorning
        let translator = try await startedTranslator()
        fixture.dictionary.holds = true
        translator.submit("hello")
        let first = translator.lookup
        await eventuallyAfterWaiting { fixture.dictionary.waiting == 1 }
        fixture.dictionary.holds = false
        translator.submit("good morning")
        await fixture.translated()
        await translator.lookup?.value
        #expect(fixture.state.dictionary?.headword == "good morning")
        // The held answer arrives after the newer one was shown.
        fixture.dictionary.release()
        await first?.value
        #expect(fixture.state.dictionary?.headword == "good morning")
    }

    @Test func aQuantityIsNotLookedUp() async throws {
        let translator = try await startedTranslator()
        await submit(translator, "72 °F")
        #expect(fixture.state.showsConversionsOnly)
        #expect(fixture.dictionary.requests.isEmpty)
        #expect(fixture.state.dictionary == nil)
    }

    @Test func nothingIsLookedUpWhenTheTextIsNotTranslated() async {
        fixture.set(false, for: \.autoTranslateOnOpen)
        await fixture.start()
        #expect(fixture.harness.services.handle(name: "translate", text: "hello"))
        await settle()
        #expect(fixture.state.input == "hello")
        #expect(fixture.dictionary.requests.isEmpty)
        #expect(fixture.state.dictionary == nil)
    }

    @Test func aSelectionFromTheShortcutGetsACard() async {
        fixture.dictionary.definitions["hello"] = DictionarySamples.hello
        await fixture.start()
        fixture.accessibility.selections = ["hello"]
        await fixture.pressShortcutAndRead()
        await fixture.translated()
        await fixture.module.translator?.lookup?.value
        #expect(fixture.state.dictionary?.headword == "hello")
    }

    @Test func theCardNeverShowsOverAQuantityOnlyResult() {
        fixture.state.dictionary = DictionaryEntry(term: "hello", headword: "hello", partOfSpeech: nil, senses: ["x"])
        #expect(fixture.state.showsDictionary)
        fixture.state.showsConversionsOnly = true
        #expect(!fixture.state.showsDictionary)
    }

    @Test func stoppingDropsTheCardAndTheLookupInFlight() async throws {
        fixture.dictionary.definitions["hello"] = DictionarySamples.hello
        let translator = try await startedTranslator()
        await submit(translator, "hello")
        #expect(fixture.state.dictionary != nil)

        fixture.dictionary.holds = true
        translator.submit("hello")
        let lookup = translator.lookup
        await eventuallyAfterWaiting { fixture.dictionary.waiting == 1 }
        await fixture.harness.registry.setEnabled(false, for: "translation")
        #expect(fixture.state.dictionary == nil)
        fixture.dictionary.release()
        await lookup?.value
        #expect(fixture.state.dictionary == nil)
    }

    @Test func theButtonOpensTheDictionaryAtTheWordAndClosesTheNotch() async throws {
        fixture.dictionary.definitions["good morning"] = DictionarySamples.goodMorning
        let translator = try await startedTranslator()
        await submit(translator, "good morning")
        fixture.module.openInDictionary()
        #expect(fixture.opener.opened == [URL(string: "dict://good%20morning")!])
        // Dictionary comes to the front over the notch.
        #expect(fixture.harness.presenter.closeCount == 1)
    }

    @Test func withoutACardTheButtonDoesNothing() async throws {
        await fixture.start()
        fixture.module.openInDictionary()
        #expect(fixture.opener.opened.isEmpty)
        #expect(fixture.harness.presenter.closeCount == 0)
    }

    @Test func nothingReachesTheNetwork() async throws {
        fixture.dictionary.definitions["hello"] = DictionarySamples.hello
        let translator = try await startedTranslator()
        await submit(translator, "hello")
        #expect(fixture.ratesClient.requests.isEmpty)
    }
}
