import Foundation
import MyNotchCore

/// The Translation module's "LLM tương thích OpenAI" (its address, model and key), lent to other modules for short questions whatever
/// engine translates: Media asks it which film a page plays. Set up only while the module runs, which is when its settings are there.
public final class TranslationLanguageModel: LanguageModel {
    /// A question is a line or two: an answer that slow is not coming.
    static let timeout: TimeInterval = 30

    private let keys: any KeyStore
    private let transport: any HTTPTransport
    /// The module's settings while it runs.
    var settings: ModuleSettings?

    init(keys: any KeyStore, transport: any HTTPTransport) {
        self.keys = keys
        self.transport = transport
    }

    public func complete(instruction: String, input: String) async throws -> String {
        guard let settings else { throw RemoteFailure.notConfigured("module Dịch") }
        let config = TranslationKeys(settings)
        guard let key = await keys.savedKey(.openAIKey) else { throw RemoteFailure.notConfigured("khoá") }
        let provider = OpenAIProvider(key: key, baseURL: settings.value(config.openAIBaseURL), model: settings.value(config.openAIModel))
        let request = try provider.request(instruction: instruction, input: input, timeout: Self.timeout)
        let reply: HTTPReply
        do {
            reply = try await transport.send(request)
        } catch let error as URLError {
            throw RemoteFailure(error)
        }
        return try provider.translation(from: reply)
    }
}
