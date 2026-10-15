import Foundation
import Testing
@testable import TranslationModule

/// Which engine translates, what happens when a chosen one fails, and that nothing is sent anywhere unless it is chosen.
@Suite struct EngineChoiceTests {
    let fixture = ModuleFixture()
    let secret = "SECRET-KEY-0123456789"
    let text = "Hello, how are you today?"

    func startedTranslator(engine: EngineChoice? = nil) async throws -> Translator {
        if let engine { fixture.set(engine.rawValue, for: \.engine) }
        await fixture.start()
        return try #require(fixture.module.translator)
    }

    func translate(_ translator: Translator, _ input: String? = nil) async {
        translator.submit(input ?? text)
        await fixture.translated()
    }

    @Test func theMenuNamesTheEnginesAsTheBriefDoes() {
        #expect(EngineChoice.allCases == [.apple, .google, .microsoft, .openAI])
        #expect(EngineChoice.apple.title == "Apple (mặc định, trên máy)")
        #expect(EngineChoice.google.title == "Google Cloud Translation")
        #expect(EngineChoice.microsoft.title == "Microsoft Translator")
        #expect(EngineChoice.openAI.title == "LLM tương thích OpenAI")
        #expect(EngineChoice.openAI.name == "LLM tương thích OpenAI")
        #expect(EngineChoice.apple.secret == nil)
        #expect(EngineChoice.google.secret == .googleKey)
        #expect(EngineChoice.microsoft.secret == .microsoftKey)
        #expect(EngineChoice.openAI.secret == .openAIKey)
    }

    @Test func thePrivacyNoteSaysWhatIsSentAndWhen() {
        #expect(EngineChoice.privacyNote == "Chỉ đoạn chữ cần dịch được gửi đi, và chỉ khi bạn chọn bộ máy đó; Apple không gửi gì.")
    }

    @Test func settingsStartOnAppleWithOpenAIsUsualAddress() {
        #expect(fixture.keys.engine.defaultValue == "apple")
        #expect(fixture.keys.engine.name == "module.translation.engine")
        #expect(fixture.keys.microsoftRegion.defaultValue == "")
        #expect(fixture.keys.openAIBaseURL.defaultValue == "https://api.openai.com/v1")
        #expect(fixture.keys.openAIModel.defaultValue == "gpt-4o-mini")
    }

    @Test func appleTranslatesByDefaultAndNothingIsEverSent() async throws {
        for secret in TranslationSecret.allCases { _ = fixture.keyStore.save(secret.rawValue, for: secret) }
        let translator = try await startedTranslator()
        await translate(translator)
        #expect(fixture.state.output == "\(text) [en→vi]")
        #expect(fixture.engine.requests.count == 1)
        #expect(fixture.transport.requests.isEmpty)
        #expect(!fixture.state.offersAppleFallback)
    }

    @Test func aStoredKeyAloneSendsNothing() async throws {
        _ = fixture.keyStore.save(secret, for: .googleKey)
        let translator = try await startedTranslator()
        await translate(translator)
        #expect(fixture.transport.requests.isEmpty)
    }

    @Test func aChosenEngineTranslatesInsteadOfApple() async throws {
        _ = fixture.keyStore.save(secret, for: .googleKey)
        fixture.transport.reply(Canned.google("Xin chào, hôm nay bạn thế nào?"))
        let translator = try await startedTranslator(engine: .google)
        await translate(translator)
        #expect(fixture.state.output == "Xin chào, hôm nay bạn thế nào?")
        #expect(fixture.state.error == nil)
        #expect(fixture.state.pairStatus == .installed)
        #expect(fixture.state.banner == nil)
        #expect(fixture.transport.requests.count == 1)
        #expect(fixture.engine.requests.isEmpty)
        let sent = try #require(fixture.transport.lastBody() as? [String: String])
        #expect(sent["q"] == text)
        #expect(sent["source"] == "en")
        #expect(sent["target"] == "vi")
    }

    @Test func eachOptionalEngineIsReachable() async throws {
        _ = fixture.keyStore.save(secret, for: .microsoftKey)
        _ = fixture.keyStore.save(secret, for: .openAIKey)
        fixture.set("southeastasia", for: \.microsoftRegion)
        fixture.set("mistral", for: \.openAIModel)
        fixture.transport.handler = { request in
            request.url?.host == "api.cognitive.microsofttranslator.com" ? Canned.microsoft("từ Microsoft") : Canned.openAI("từ mô hình")
        }
        let translator = try await startedTranslator(engine: .microsoft)
        await translate(translator)
        #expect(fixture.state.output == "từ Microsoft")
        fixture.set("openai", for: \.engine)
        await translate(translator)
        #expect(fixture.state.output == "từ mô hình")
        #expect(fixture.transport.requests.map(\.url?.host) == ["api.cognitive.microsofttranslator.com", "api.openai.com"])
        #expect(fixture.engine.requests.isEmpty)
    }

    @Test func theChoiceAppliesToTheNextTranslationWithoutARestart() async throws {
        _ = fixture.keyStore.save(secret, for: .googleKey)
        fixture.transport.reply(Canned.google("Xin chào"))
        let translator = try await startedTranslator()
        await translate(translator)
        #expect(fixture.engine.requests.count == 1)
        #expect(fixture.transport.requests.isEmpty)
        fixture.set("google", for: \.engine)
        await translate(translator, "Good morning, my friend")
        #expect(fixture.engine.requests.count == 1)
        #expect(fixture.transport.requests.count == 1)
        fixture.set("apple", for: \.engine)
        await translate(translator, "Good evening, my friend")
        #expect(fixture.engine.requests.count == 2)
        #expect(fixture.transport.requests.count == 1)
    }

    @Test func anUnknownChoiceFallsBackToApple() async throws {
        fixture.set("something-else", for: \.engine)
        let translator = try await startedTranslator()
        await translate(translator)
        #expect(fixture.engine.requests.count == 1)
        #expect(fixture.transport.requests.isEmpty)
    }

    @Test func aFailingEngineShowsItsErrorAndOffersAppleWithoutSwitching() async throws {
        _ = fixture.keyStore.save(secret, for: .googleKey)
        fixture.transport.reply(Canned.error(500, "Backend Error"))
        let translator = try await startedTranslator(engine: .google)
        await translate(translator)
        #expect(fixture.state.error == "Google Cloud Translation đang lỗi (HTTP 500): Backend Error.")
        #expect(fixture.state.output.isEmpty)
        #expect(fixture.state.offersAppleFallback)
        #expect(fixture.state.hasTranslationContent)
        // Never silently switched: Apple was not asked.
        await settle()
        #expect(fixture.engine.requests.isEmpty)
        #expect(fixture.transport.requests.count == 1)
    }

    @Test func noConnectionOffersAppleToo() async throws {
        _ = fixture.keyStore.save(secret, for: .googleKey)
        let translator = try await startedTranslator(engine: .google)
        await translate(translator)
        #expect(fixture.state.error == "Không có kết nối mạng.")
        #expect(fixture.state.offersAppleFallback)
    }

    @Test func aMissingKeyShowsAnErrorOffersAppleAndSendsNothing() async throws {
        let translator = try await startedTranslator(engine: .google)
        await translate(translator)
        #expect(fixture.state.error == "Chưa nhập key cho Google Cloud Translation. Mở Cài đặt → Dịch để thêm.")
        #expect(fixture.state.offersAppleFallback)
        #expect(fixture.transport.requests.isEmpty)
        #expect(fixture.engine.requests.isEmpty)
    }

    @Test func theButtonTranslatesOnceWithAppleAndKeepsTheChoice() async throws {
        _ = fixture.keyStore.save(secret, for: .googleKey)
        let translator = try await startedTranslator(engine: .google)
        await translate(translator)
        #expect(fixture.state.offersAppleFallback)

        translator.translateWithApple()
        await fixture.translated()
        #expect(fixture.state.output == "\(text) [en→vi]")
        #expect(fixture.state.error == nil)
        #expect(!fixture.state.offersAppleFallback)
        #expect(fixture.engine.requests.map(\.text) == [text])
        #expect(fixture.transport.requests.count == 1)
        let settings = try #require(fixture.harness.settingsEnvironment(for: "translation")).settings
        #expect(settings.value(fixture.keys.engine) == "google")

        // The next translation goes to the chosen engine again, and fails and offers again.
        await translate(translator, "Good morning, my friend")
        #expect(fixture.transport.requests.count == 2)
        #expect(fixture.state.offersAppleFallback)
        #expect(fixture.engine.requests.count == 1)
    }

    @Test func theButtonDoesNothingWithoutText() async throws {
        let translator = try await startedTranslator(engine: .google)
        translator.translateWithApple()
        await settle()
        #expect(fixture.engine.requests.isEmpty)
        #expect(fixture.transport.requests.isEmpty)
    }

    @Test func aSuccessClearsTheOfferAndTheError() async throws {
        _ = fixture.keyStore.save(secret, for: .googleKey)
        let translator = try await startedTranslator(engine: .google)
        await translate(translator)
        #expect(fixture.state.offersAppleFallback)
        fixture.transport.reply(Canned.google("Xin chào"))
        await translate(translator, "Good morning, my friend")
        #expect(fixture.state.output == "Xin chào")
        #expect(fixture.state.error == nil)
        #expect(!fixture.state.offersAppleFallback)
    }

    @Test func aNewTextDoesNotKeepTheOfferOfAnOldFailure() async throws {
        let translator = try await startedTranslator(engine: .google)
        await translate(translator)
        #expect(fixture.state.offersAppleFallback)
        translator.edit("")
        #expect(!fixture.state.offersAppleFallback)
        #expect(fixture.state.error == nil)
    }

    @Test func appleOwnFailuresDoNotOfferApple() async throws {
        fixture.engine.failure = .failed("Hỏng rồi")
        let translator = try await startedTranslator()
        await translate(translator)
        #expect(fixture.state.error == "Hỏng rồi")
        #expect(!fixture.state.offersAppleFallback)
    }

    @Test func aChosenEngineIsNotBlamedForALanguagePackAndHasNone() async throws {
        _ = fixture.keyStore.save(secret, for: .googleKey)
        fixture.transport.reply(Canned.google("Xin chào"))
        fixture.engine.failure = .notInstalled
        let translator = try await startedTranslator(engine: .google)
        await translate(translator)
        #expect(fixture.state.banner == nil)
        #expect(fixture.state.output == "Xin chào")
    }

    @Test func aSupersededRemoteTranslationShowsNothing() async throws {
        _ = fixture.keyStore.save(secret, for: .googleKey)
        fixture.transport.holds = true
        fixture.transport.reply(Canned.google("Xin chào"))
        let translator = try await startedTranslator(engine: .google)
        translator.submit(text)
        await eventuallyAfterWaiting { fixture.transport.waiting }
        let first = translator.translation
        fixture.transport.holds = false
        fixture.transport.handler = { _ in Canned.google("Chào buổi sáng") }
        translator.submit("Good morning, my friend")
        fixture.transport.release()
        await first?.value
        await fixture.translated()
        #expect(fixture.state.output == "Chào buổi sáng")
        #expect(fixture.state.error == nil)
        #expect(!fixture.state.offersAppleFallback)
    }

    @Test func aQuantityIsNeverSent() async throws {
        _ = fixture.keyStore.save(secret, for: .googleKey)
        let translator = try await startedTranslator(engine: .google)
        await translate(translator, "72 °F")
        #expect(fixture.state.showsConversionsOnly)
        #expect(fixture.transport.requests.isEmpty)
    }

    @Test func nothingIsSentWhileTheTextIsNotTranslated() async {
        _ = fixture.keyStore.save(secret, for: .googleKey)
        fixture.set("google", for: \.engine)
        fixture.set(false, for: \.autoTranslateOnOpen)
        await fixture.start()
        #expect(fixture.harness.services.handle(name: "translate", text: text))
        await settle()
        #expect(fixture.transport.requests.isEmpty)
    }

    @Test func theKeyIsNeverInAMessageOrTheLog() async throws {
        _ = fixture.keyStore.save(secret, for: .googleKey)
        fixture.transport.reply(Canned.error(403, "Requests with \(secret) are blocked"))
        let translator = try await startedTranslator(engine: .google)
        await translate(translator)
        #expect(fixture.state.error?.contains(secret) == false)
        #expect(fixture.state.error?.contains("***") == true)
        #expect(!fixture.engineLog.lines.isEmpty)
        #expect(!fixture.engineLog.lines.joined().contains(secret))
        #expect(!fixture.engineLog.lines.joined().contains(text))
    }

    @Test func stoppingDropsTheOffer() async throws {
        let translator = try await startedTranslator(engine: .google)
        await translate(translator)
        #expect(fixture.state.offersAppleFallback)
        await fixture.harness.registry.setEnabled(false, for: "translation")
        #expect(!fixture.state.offersAppleFallback)
    }
}
