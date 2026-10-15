import Foundation

/// Cloud Translation, Basic (v2) REST. The key goes in the `X-goog-api-key` header rather than the URL's `key=`
/// parameter, since a URL ends up in error descriptions and logs.
nonisolated struct GoogleProvider: RemoteProvider {
    static let endpoint = URL(string: "https://translation.googleapis.com/language/translate/v2")!

    let key: String

    private struct Body: Encodable {
        var q: String
        var source: String
        var target: String
        /// "text" keeps the answer free of the HTML entities ("&#39;") that the default "html" format writes.
        var format = "text"
    }

    private struct Reply: Decodable {
        struct Payload: Decodable {
            struct Item: Decodable {
                var translatedText: String
            }

            var translations: [Item]
        }

        var data: Payload
    }

    func request(for text: String, from source: Locale.Language, to target: Locale.Language) throws(RemoteFailure) -> URLRequest {
        RemoteRequest.post(
            Self.endpoint,
            headers: ["X-goog-api-key": key, "Content-Type": "application/json; charset=utf-8"],
            body: Body(q: text, source: LanguageCodes.google(source), target: LanguageCodes.google(target)),
            timeout: 20
        )
    }

    func translation(from reply: HTTPReply) throws(RemoteFailure) -> String {
        guard RemoteRequest.succeeded(reply) else { throw RemoteFailure.of(reply, key: key) }
        guard let text = (try? JSONDecoder().decode(Reply.self, from: reply.body))?.data.translations.first?.translatedText,
              !text.isEmpty else { throw RemoteFailure.unreadable }
        return text
    }
}
