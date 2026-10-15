import Foundation
import Testing
@testable import TranslationModule

/// An error whose description quotes a key, as a careless library might; nothing of it may reach a message or the log.
struct LeakyError: Error, LocalizedError {
    let key: String
    var errorDescription: String? { "request failed for key \(key)" }
}

@Suite struct RemoteTranslationEngineTests {
    let transport = FakeTransport()
    let log = FakeTranslationLog()
    let key = "SECRET-KEY-0123456789"

    func engine(
        name: String = "Google Cloud Translation", provider: (any RemoteProvider)? = nil
    ) -> RemoteTranslationEngine {
        let provider = provider ?? GoogleProvider(key: key)
        return RemoteTranslationEngine(name: name, provider: { provider }, transport: transport, log: log)
    }

    func translate(_ engine: RemoteTranslationEngine, _ text: String = "Hello, how are you?") async -> Result<String, TranslationFailure> {
        do throws(TranslationFailure) {
            return .success(try await engine.translate(text, from: .en, to: .vi))
        } catch {
            return .failure(error)
        }
    }

    @Test func sendsOneRequestAndReturnsTheTranslation() async {
        transport.reply(Canned.google("Xin chào, bạn khỏe không?"))
        let result = await translate(engine())
        #expect(result == .success("Xin chào, bạn khỏe không?"))
        #expect(transport.requests.count == 1)
        #expect(transport.requests.first?.url?.host == "translation.googleapis.com")
    }

    @Test func blankTextIsNotSentAnywhere() async {
        transport.reply(Canned.google("x"))
        #expect(await translate(engine(), "  \n ") == .success(""))
        #expect(transport.requests.isEmpty)
    }

    @Test func aRedirectIsToldAndNothingIsFollowed() async {
        transport.reply(Canned.text(307, "moved"))
        #expect(await translate(engine()) == .failure(.failed("Máy chủ của Google Cloud Translation chuyển hướng — đã chặn để bảo vệ khoá.")))
        #expect(log.lines == ["Google Cloud Translation failed: redirect refused (HTTP 307)"])
    }

    @Test func aTextOfTheLimitIsSent() async {
        transport.reply(Canned.google("ok"))
        let text = String(repeating: "a", count: RemoteTranslationEngine.maxCharacters)
        #expect(await translate(engine(), text) == .success("ok"))
        #expect(transport.requests.count == 1)
    }

    /// A paid service, and a request size it limits: a longer text is not sent at all.
    @Test func aLongerTextIsNotSentAndSaysWhy() async {
        transport.reply(Canned.google("ok"))
        let text = String(repeating: "a", count: RemoteTranslationEngine.maxCharacters + 1)
        #expect(await translate(engine(), text) == .failure(.failed("Đoạn chữ dài hơn 5.000 ký tự nên chưa gửi tới Google Cloud Translation. Chọn đoạn ngắn hơn, hoặc dịch bằng Apple.")))
        #expect(transport.requests.isEmpty)
        #expect(log.lines == ["Google Cloud Translation failed: text too long"])
    }

    @Test func theLimitCountsCharactersNotBytes() async {
        transport.reply(Canned.google("ok"))
        let text = String(repeating: "ế", count: RemoteTranslationEngine.maxCharacters)
        #expect(await translate(engine(), text) == .success("ok"))
    }

    @Test func thereIsNoLanguagePackToInstall() async {
        #expect(await engine().status(from: .en, to: .vi) == .installed)
    }

    @Test func aServiceThatRefusesIsToldInVietnamese() async {
        transport.reply(Canned.error(403, "Billing disabled"))
        #expect(await translate(engine()) == .failure(.failed("Google Cloud Translation từ chối yêu cầu (HTTP 403): Billing disabled. Kiểm tra lại key.")))
    }

    @Test func noConnectionIsToldAsSuch() async {
        transport.handler = { _ in throw URLError(.notConnectedToInternet) }
        #expect(await translate(engine()) == .failure(.failed("Không có kết nối mạng.")))
        transport.handler = { _ in throw URLError(.timedOut) }
        #expect(await translate(engine()) == .failure(.failed("Google Cloud Translation trả lời quá lâu.")))
    }

    @Test func aMissingKeyFailsBeforeAnythingIsSent() async {
        let missing = RemoteTranslationEngine(name: "Google Cloud Translation", provider: { throw RemoteFailure.notConfigured("key") }, transport: transport, log: log)
        #expect(await translate(missing) == .failure(.failed("Chưa nhập key cho Google Cloud Translation. Mở Cài đặt → Dịch để thêm.")))
        #expect(transport.requests.isEmpty)
    }

    @Test func cancellingIsNotAFailure() async {
        transport.handler = { _ in throw CancellationError() }
        #expect(await translate(engine()) == .failure(.cancelled))
        transport.handler = { _ in throw URLError(.cancelled) }
        #expect(await translate(engine()) == .failure(.cancelled))
        #expect(log.lines.isEmpty)
    }

    @Test func aCancelledTaskNeverShowsItsReply() async {
        transport.holds = true
        transport.reply(Canned.google("Xin chào"))
        let engine = engine()
        let task = Task { await translate(engine) }
        await eventuallyAfterWaiting { transport.waiting }
        task.cancel()
        transport.release()
        #expect(await task.value == .failure(.cancelled))
    }

    @Test func anOddErrorIsNeverQuoted() async {
        transport.handler = { [key] _ in throw LeakyError(key: key) }
        let result = await translate(engine())
        #expect(result == .failure(.failed("Không kết nối được tới Google Cloud Translation.")))
        #expect(!log.lines.joined().contains(key))
    }

    @Test func aFailureIsLoggedByEngineAndStatusOnly() async {
        transport.reply(Canned.error(403, "Detail words that must not be logged"))
        _ = await translate(engine(), "A text the user selected")
        #expect(log.lines == ["Google Cloud Translation failed: rejected (HTTP 403)"])
        #expect(log.levels == [.error])
    }

    @Test func neitherAKeyNorTheTextIsEverLogged() async {
        let secretText = "My private diary entry"
        let scenarios: [(any RemoteProvider, HTTPReply?, (any Error)?)] = [
            (GoogleProvider(key: key), Canned.error(400, "key \(key) is bad"), nil),
            (GoogleProvider(key: key), Canned.text(500, "oops \(secretText)"), nil),
            (MicrosoftProvider(key: key, region: "westeurope"), Canned.error(401, "bad \(key)"), nil),
            (OpenAIProvider(key: key, baseURL: "https://api.openai.com/v1", model: "m"), Canned.error(429, "slow down \(key)"), nil),
            (OpenAIProvider(key: key, baseURL: "https://api.openai.com/v1", model: "m"), nil, LeakyError(key: key)),
            (GoogleProvider(key: key), Canned.google("Nhật ký riêng của tôi"), nil),
        ]
        for (provider, reply, error) in scenarios {
            transport.handler = { _ in
                if let error { throw error }
                return reply ?? Canned.text(200, "")
            }
            let result = await translate(engine(provider: provider), secretText)
            if case .failure(.failed(let message)) = result { #expect(!message.contains(key)) }
        }
        let logged = log.lines.joined(separator: "\n")
        #expect(!logged.isEmpty)
        for secret in [key, secretText, "Nhật ký", "Bearer", "Ocp-Apim"] { #expect(!logged.contains(secret), "\(secret)") }
        #expect(logged.contains("Google Cloud Translation failed: rejected (HTTP 400)"))
    }

    @Test func aMissingKeyIsLoggedWithoutAny() async {
        let missing = RemoteTranslationEngine(name: "Microsoft Translator", provider: { throw RemoteFailure.notConfigured("key") }, transport: transport, log: log)
        _ = await translate(missing)
        #expect(log.lines == ["Microsoft Translator failed: not configured"])
    }
}

@Suite struct RemoteEnginesTests {
    let transport = FakeTransport()
    let log = FakeTranslationLog()
    let keys = FakeKeyStore()
    let key = "SECRET-KEY-0123456789"

    func engines(_ config: EngineConfig = EngineConfig()) -> RemoteEngines {
        RemoteEngines(keys: keys, transport: transport, log: log, config: { config })
    }

    func translate(_ choice: EngineChoice, config: EngineConfig = EngineConfig()) async throws -> Result<String, TranslationFailure> {
        let engine = try #require(engines(config).engine(for: choice))
        do throws(TranslationFailure) {
            return .success(try await engine.translate("Hello", from: .en, to: .vi))
        } catch {
            return .failure(error)
        }
    }

    @Test func appleIsNotARemoteEngine() {
        #expect(engines().engine(for: .apple) == nil)
        for choice in [EngineChoice.google, .microsoft, .openAI] { #expect(engines().engine(for: choice) != nil) }
    }

    @Test func googleUsesTheSavedKey() async throws {
        _ = keys.save(key, for: .googleKey)
        transport.reply(Canned.google("Xin chào"))
        #expect(try await translate(.google) == .success("Xin chào"))
        let request = try #require(transport.requests.first)
        #expect(request.url?.host == "translation.googleapis.com")
        #expect(request.value(forHTTPHeaderField: "X-goog-api-key") == key)
    }

    @Test func withoutAKeyNothingIsSent() async throws {
        for choice in [EngineChoice.google, .microsoft, .openAI] {
            let result = try await translate(choice, config: EngineConfig(openAIBaseURL: "https://api.openai.com/v1", openAIModel: "m"))
            guard case .failure(.failed(let message)) = result else { Issue.record("\(choice): \(result)"); continue }
            #expect(message.hasPrefix("Chưa nhập key cho "), "\(choice)")
        }
        #expect(transport.requests.isEmpty)
    }

    @Test func aKeyOfOnlySpacesIsNoKey() async throws {
        _ = keys.save("  \n ", for: .googleKey)
        _ = try await translate(.google)
        #expect(transport.requests.isEmpty)
    }

    @Test func aKeySavedWithSpacesAroundItIsTrimmed() async throws {
        _ = keys.save("  \(key)\n", for: .googleKey)
        transport.reply(Canned.google("Xin chào"))
        _ = try await translate(.google)
        #expect(transport.requests.first?.value(forHTTPHeaderField: "X-goog-api-key") == key)
    }

    @Test func microsoftSendsTheRegionOfTheSettings() async throws {
        _ = keys.save(key, for: .microsoftKey)
        transport.reply(Canned.microsoft("Xin chào"))
        #expect(try await translate(.microsoft, config: EngineConfig(microsoftRegion: "southeastasia")) == .success("Xin chào"))
        let request = try #require(transport.requests.first)
        #expect(request.url?.host == "api.cognitive.microsofttranslator.com")
        #expect(request.value(forHTTPHeaderField: "Ocp-Apim-Subscription-Key") == key)
        #expect(request.value(forHTTPHeaderField: "Ocp-Apim-Subscription-Region") == "southeastasia")
    }

    @Test func theLanguageModelUsesTheSettingsAddressAndModel() async throws {
        _ = keys.save(key, for: .openAIKey)
        transport.reply(Canned.openAI("Xin chào"))
        let config = EngineConfig(openAIBaseURL: "http://localhost:11434/v1", openAIModel: "qwen2.5")
        #expect(try await translate(.openAI, config: config) == .success("Xin chào"))
        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "http://localhost:11434/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(key)")
        let body = try #require(transport.lastBody() as? [String: Any])
        #expect(body["model"] as? String == "qwen2.5")
    }

    @Test func aLanguageModelWithoutAModelOrAnAddressSendsNothing() async throws {
        _ = keys.save(key, for: .openAIKey)
        let noModel = try await translate(.openAI, config: EngineConfig(openAIBaseURL: "https://api.openai.com/v1", openAIModel: ""))
        #expect(noModel == .failure(.failed("Chưa nhập model cho LLM tương thích OpenAI. Mở Cài đặt → Dịch để thêm.")))
        let noAddress = try await translate(.openAI, config: EngineConfig(openAIBaseURL: "", openAIModel: "m"))
        #expect(noAddress == .failure(.failed("Chưa nhập địa chỉ cho LLM tương thích OpenAI. Mở Cài đặt → Dịch để thêm.")))
        #expect(transport.requests.isEmpty)
    }

    @Test func aLanguageModelAtAPlainHttpAddressSendsNothing() async throws {
        _ = keys.save(key, for: .openAIKey)
        let result = try await translate(.openAI, config: EngineConfig(openAIBaseURL: "http://example.com/v1", openAIModel: "m"))
        #expect(result == .failure(.failed("Địa chỉ của LLM tương thích OpenAI chưa đúng: cần https:// (http:// chỉ dùng cho localhost).")))
        #expect(transport.requests.isEmpty)
    }

    @Test func theKeyIsReadWhenAnEngineIsUsedNotBefore() async throws {
        let engine = try #require(engines().engine(for: .google))
        _ = keys.save(key, for: .googleKey)   // typed after the engine was built, before it translated
        transport.reply(Canned.google("Xin chào"))
        #expect(try await engine.translate("Hello", from: .en, to: .vi) == "Xin chào")
    }
}
