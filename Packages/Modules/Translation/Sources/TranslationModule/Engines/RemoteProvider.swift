import Foundation

/// How one service is asked to translate and how its answer is read: pure functions of the key and the text, so they
/// are tested with canned data and no network.
nonisolated protocol RemoteProvider: Sendable {
    func request(for text: String, from source: Locale.Language, to target: Locale.Language) throws(RemoteFailure) -> URLRequest
    func translation(from reply: HTTPReply) throws(RemoteFailure) -> String
}

nonisolated enum RemoteRequest {
    /// A JSON POST. `timeout` is how long to wait for the answer, which a language model takes longer to give.
    static func post(_ url: URL, headers: [String: String], body: some Encodable, timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = try? JSONEncoder().encode(body)
        return request
    }

    static func succeeded(_ reply: HTTPReply) -> Bool {
        (200..<300).contains(reply.status)
    }
}
