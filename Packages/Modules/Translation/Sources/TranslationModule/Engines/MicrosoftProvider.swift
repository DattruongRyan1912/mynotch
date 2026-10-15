import Foundation

/// Translator v3 REST. A resource that is not "global" needs its region in a header next to the key.
nonisolated struct MicrosoftProvider: RemoteProvider {
    static let endpoint = URL(string: "https://api.cognitive.microsofttranslator.com/translate")!

    let key: String
    let region: String

    private struct Item: Encodable {
        var text: String

        enum CodingKeys: String, CodingKey { case text = "Text" }
    }

    private struct Reply: Decodable {
        struct Translation: Decodable {
            var text: String
        }

        var translations: [Translation]
    }

    func request(for text: String, from source: Locale.Language, to target: Locale.Language) throws(RemoteFailure) -> URLRequest {
        var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "api-version", value: "3.0"),
            URLQueryItem(name: "from", value: LanguageCodes.microsoft(source)),
            URLQueryItem(name: "to", value: LanguageCodes.microsoft(target)),
            URLQueryItem(name: "textType", value: "plain"),
        ]
        var headers = ["Ocp-Apim-Subscription-Key": key, "Content-Type": "application/json; charset=UTF-8"]
        let region = region.trimmingCharacters(in: .whitespacesAndNewlines)
        if !region.isEmpty { headers["Ocp-Apim-Subscription-Region"] = region }
        return RemoteRequest.post(components?.url ?? Self.endpoint, headers: headers, body: [Item(text: text)], timeout: 20)
    }

    func translation(from reply: HTTPReply) throws(RemoteFailure) -> String {
        guard RemoteRequest.succeeded(reply) else { throw RemoteFailure.of(reply, key: key) }
        guard let text = (try? JSONDecoder().decode([Reply].self, from: reply.body))?.first?.translations.first?.text,
              !text.isEmpty else { throw RemoteFailure.unreadable }
        return text
    }
}
