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

    @Test func theWholeTranslationIsWhatTheChipGets() async throws {
        let hint = await hint("\n  Good morning my friends\nand good night to everyone  \n", using: try await decider())
        // Trimmed, but every line of it: the chip wraps and scrolls it, so nothing is cut here.
        #expect(hint?.text == "Good morning my friends\nand good night to everyone [en→vi]")
    }

    @Test func aLongTranslationIsNeverCut() async throws {
        let long = String(repeating: english + ". ", count: 3)
        let hint = await hint(long, using: try await decider())
        let text = try #require(hint?.text)
        #expect(text == "\(long.trimmingCharacters(in: .whitespaces)) [en→vi]")
        #expect(text.count > SelectionHint.maxLength)
        #expect(!text.hasSuffix("…"))
    }

    @Test func aConversionKeepsItsCompactLine() async throws {
        let long = "It was 30 °C " + String(repeating: "and sunny in the park ", count: 6)
        let hint = await hint(long, using: try await decider())
        #expect(hint?.kind == .conversion)
        #expect(try #require(hint?.text).count <= SelectionHint.maxLength)
    }

    @Test func aShortTranslationIsNotCut() async throws {
        let hint = await hint("Please send me the report before the meeting tomorrow", using: try await decider())
        #expect(hint?.text == "Please send me the report before the meeting tomorrow [en→vi]")
    }

    // MARK: the preview is capped, "Mở" is not

    let sentence = "The quick brown fox jumps over the lazy dog. "

    @Test func aPreviewTranslatesAtMostSixHundredCharacters() async throws {
        #expect(SelectionDecider.previewLimit == 600)
        let long = String(repeating: sentence, count: 30)
        #expect(long.count > 1_300)
        let hint = await hint(long, using: try await decider())
        let sent = try #require(fixture.previewEngine.requests.first?.text)
        #expect(sent.count <= 600)
        #expect(sent.count > 500)
        #expect(sent.hasSuffix("dog."), "cut after a whole sentence")
        #expect(hint?.kind == .translation)
    }

    @Test func aCutPreviewSaysSoWithAnEllipsisAndANote() async throws {
        let hint = await hint(String(repeating: sentence, count: 30), using: try await decider())
        let text = try #require(hint?.text)
        #expect(text.hasSuffix("…"))
        #expect(hint?.note == "Mở để dịch đủ")
    }

    @Test func aWholePreviewHasNoEllipsisAndNoNote() async throws {
        let hint = await hint(String(repeating: sentence, count: 5), using: try await decider())
        #expect(hint?.note == nil)
        #expect(try #require(hint?.text).hasSuffix("[en→vi]"))
        #expect(fixture.previewEngine.requests.first?.text.count == String(repeating: sentence, count: 5).count - 1)
    }

    @Test func openingTranslatesTheWholeSelection() async throws {
        await fixture.start()
        let long = String(repeating: sentence, count: 30).trimmingCharacters(in: .whitespaces)
        await fixture.dragSelecting(long)
        try #require(fixture.chipWindow.current).content.open()
        await fixture.translated()
        #expect(fixture.engine.requests.first?.text == long)
        #expect(fixture.state.input == long)
    }

    @Test func theCutIsAtTheLastSentenceEndThatIsFarEnoughIn() {
        let text = String(repeating: sentence, count: 30)
        let cut = SelectionDecider.previewCut(of: text, limit: 600)
        #expect(cut.wasCut)
        #expect(cut.text.hasSuffix("dog."))
        #expect(cut.text.count <= 600)
        #expect(text.hasPrefix(cut.text))
    }

    @Test func aNewlineIsASentenceEndToo() {
        let text = (1...60).map { "Line number \($0) of the text without a full stop" }.joined(separator: "\n")
        let cut = SelectionDecider.previewCut(of: text, limit: 600)
        #expect(cut.wasCut)
        #expect(cut.text.count <= 600)
        #expect(cut.text.hasSuffix("full stop"), "\(cut.text.suffix(20))")
    }

    @Test func withoutASentenceEndTheCutIsAtAWord() {
        let text = String(repeating: "lorem ipsum dolor sit amet ", count: 60)
        let cut = SelectionDecider.previewCut(of: text, limit: 600)
        #expect(cut.wasCut)
        #expect(cut.text.count <= 600)
        #expect(cut.text.hasSuffix("amet") || cut.text.hasSuffix("sit") || cut.text.hasSuffix("dolor") || cut.text.hasSuffix("ipsum") || cut.text.hasSuffix("lorem"))
    }

    @Test func aTextWithNoBoundaryIsCutAtTheLimit() {
        let text = String(repeating: "a", count: 1_000)
        let cut = SelectionDecider.previewCut(of: text, limit: 600)
        #expect(cut.text.count == 600)
        #expect(cut.wasCut)
    }

    @Test func aChineseSentenceEndCounts() {
        let text = String(repeating: "今天天气很好，我们一起去公园散步吧。", count: 60)
        let cut = SelectionDecider.previewCut(of: text, limit: 600)
        #expect(cut.wasCut)
        #expect(cut.text.hasSuffix("。"))
    }

    @Test func aShortTextIsNotCut() {
        let cut = SelectionDecider.previewCut(of: "Hello there my friend", limit: 600)
        #expect(!cut.wasCut)
        #expect(cut.text == "Hello there my friend")
    }

    @Test func aSentenceEndTooEarlyToBeWorthItIsNotUsed() {
        // The only full stop is at the start: cutting there would translate almost nothing.
        let text = "Hi. " + String(repeating: "word ", count: 300)
        let cut = SelectionDecider.previewCut(of: text, limit: 600)
        #expect(cut.text.count > 400)
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

    // MARK: a preview that cannot be made

    @Test func aMissingLanguagePackStillOffersTheTranslateButton() async throws {
        fixture.previewEngine.failure = .notInstalled
        let hint = await hint(english, using: try await decider())
        #expect(hint?.kind == .button)
        #expect(hint?.text == "Cần tải gói ngôn ngữ")
        #expect(hint?.source.text == english)
    }

    @Test(arguments: [TranslationFailure.unsupported, .failed("boom")])
    func aPreviewThatFailsOtherwiseStillOffersTheButtonWithNoNote(failure: TranslationFailure) async throws {
        fixture.previewEngine.failure = failure
        let hint = await hint(english, using: try await decider())
        #expect(hint?.kind == .button)
        #expect(hint?.text == "")
    }

    @Test func aPreviewThatWasSupersededShowsNothing() async throws {
        fixture.previewEngine.failure = .cancelled
        #expect(await hint(english, using: try await decider()) == nil)
    }

    @Test func theButtonIsOnlyForTextThatWouldHaveBeenPreviewed() async throws {
        fixture.previewEngine.failure = .notInstalled
        let decider = try await decider()
        // Not foreign, not enough of it, not prose: no button either.
        #expect(await hint("Hôm nay trời đẹp quá, chúng ta đi dạo nhé", using: decider) == nil)
        #expect(await hint("Hello", using: decider) == nil)
        #expect(await hint("https://example.com/a/b", using: decider) == nil)
        #expect(await hint("let value = compute(input)", using: decider) == nil)
    }

    @Test func aQuantityNeverNeedsTheLanguagePack() async throws {
        fixture.previewEngine.failure = .notInstalled
        let hint = await hint("5 ft 11 in", using: try await decider())
        #expect(hint?.kind == .conversion)
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
