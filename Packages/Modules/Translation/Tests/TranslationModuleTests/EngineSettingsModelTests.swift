import Foundation
import Testing
@testable import TranslationModule

/// What the Settings rows do with keys and the "Kiểm tra" button, without the rows.
@Suite struct EngineSettingsModelTests {
    let keys = FakeKeyStore()
    let transport = FakeTransport()
    let log = FakeTranslationLog()
    let secret = "SECRET-KEY-0123456789"

    func model(_ config: EngineConfig = EngineConfig(microsoftRegion: "westeurope", openAIBaseURL: "https://api.openai.com/v1", openAIModel: "gpt-4o-mini")) -> EngineSettingsModel {
        EngineSettingsModel(keys: keys, engines: RemoteEngines(keys: keys, transport: transport, log: log, config: { config }), log: log)
    }

    @Test func knowsWhichKeysAreSavedWithoutReadingThemOut() async {
        _ = keys.save(secret, for: .googleKey)
        let model = model()
        #expect(model.savedKeys.isEmpty)
        await model.refresh()
        #expect(model.savedKeys == [.google])
        #expect(!model.hasKey(.microsoft))
        #expect(model.hasKey(.google))
    }

    @Test func appleNeedsNoKey() async {
        let model = model()
        await model.refresh()
        #expect(model.hasKey(.apple))
    }

    @Test func savesATrimmedKeyInTheKeychainStore() async {
        let model = model()
        #expect(await model.save("  \(secret)\n", for: .google))
        #expect(keys.values == [.googleKey: secret])
        #expect(model.hasKey(.google))
        #expect(model.keyError == nil)
    }

    @Test func eachEngineKeepsItsOwnKey() async {
        let model = model()
        _ = await model.save("a", for: .google)
        _ = await model.save("b", for: .microsoft)
        _ = await model.save("c", for: .openAI)
        #expect(keys.values == [.googleKey: "a", .microsoftKey: "b", .openAIKey: "c"])
    }

    @Test func aBlankKeyIsNotSaved() async {
        let model = model()
        #expect(!(await model.save("   ", for: .google)))
        #expect(keys.saveCount == 0)
    }

    @Test func appleHasNoKeyToSave() async {
        let model = model()
        #expect(!(await model.save(secret, for: .apple)))
        #expect(keys.values.isEmpty)
    }

    @Test func aKeychainThatRefusesIsReportedWithoutTheKey() async {
        keys.failsToSave = true
        let model = model()
        #expect(!(await model.save(secret, for: .google)))
        #expect(!model.hasKey(.google))
        #expect(model.keyError == "Không lưu được key vào Keychain")
        #expect(!log.lines.isEmpty)
        #expect(!log.lines.joined().contains(secret))
    }

    @Test func aLaterSaveClearsTheOldError() async {
        keys.failsToSave = true
        let model = model()
        _ = await model.save(secret, for: .google)
        keys.failsToSave = false
        #expect(await model.save(secret, for: .google))
        #expect(model.keyError == nil)
    }

    @Test func removingAKeyForgetsItAndItsCheck() async {
        _ = keys.save(secret, for: .googleKey)
        transport.reply(Canned.google("Xin chào"))
        let model = model()
        await model.refresh()
        await model.test(.google)
        #expect(model.checks[.google] == .ok)
        #expect(await model.remove(.google))
        #expect(keys.values.isEmpty)
        #expect(!model.hasKey(.google))
        #expect(model.checks[.google] == nil)
        #expect(model.keyError == nil)
    }

    /// The one promise a user cannot check by eye: a key that could not be deleted is still there, and the row says so.
    @Test func aKeyThatCannotBeRemovedStaysSavedAndSaysSo() async {
        _ = keys.save(secret, for: .googleKey)
        transport.reply(Canned.google("Xin chào"))
        let model = model()
        await model.refresh()
        await model.test(.google)
        keys.failsToRemove = true
        #expect(!(await model.remove(.google)))
        #expect(keys.values == [.googleKey: secret])
        #expect(model.hasKey(.google))
        #expect(model.checks[.google] == .ok)
        #expect(model.keyError == "Không xoá được key khỏi Keychain")
        #expect(log.lines == ["Could not remove the Google Cloud Translation key from the Keychain"])
        #expect(!log.lines.joined().contains(secret))
        // The next look at the Keychain agrees with the row.
        await model.refresh()
        #expect(model.hasKey(.google))
    }

    @Test func aLaterRemovalThatWorksClearsTheError() async {
        _ = keys.save(secret, for: .googleKey)
        let model = model()
        await model.refresh()
        keys.failsToRemove = true
        _ = await model.remove(.google)
        keys.failsToRemove = false
        #expect(await model.remove(.google))
        #expect(model.keyError == nil)
        #expect(!model.hasKey(.google))
    }

    @Test func removingAppleOrWhatIsNotSavedIsNotAnError() async {
        let model = model()
        #expect(!(await model.remove(.apple)))
        #expect(model.keyError == nil)
        #expect(await model.remove(.microsoft))
    }

    @Test func lookingForSavedKeysNeverReadsTheirValues() async {
        _ = keys.save(secret, for: .googleKey)
        _ = keys.save(secret, for: .openAIKey)
        let model = model()
        await model.refresh()
        #expect(model.savedKeys == [.google, .openAI])
        #expect(keys.loadCount == 0)
        #expect(keys.containsCount == 3)
    }

    @Test func checkSendsOneRequestWithAFixedTextAndSaysOK() async throws {
        _ = keys.save(secret, for: .googleKey)
        transport.reply(Canned.google("Xin chào"))
        let model = model()
        await model.test(.google)
        #expect(model.checks[.google] == .ok)
        #expect(transport.requests.count == 1)
        // Only a fixed word is sent: the check never uses what the user selected.
        let body = try #require(transport.lastBody() as? [String: String])
        #expect(body["q"] == "Hello")
    }

    @Test func checkShowsTheError() async {
        _ = keys.save(secret, for: .googleKey)
        transport.reply(Canned.error(403, "Billing disabled"))
        let model = model()
        await model.test(.google)
        #expect(model.checks[.google] == .failed("Google Cloud Translation từ chối yêu cầu (HTTP 403): Billing disabled. Kiểm tra lại key."))
        #expect(transport.requests.count == 1)
    }

    @Test func checkWithoutAKeySendsNothingAndSaysSo() async {
        let model = model()
        await model.test(.microsoft)
        #expect(model.checks[.microsoft] == .failed("Chưa nhập key cho Microsoft Translator. Mở Cài đặt → Dịch để thêm."))
        #expect(transport.requests.isEmpty)
    }

    @Test func checkSaysRunningWhileTheRequestIsOut() async {
        _ = keys.save(secret, for: .openAIKey)
        transport.holds = true
        transport.reply(Canned.openAI("Xin chào"))
        let model = model()
        let check = Task { await model.test(.openAI) }
        await eventuallyAfterWaiting { transport.waiting }
        #expect(model.checks[.openAI] == .running)
        transport.release()
        await check.value
        #expect(model.checks[.openAI] == .ok)
    }

    @Test func aSecondCheckWhileOneRunsSendsNothingMore() async {
        _ = keys.save(secret, for: .googleKey)
        transport.holds = true
        transport.reply(Canned.google("Xin chào"))
        let model = model()
        let first = Task { await model.test(.google) }
        await eventuallyAfterWaiting { transport.waiting }
        await model.test(.google)
        #expect(transport.requests.count == 1)
        transport.release()
        await first.value
    }

    @Test func aNewKeyDropsTheOldCheck() async {
        _ = keys.save(secret, for: .googleKey)
        transport.reply(Canned.google("Xin chào"))
        let model = model()
        await model.test(.google)
        #expect(model.checks[.google] == .ok)
        _ = await model.save("another-key", for: .google)
        #expect(model.checks[.google] == nil)
    }

    @Test func checkingAppleSendsNothing() async {
        let model = model()
        await model.test(.apple)
        #expect(model.checks[.apple] == nil)
        #expect(transport.requests.isEmpty)
    }
}
