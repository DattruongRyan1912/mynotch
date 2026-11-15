import Foundation
import MyNotchCore
import Testing
@testable import TranslationModule

/// The LLM lent to other modules: the module's address, model and key, whatever engine translates.
@MainActor @Suite struct TranslationLanguageModelTests {
    let fixture = ModuleFixture()
    var model: TranslationLanguageModel { fixture.module.languageModel }

    func reply(_ content: String) -> HTTPReply {
        HTTPReply(status: 200, body: Data(#"{"choices":[{"message":{"role":"assistant","content":\#(String(reflecting: content))}}]}"#.utf8))
    }

    @Test func whileTheModuleIsStoppedItIsNotSetUp() async {
        await #expect(throws: RemoteFailure.notConfigured("module Dịch")) {
            try await model.complete(instruction: "x", input: "y")
        }
    }

    @Test func itAsksTheUsersServerWithTheInstructionApartFromTheInput() async throws {
        await fixture.start()
        let settings = fixture.harness.settingsEnvironment(for: "translation")!.settings
        settings.set("https://api.deepseek.com/v1", for: fixture.keys.openAIBaseURL)
        settings.set("deepseek-chat", for: fixture.keys.openAIModel)
        _ = fixture.keyStore.save("sk-test", for: .openAIKey)
        fixture.transport.reply(reply("The Intern"))

        let answer = try await model.complete(instruction: "Name the film.", input: "Xem Bố Già Học Việc")
        #expect(answer == "The Intern")
        let request = try #require(fixture.transport.requests.last)
        #expect(request.url?.absoluteString == "https://api.deepseek.com/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        let body = try #require(try fixture.transport.lastBody() as? [String: Any])
        #expect(body["model"] as? String == "deepseek-chat")
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages == [["role": "system", "content": "Name the film."], ["role": "user", "content": "Xem Bố Già Học Việc"]])
    }

    @Test func withoutAKeyNothingIsSent() async {
        await fixture.start()
        await #expect(throws: RemoteFailure.notConfigured("khoá")) {
            try await model.complete(instruction: "x", input: "y")
        }
        #expect(fixture.transport.requests.isEmpty)
    }
}
