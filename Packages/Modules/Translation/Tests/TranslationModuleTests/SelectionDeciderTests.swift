import Foundation
import MyNotchCore
import Testing
@testable import TranslationModule

/// What a selection is worth showing: a conversion, a translation preview, or nothing.
@Suite struct SelectionDeciderTests {
    let fixture = ModuleFixture()
    let safari = FocusedApplication(processID: 42, bundleID: "com.apple.Safari")
    let english = "The quick brown fox jumps over the lazy dog"

    func decider() async throws -> SelectionDecider {
        await fixture.start()
        return try #require(fixture.module.smartSelection).decider
    }

    func hint(_ text: String, using decider: SelectionDecider) async -> SelectionHint? {
        await decider.hint(for: SelectionSource(text: text, application: safari))
    }

    // MARK: quick convert comes first

    @Test func aQuantityIsConvertedAndNothingIsTranslated() async throws {
        let decider = try await decider()
        let hint = await hint("5 ft 11 in", using: decider)
        #expect(hint?.kind == .conversion)
        #expect(hint?.text == "5 ft 11 in → 180 cm")
        #expect(hint?.source.text == "5 ft 11 in")
        #expect(fixture.previewEngine.requests.isEmpty)
    }

    @Test func aCalculationShowsItsAnswer() async throws {
        let hint = await hint("(2+3)*4", using: try await decider())
        #expect(hint?.kind == .conversion)
        #expect(hint?.text == "(2+3)*4 = 20")
    }

    @Test func aZonedTimeShowsItsFirstConversion() async throws {
        let hint = await hint("3pm PST", using: try await decider())
        #expect(hint?.kind == .conversion)
        #expect(hint?.text.hasPrefix("3pm PST → Giờ máy") == true)
    }

    @Test func aQuantityInsideAForeignSentenceIsStillConvertedFirst() async throws {
        let hint = await hint("It was 30 °C outside yesterday afternoon", using: try await decider())
        #expect(hint?.kind == .conversion)
        #expect(hint?.text.hasPrefix("30 °C → ") == true)
        #expect(fixture.previewEngine.requests.isEmpty)
    }

    @Test func aPriceIsConvertedWhenCurrencyIsOn() async throws {
        fixture.set(true, for: \.convertCurrency)
        fixture.ratesClient.reply(RatesReplies.success(["USD": 1, "VND": 25_000]))
        let hint = await hint("$12", using: try await decider())
        #expect(hint?.kind == .conversion)
        #expect(hint?.text == "$12 → 300.000 ₫")
    }

    @Test func aPriceIsNothingWhenCurrencyIsOffAndNoRatesAreAsked() async throws {
        fixture.ratesClient.reply(RatesReplies.success())
        #expect(await hint("$12", using: try await decider()) == nil)
        #expect(fixture.ratesClient.requests.isEmpty)
        #expect(fixture.previewEngine.requests.isEmpty)
    }

    @Test func aPriceWithNoRatesShowsNothing() async throws {
        fixture.set(true, for: \.convertCurrency)   // the fake source is down
        #expect(await hint("$12", using: try await decider()) == nil)
        #expect(fixture.previewEngine.requests.isEmpty)
    }

    @Test func aLongTextWithDigitsIsNotLookedAtForQuantities() async throws {
        let long = String(repeating: english + ". ", count: 6) + "5 kg"
        #expect(long.count > QuantityRecognizer.maxSelectionLength)
        let hint = await hint(long, using: try await decider())
        #expect(hint?.kind == .translation)
    }

    // MARK: foreign text

    @Test func foreignTextGetsAPreviewFromTheOnDeviceEngine() async throws {
        let hint = await hint(english, using: try await decider())
        #expect(hint?.kind == .translation)
        #expect(hint?.text == "\(english) [en→vi]")
        #expect(hint?.source == SelectionSource(text: english, application: safari))
        #expect(fixture.previewEngine.requests == [.init(text: english, pair: LanguagePair(source: .en, target: .vi))])
    }

    @Test func thePreviewNeverUsesTheTabsEngine() async throws {
        _ = await hint(english, using: try await decider())
        #expect(fixture.engine.requests.isEmpty)
    }

    @Test func theTargetIsTheOneInSettings() async throws {
        fixture.set("ja", for: \.targetLanguage)
        let hint = await hint(english, using: try await decider())
        #expect(hint?.text == "\(english) [en→ja]")
    }

    @Test func textInTheTargetLanguageShowsNothing() async throws {
        let decider = try await decider()
        #expect(await hint("Hôm nay trời đẹp quá, chúng ta đi dạo nhé", using: decider) == nil)
        fixture.set("en", for: \.targetLanguage)
        #expect(await hint(english, using: decider) == nil)
        #expect(fixture.previewEngine.requests.isEmpty)
    }

    @Test func oneWordIsNotPreviewed() async throws {
        #expect(await hint("Hello", using: try await decider()) == nil)
        #expect(fixture.previewEngine.requests.isEmpty)
    }

    @Test func fourJapaneseCharactersAreEnough() async throws {
        let hint = await hint("こんにちは世界", using: try await decider())
        #expect(hint?.kind == .translation)
        #expect(fixture.previewEngine.requests.first?.pair == LanguagePair(source: .ja, target: .vi))
    }

    @Test func aLanguageNobodyCanTranslateShowsNothing() async throws {
        // Korean is not among the languages the fixture's Translation supports.
        #expect(await hint("안녕하세요 여러분 만나서 반갑습니다", using: try await decider()) == nil)
        #expect(fixture.previewEngine.requests.isEmpty)
    }

    @Test func aTrimmedFirstLineIsWhatTheChipShows() async throws {
        let hint = await hint("\n  Good morning my friends\nand good night to everyone  \n", using: try await decider())
        #expect(hint?.text == "Good morning my friends")
    }

    @Test func aLongTranslationIsCut() async throws {
        let long = String(repeating: english + ". ", count: 3)
        let hint = await hint(long, using: try await decider())
        let text = try #require(hint?.text)
        #expect(text.count == SelectionHint.maxLength)
        #expect(text.hasSuffix("…"))
        #expect(text.hasPrefix("The quick brown fox"))
    }

    @Test func aShortTranslationIsNotCut() async throws {
        let hint = await hint("Please send me the report before the meeting tomorrow", using: try await decider())
        #expect(hint?.text == "Please send me the report before the meeting tomorrow [en→vi]")
    }

    @Test func aLongSelectionIsOnlyTranslatedAsFarAsThePreviewNeeds() async throws {
        let long = String(repeating: english + ". ", count: 25)
        #expect(long.count > SelectionDecider.previewLimit)
        let hint = await hint(long, using: try await decider())
        #expect(fixture.previewEngine.requests.first?.text.count == SelectionDecider.previewLimit)
        #expect(hint?.kind == .translation)
        #expect(try #require(hint?.text).count <= SelectionHint.maxLength)
    }

    @Test func aShortSelectionIsTranslatedWhole() async throws {
        _ = await hint(english, using: try await decider())
        #expect(fixture.previewEngine.requests.first?.text == english)
    }

    // MARK: only an on-device engine can make a preview

    @Test func onlyAppleIsAnOnDeviceEngine() {
        func isOnDevice(_ engine: any TranslationEngine) -> Bool { engine is any OnDeviceTranslationEngine }
        #expect(isOnDevice(AppleTranslationEngine()))
        let remote = RemoteEngines(keys: fixture.keyStore, transport: fixture.transport, log: fixture.engineLog, config: { EngineConfig() })
        for choice in EngineChoice.allCases where choice != .apple {
            let engine = remote.engine(for: choice)
            #expect(engine != nil)
            #expect(engine.map(isOnDevice) == false, "\(choice)")
        }
    }

    // MARK: failures show nothing

    @Test(arguments: [TranslationFailure.notInstalled, .unsupported, .cancelled, .failed("boom")])
    func aPreviewThatFailsShowsNothing(failure: TranslationFailure) async throws {
        fixture.previewEngine.failure = failure
        #expect(await hint(english, using: try await decider()) == nil)
    }

    // MARK: nothing leaves the Mac on its own

    @Test func aRemoteEngineChosenInSettingsIsNeverAskedForAPreview() async throws {
        _ = fixture.keyStore.save("fake-key", for: .googleKey)
        _ = fixture.keyStore.save("fake-key", for: .microsoftKey)
        _ = fixture.keyStore.save("fake-key", for: .openAIKey)
        let decider = try await decider()
        for choice in ["google", "microsoft", "openai"] {
            fixture.set(choice, for: \.engine)
            let hint = await hint(english, using: decider)
            #expect(hint?.kind == .translation, "\(choice)")
        }
        #expect(fixture.transport.requests.isEmpty)
        #expect(fixture.keyStore.loadCount == 0)
        #expect(fixture.previewEngine.requests.count == 3)
    }
}
