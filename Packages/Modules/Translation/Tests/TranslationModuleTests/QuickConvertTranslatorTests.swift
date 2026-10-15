import AppKit
import Foundation
import MyNotchCore
import Testing
@testable import TranslationModule

/// The quick convert as the tab sees it: the translator's state for a text that is a quantity.
@Suite struct QuickConvertTranslatorTests {
    let fixture = ModuleFixture()
    /// What the rates source answers on 15 January 2026: the day's rates, dated that morning.
    let updated = utc("2026-01-15T00:02:31Z").timeIntervalSince1970

    func startedTranslator() async throws -> Translator {
        await fixture.start()
        return try #require(fixture.module.translator)
    }

    func lines(_ conversion: Conversion) -> [String] {
        guard case .lines(let lines) = conversion.outcome else { return [] }
        return lines.map(\.text)
    }

    /// Types `text` and waits until it has been read for quantities (and translated, when it is not just one).
    func submit(_ translator: Translator, _ text: String) async {
        translator.submit(text)
        await fixture.translated()
    }

    func fullLines(_ conversion: Conversion) -> [ConversionLine] {
        guard case .lines(let lines) = conversion.outcome else {
            Issue.record("no lines in \(conversion)")
            return []
        }
        return lines
    }

    func enableCurrency() {
        fixture.set(true) { $0.convertCurrency }
        fixture.ratesClient.reply(RatesReplies.success(["USD": 1, "VND": 25_000, "EUR": 0.9, "JPY": 150], updated: updated))
    }

    @Test func aUnitIsConvertedAndNotTranslated() async throws {
        let translator = try await startedTranslator()
        translator.submit("5 ft 11 in")
        await fixture.translated()
        #expect(fixture.state.conversions.map(\.source) == ["5 ft 11 in"])
        #expect(lines(fixture.state.conversions[0]) == ["180 cm"])
        #expect(fixture.state.showsConversionsOnly)
        #expect(fixture.state.output.isEmpty)
        #expect(!fixture.state.isTranslating)
        #expect(fixture.state.error == nil)
        await settle()
        #expect(fixture.engine.requests.isEmpty)
    }

    @Test func theBriefsExamplesAsTyped() async throws {
        let translator = try await startedTranslator()
        for (text, expected) in [("72 °F", "22,2 °C"), ("2 lb", "0,91 kg"), ("5 ft 11 in", "180 cm")] {
            await submit(translator, text)
            #expect(lines(fixture.state.conversions[0]) == [expected], "\(text)")
        }
    }

    @Test func anExpressionIsCalculated() async throws {
        let translator = try await startedTranslator()
        await submit(translator, "2 + 3 × 4")
        #expect(fixture.state.conversions.map(\.source) == ["2 + 3 × 4 ="])
        #expect(lines(fixture.state.conversions[0]) == ["14"])
        await submit(translator, "1.234,5 * 2")
        #expect(lines(fixture.state.conversions[0]) == ["2.469"])
        await submit(translator, "10 / 4")
        #expect(lines(fixture.state.conversions[0]) == ["2,5"])
        await settle()
        #expect(fixture.engine.requests.isEmpty)
    }

    @Test func aTimeIsShownInTheUsersZoneAndTheChosenOnes() async throws {
        let translator = try await startedTranslator()
        await submit(translator, "3pm PST")
        let conversion = try #require(fixture.state.conversions.first)
        let result = fullLines(conversion)
        // Winter: 15:00 PST is 23:00 UTC. Hanoi is the user's zone; London and Los Angeles the defaults, and Los Angeles
        // is where the time was written, so it is left out.
        #expect(result.map(\.text) == ["06:00 (hôm sau)", "23:00"])
        #expect(result.map(\.label) == ["Giờ máy · UTC+7", "London · UTC+0"])
        #expect(conversion.note == "Hiểu là 15:00, Los Angeles · UTC-8")
    }

    @Test func theChosenZonesComeFromSettings() async throws {
        let translator = try await startedTranslator()
        fixture.set("Asia/Tokyo") { $0.firstZone }
        fixture.set("America/New_York") { $0.secondZone }
        await submit(translator, "9h sáng giờ Hà Nội")
        #expect(lines(fixture.state.conversions[0]) == ["11:00", "21:00 (hôm trước)"])
        // Changed in Settings while the tab is open: the next text uses the new choice.
        fixture.set("Europe/London") { $0.secondZone }
        await submit(translator, "9h sáng giờ Hà Nội")
        #expect(lines(fixture.state.conversions[0]) == ["11:00", "02:00"])
        // A zone that does not exist is skipped.
        fixture.set("Nowhere/Land") { $0.firstZone }
        await submit(translator, "9h sáng giờ Hà Nội")
        #expect(lines(fixture.state.conversions[0]) == ["02:00"])
    }

    @Test func aSentenceWithAQuantityIsTranslatedWithTheConversionAbove() async throws {
        let translator = try await startedTranslator()
        translator.submit("The room is 5 kg heavier, so be careful")
        #expect(fixture.state.isTranslating)
        await fixture.translated()
        #expect(fixture.state.conversions.map(\.source) == ["5 kg"])
        #expect(lines(fixture.state.conversions[0]) == ["11 lb"])
        #expect(!fixture.state.showsConversionsOnly)
        #expect(fixture.engine.requests.map(\.text) == ["The room is 5 kg heavier, so be careful"])
        #expect(fixture.state.output == "The room is 5 kg heavier, so be careful [en→vi]")
        #expect(fixture.state.conversions.count == 1)
    }

    @Test func aTextWithoutQuantitiesHasNoConversions() async throws {
        let translator = try await startedTranslator()
        translator.submit("Hello, how are you today?")
        await fixture.translated()
        #expect(fixture.state.conversions.isEmpty)
        #expect(!fixture.state.showsConversionsOnly)
        #expect(fixture.state.output == "Hello, how are you today? [en→vi]")
    }

    @Test func aQuantityAfterATranslationReplacesItsResult() async throws {
        let translator = try await startedTranslator()
        fixture.engine.failure = .notInstalled
        translator.submit("Hello, how are you today?")
        await fixture.translated()
        #expect(fixture.state.banner != nil)
        fixture.engine.failure = nil
        await submit(translator, "72 °F")
        #expect(fixture.state.output.isEmpty)
        #expect(fixture.state.banner == nil)
        #expect(fixture.state.detectedSource == nil)
        #expect(fixture.state.showsConversionsOnly)
        // Back to words: the conversions are gone and the translation is back.
        translator.submit("Good morning, my friend")
        await fixture.translated()
        #expect(fixture.state.conversions.isEmpty)
        #expect(!fixture.state.showsConversionsOnly)
        #expect(fixture.state.output == "Good morning, my friend [en→vi]")
    }

    @Test func aTranslationInFlightNeverShowsOverAQuantity() async throws {
        let translator = try await startedTranslator()
        fixture.engine.holds = true
        translator.submit("Hello, how are you today?")
        await eventually { fixture.engine.waiting }
        translator.submit("72 °F")
        await fixture.translated()
        #expect(!fixture.state.isTranslating)
        fixture.engine.release()
        await settle()
        #expect(fixture.state.output.isEmpty)
        #expect(lines(fixture.state.conversions[0]) == ["22,2 °C"])
    }

    @Test func blankingTheInputClearsTheConversions() async throws {
        let translator = try await startedTranslator()
        await submit(translator, "72 °F")
        #expect(!fixture.state.conversions.isEmpty)
        translator.edit("  ")
        #expect(fixture.state.conversions.isEmpty)
        #expect(!fixture.state.showsConversionsOnly)
        await submit(translator, "72 °F")
        translator.receive(nil, translate: false)
        #expect(fixture.state.conversions.isEmpty)
        await submit(translator, "72 °F")
        translator.receive("Hello, how are you today?", translate: false)
        #expect(fixture.state.conversions.isEmpty)
        #expect(!fixture.state.showsConversionsOnly)
    }

    @Test func typingConvertsAfterThePause() async throws {
        let translator = try await startedTranslator()
        translator.edit("72 °F")
        #expect(fixture.state.conversions.isEmpty)
        fixture.harness.scheduler.advance(by: .milliseconds(600))
        await fixture.translated()
        #expect(lines(fixture.state.conversions[0]) == ["22,2 °C"])
    }

    @Test func aSelectionThatIsAQuantityIsConvertedAndOffersNoReplacement() async throws {
        await fixture.start()
        fixture.accessibility.selections = ["72 °F"]
        await fixture.pressShortcutAndRead()
        await fixture.translated()
        #expect(lines(fixture.state.conversions[0]) == ["22,2 °C"])
        #expect(fixture.state.output.isEmpty)
        #expect(fixture.state.selectionSource != nil)
        #expect(!fixture.state.showsReplace)
        await settle()
        #expect(fixture.engine.requests.isEmpty)
    }

    @Test func servicesTextThatIsAQuantityIsConvertedToo() async throws {
        await fixture.start()
        #expect(fixture.harness.services.handle(name: "translate", text: "2 lb"))
        await fixture.translated()
        #expect(lines(fixture.state.conversions[0]) == ["0,91 kg"])
        #expect(fixture.engine.requests.isEmpty)
    }

    @Test func zeroOfSomethingIsTranslatedNotConverted() async throws {
        let translator = try await startedTranslator()
        translator.submit("0 kg")
        await fixture.translated()
        #expect(fixture.state.conversions.isEmpty)
        #expect(fixture.engine.requests.map(\.text) == ["0 kg"])
    }

    @Test func copiesOneResult() async throws {
        let translator = try await startedTranslator()
        await submit(translator, "3pm PST")
        let result = fullLines(fixture.state.conversions[0])
        translator.copy(result[1].text)
        #expect(fixture.pasteboard.string(forType: .string) == "23:00")
        translator.copy("")
        #expect(fixture.pasteboard.string(forType: .string) == "23:00")
    }

    @Test func stoppingTheModuleClearsThem() async throws {
        let translator = try await startedTranslator()
        await submit(translator, "72 °F")
        await fixture.harness.registry.setEnabled(false, for: "translation")
        #expect(fixture.state.conversions.isEmpty)
        #expect(!fixture.state.showsConversionsOnly)
    }

    @Test func aSelectionOfMoreThan200CharactersIsJustTranslatedAndNeverRead() async throws {
        let translator = try await startedTranslator()
        let long = String(repeating: "Mua 5 kg gạo và 3 lb đường. ", count: 72)
        #expect(long.count > 2000)
        await submit(translator, long)
        #expect(fixture.recognizer.calls.isEmpty)
        #expect(fixture.state.conversions.isEmpty)
        #expect(!fixture.state.showsConversionsOnly)
        #expect(fixture.engine.requests.map(\.text) == [long])
        #expect(fixture.state.output == "\(long) [vi→en]")
        // One character over the limit is not read either; the limit itself is.
        let limit = QuantityRecognizer.maxSelectionLength
        let atLimit = "5 kg " + String(repeating: "x", count: limit - 5)
        let over = atLimit + "x"
        #expect(atLimit.count == limit && over.count == limit + 1)
        await submit(translator, over)
        #expect(fixture.recognizer.calls.isEmpty)
        await submit(translator, atLimit)
        #expect(fixture.recognizer.calls == [atLimit])
    }

    @Test func aTextWithoutADigitIsNeverRead() async throws {
        let translator = try await startedTranslator()
        await submit(translator, "Hello, how are you today?")
        #expect(fixture.recognizer.calls.isEmpty)
        #expect(fixture.state.output == "Hello, how are you today? [en→vi]")
        await submit(translator, "Chiều 5h anh qua đón em nhé")
        #expect(fixture.recognizer.calls == ["Chiều 5h anh qua đón em nhé"])
    }

    @Test func aShortTextIsReadOffTheMainThread() async throws {
        let translator = try await startedTranslator()
        await submit(translator, "5 ft 11 in")
        #expect(fixture.recognizer.calls == ["5 ft 11 in"])
        #expect(!fixture.recognizer.ranOnTheMainThread)
        #expect(lines(fixture.state.conversions[0]) == ["180 cm"])
    }

    @Test func aNewSelectionCancelsTheReadingInFlight() async throws {
        let translator = try await startedTranslator()
        fixture.recognizer.holdFirstCall()
        translator.submit("5 kg")
        let first = translator.translation
        await eventuallyOnAnotherThread { fixture.recognizer.calls.count == 1 }
        // While the first is still being read, a newer selection arrives and is read at once.
        translator.submit("7 lb")
        await fixture.translated()
        #expect(fixture.state.conversions.map(\.source) == ["7 lb"])
        #expect(lines(fixture.state.conversions[0]) == ["3,18 kg"])
        // The first finishes late and changes nothing.
        fixture.recognizer.release()
        await first?.value
        await settle()
        #expect(fixture.state.conversions.map(\.source) == ["7 lb"])
        #expect(fixture.state.showsConversionsOnly)
        #expect(fixture.engine.requests.isEmpty)
    }

    @Test func whileAQuantityIsBeingReadTheTabKeepsWhatItShowed() async throws {
        let translator = try await startedTranslator()
        await submit(translator, "72 °F")
        #expect(lines(fixture.state.conversions[0]) == ["22,2 °C"])
        // The next reading is held, like a slow one.
        fixture.recognizer.holdFirstCall()
        translator.submit("73 °F")
        await eventuallyOnAnotherThread { fixture.recognizer.calls.count == 2 }
        #expect(fixture.state.isTranslating)
        #expect(lines(fixture.state.conversions[0]) == ["22,2 °C"])
        fixture.recognizer.release()
        await fixture.translated()
        #expect(lines(fixture.state.conversions[0]) == ["22,8 °C"])
        #expect(!fixture.state.isTranslating)
    }

    @Test func conversionsDoNotNeedTheNetwork() async throws {
        let translator = try await startedTranslator()
        for text in ["5 ft 11 in", "72 °F", "3pm PST", "2+2", "I weigh 70 kg"] { translator.submit(text) }
        await settle()
        #expect(fixture.ratesClient.requests.isEmpty)
    }
}

@Suite struct CurrencyConvertTranslatorTests {
    let fixture = ModuleFixture()
    let updated = utc("2026-01-15T00:02:31Z").timeIntervalSince1970

    func startedTranslator() async throws -> Translator {
        await fixture.start()
        return try #require(fixture.module.translator)
    }

    func enableCurrency(rates: [String: Double] = ["USD": 1, "VND": 25_000, "EUR": 0.9, "JPY": 150]) {
        fixture.set(true) { $0.convertCurrency }
        fixture.ratesClient.reply(RatesReplies.success(rates, updated: updated))
    }

    func lines(_ conversion: Conversion) -> [String] {
        guard case .lines(let lines) = conversion.outcome else { return [] }
        return lines.map(\.text)
    }

    /// Types `text` and waits for it to be read, and for the rates its amounts wait for.
    func submit(_ translator: Translator, _ text: String) async {
        translator.submit(text)
        await fixture.translated()
        await translator.conversion?.value
    }

    @Test func isOffByDefaultAndNeverTouchesTheNetwork() async throws {
        #expect(fixture.keys.convertCurrency.defaultValue == false)
        let translator = try await startedTranslator()
        fixture.ratesClient.reply(RatesReplies.success())
        for text in ["$12", "12 USD", "€5", "100.000đ", "I paid 12 USD for it"] {
            translator.submit(text)
            await fixture.translated()
        }
        #expect(fixture.ratesClient.requests.isEmpty)
        #expect(fixture.state.conversions.isEmpty)
        // They are plain text then, and translated.
        #expect(fixture.engine.requests.map(\.text) == ["$12", "12 USD", "€5", "100.000đ", "I paid 12 USD for it"])
    }

    @Test func convertsAnAmountIntoTheUsersCurrency() async throws {
        let translator = try await startedTranslator()
        enableCurrency()
        // The rates are asked for and have not come yet.
        let gate = Gate()
        fixture.ratesClient.handler = { [updated] _ in
            await gate.wait()
            return RatesReplies.success(["USD": 1, "VND": 25_000], updated: updated)
        }
        translator.submit("$12")
        await fixture.translated()
        #expect(fixture.state.conversions.map(\.outcome) == [.fetching])
        #expect(fixture.state.conversions[0].creditsRates)
        #expect(fixture.state.showsConversionsOnly)
        await eventuallyOnAnotherThread { gate.isWaiting }
        gate.open()
        await translator.conversion?.value
        let conversion = try #require(fixture.state.conversions.first)
        #expect(conversion.source == "$12")
        #expect(lines(conversion) == ["300.000 ₫"])
        #expect(conversion.note == "Tỷ giá ngày 15/01/2026")
        #expect(fixture.ratesClient.requests == [ExchangeRateService.endpoint])
        #expect(fixture.state.output.isEmpty)
        #expect(fixture.engine.requests.isEmpty)
    }

    @Test(arguments: [
        ("12 USD", "300.000 ₫"), ("€5", "138.889 ₫"), ("¥1500", "250.000 ₫"), ("1 USD", "25.000 ₫"), ("12 đô", "300.000 ₫"),
        ("5 euro", "138.889 ₫"), ("USD 0,5", "12.500 ₫"),
    ])
    func convertsEachCurrency(text: String, expected: String) async throws {
        let translator = try await startedTranslator()
        enableCurrency()
        await submit(translator, text)
        #expect(lines(fixture.state.conversions[0]) == [expected])
    }

    @Test func anAmountInTheUsersCurrencyIsShownInDollars() async throws {
        let translator = try await startedTranslator()
        enableCurrency()
        await submit(translator, "100.000đ")
        #expect(lines(fixture.state.conversions[0]) == ["4,00 USD"])
        // A user of dollars sees euros for dollars.
        fixture.set("USD") { $0.currencyTarget }
        await submit(translator, "$12")
        #expect(lines(fixture.state.conversions[0]) == ["10,80 EUR"])
    }

    @Test func theTargetCurrencyComesFromSettings() async throws {
        let translator = try await startedTranslator()
        enableCurrency()
        fixture.set("EUR") { $0.currencyTarget }
        await submit(translator, "12 USD")
        #expect(lines(fixture.state.conversions[0]) == ["10,80 EUR"])
        fixture.set("JPY") { $0.currencyTarget }
        await submit(translator, "12 USD")
        #expect(lines(fixture.state.conversions[0]) == ["1.800 JPY"])
    }

    @Test func fetchesOncePerDay() async throws {
        let translator = try await startedTranslator()
        enableCurrency()
        for text in ["$12", "€5", "£3", "100.000đ"] {
            await submit(translator, text)
        }
        #expect(fixture.ratesClient.requests.count == 1)
        fixture.clock.advance(24 * 3600 + 1)
        await submit(translator, "$12")
        #expect(fixture.ratesClient.requests.count == 2)
    }

    @Test func saysSoWhenThereAreNoRates() async throws {
        let translator = try await startedTranslator()
        fixture.set(true) { $0.convertCurrency }
        await submit(translator, "$12")
        #expect(fixture.state.conversions[0].outcome == .failed("Chưa lấy được tỷ giá"))
        #expect(fixture.state.conversions[0].note == nil)
        #expect(fixture.state.showsConversionsOnly)
    }

    @Test func saysSoWhenTheSourceLacksTheCurrency() async throws {
        let translator = try await startedTranslator()
        enableCurrency(rates: ["USD": 1, "VND": 25_000])
        await submit(translator, "€5")
        #expect(fixture.state.conversions[0].outcome == .failed("Chưa có tỷ giá EUR"))
        fixture.set("EUR") { $0.currencyTarget }
        await submit(translator, "12 USD")
        #expect(fixture.state.conversions[0].outcome == .failed("Chưa có tỷ giá EUR"))
    }

    @Test func oldRatesAreShownWithTheirDateAndAWarning() async throws {
        let translator = try await startedTranslator()
        enableCurrency()
        await submit(translator, "$12")
        fixture.clock.advance(30 * 3600)
        fixture.ratesClient.handler = { _ in throw URLError(.notConnectedToInternet) }
        await submit(translator, "$12")
        let conversion = fixture.state.conversions[0]
        #expect(lines(conversion) == ["300.000 ₫"])
        #expect(conversion.note == "Tỷ giá ngày 15/01/2026, chưa lấy được tỷ giá mới")
    }

    @Test func ratesFromAClockSetBackAreFlaggedAsOldWhenTheRefetchFails() async throws {
        let translator = try await startedTranslator()
        enableCurrency()
        await submit(translator, "$12")
        // Their fetch time is now in the future, so they are not fresh, and a failing refetch must not pass them off as live.
        fixture.clock.advance(-3600)
        fixture.ratesClient.handler = { _ in throw URLError(.notConnectedToInternet) }
        await submit(translator, "$12")
        #expect(lines(fixture.state.conversions[0]) == ["300.000 ₫"])
        #expect(fixture.state.conversions[0].note == "Tỷ giá ngày 15/01/2026, chưa lấy được tỷ giá mới")
    }

    @Test func anAmountInASentenceIsConvertedAboveTheTranslation() async throws {
        let translator = try await startedTranslator()
        enableCurrency()
        translator.submit("The ticket costs 12 USD for adults")
        await fixture.translated()
        await translator.conversion?.value
        #expect(!fixture.state.showsConversionsOnly)
        #expect(fixture.state.output == "The ticket costs 12 USD for adults [en→vi]")
        #expect(fixture.state.conversions.map(\.source) == ["12 USD"])
        #expect(lines(fixture.state.conversions[0]) == ["300.000 ₫"])
    }

    @Test func aSentenceKeepsItsTranslationWhenTheRatesFail() async throws {
        let translator = try await startedTranslator()
        fixture.set(true) { $0.convertCurrency }
        translator.submit("The ticket costs 12 USD for adults")
        await fixture.translated()
        await translator.conversion?.value
        #expect(fixture.state.output == "The ticket costs 12 USD for adults [en→vi]")
        #expect(fixture.state.conversions[0].outcome == .failed("Chưa lấy được tỷ giá"))
    }

    @Test func ratesThatArriveForOldTextAreDropped() async throws {
        let translator = try await startedTranslator()
        fixture.set(true) { $0.convertCurrency }
        let gate = Gate()
        fixture.ratesClient.handler = { _ in
            await gate.wait()
            return RatesReplies.success(["USD": 1, "VND": 25_000], updated: updated)
        }
        translator.submit("$12")
        await fixture.translated()
        await eventuallyOnAnotherThread { gate.isWaiting }
        translator.submit("72 °F")
        await fixture.translated()
        gate.open()
        await settle()
        #expect(fixture.state.conversions.map(\.source) == ["72 °F"])
        #expect(lines(fixture.state.conversions[0]) == ["22,2 °C"])
    }

    @Test func switchingTheSettingOffStopsConvertingAtOnce() async throws {
        let translator = try await startedTranslator()
        enableCurrency()
        await submit(translator, "$12")
        fixture.set(false) { $0.convertCurrency }
        translator.submit("$12")
        await fixture.translated()
        #expect(fixture.state.conversions.isEmpty)
        #expect(fixture.engine.requests.map(\.text) == ["$12"])
        #expect(fixture.ratesClient.requests.count == 1)
    }

    @Test func theRatesAreKeptInTheModulesCachesFolder() async throws {
        let translator = try await startedTranslator()
        enableCurrency()
        await submit(translator, "$12")
        let caches = fixture.harness.storageRoot.storage(for: "translation").cachesDirectory
        #expect(FileManager.default.fileExists(atPath: caches.appending(path: "exchange-rates.json").path))
    }
}
