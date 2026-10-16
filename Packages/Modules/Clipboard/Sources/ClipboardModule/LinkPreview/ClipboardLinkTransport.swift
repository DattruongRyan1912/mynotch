import Foundation

/// One GET, as the fetcher asks for it. The transport follows no redirect: a 3xx answer is the answer, and the fetcher decides.
nonisolated struct ClipboardLinkRequest: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        /// A page: read only its head.
        case page
        case image
    }

    var url: URL
    var kind: Kind
    /// The most bytes of the body to read. Past it the rest is left unread.
    var byteLimit: Int
}

nonisolated struct ClipboardLinkResponse: Sendable, Equatable {
    var status: Int
    /// The `Content-Type` header.
    var contentType: String?
    /// The `Location` header of a redirect.
    var location: String?
    /// At most the request's `byteLimit` bytes, and for a page only up to the end of its head.
    var body: Data
    /// There was more than `body` holds.
    var wasCut: Bool
}

/// The only way the link preview touches the network, as a protocol so tests answer from a table and no test opens a connection.
protocol ClipboardLinkTransport: Sendable {
    func get(_ request: ClipboardLinkRequest) async throws -> ClipboardLinkResponse

    /// The addresses a name resolves to, as text; empty when it does not resolve. Asked about a name before it is opened, so a name
    /// that points at the user's own network is refused like an address that does.
    func addresses(for host: String) async -> [String]
}

/// What a module made without a network (every test) has: nothing is ever opened.
struct ClipboardNoNetwork: ClipboardLinkTransport {
    func get(_ request: ClipboardLinkRequest) async throws -> ClipboardLinkResponse {
        throw URLError(.notConnectedToInternet)
    }

    func addresses(for host: String) async -> [String] { [] }
}
