import Foundation

/// Reads a link's page for its title and one small picture, through a `ClipboardLinkTransport`. Every address it opens, the page's and each
/// picture's, goes through the same checks: `ClipboardLinkGuard` on the address, a lookup of the name whose answer must be public too, at most
/// three redirects each checked the same way, a time limit on every request and on the whole, and a cap on what is read. The safety lives
/// here and not in a session, so a test with a fake transport can try every way a page might send MyNotch somewhere it must not go.
///
/// It has no logger on purpose: the address and the title are the user's, and a log line is a place for them to leak to.
nonisolated struct ClipboardLinkFetcher: Sendable {
    /// The most of a page that is read; only its head is looked at.
    static let pageByteLimit = 512 * 1024
    /// A larger picture is not used, not even in part.
    static let imageByteLimit = 2 * 1024 * 1024
    static let redirectLimit = 3
    static let requestTimeout: Duration = .seconds(5)
    /// For the page and its pictures together.
    static let totalTimeout: Duration = .seconds(20)
    /// How many addresses are tried for the picture: `og:image`, then the icons the page names, then `/favicon.ico`.
    static let pictureAttempts = 3

    enum Outcome: Sendable, Equatable {
        /// The page answered. Either part may be nil: no title, or no picture that could be used.
        case read(title: String?, image: Data?)
        /// Nothing could be read: refused address, no answer, an error status, too slow.
        case failed
    }

    enum Failure: Error {
        case forbidden, badStatus, tooManyRedirects, timedOut
    }

    let transport: any ClipboardLinkTransport
    /// How a limit is waited out. A parameter so that a test decides when a limit runs out, instead of racing a clock that a busy machine
    /// can make fire too early.
    typealias Sleep = @Sendable (Duration) async throws -> Void

    let requestTimeout: Duration
    let totalTimeout: Duration
    let sleep: Sleep

    init(
        transport: any ClipboardLinkTransport, requestTimeout: Duration = Self.requestTimeout, totalTimeout: Duration = Self.totalTimeout,
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
    ) {
        self.transport = transport
        self.requestTimeout = requestTimeout
        self.totalTimeout = totalTimeout
        self.sleep = sleep
    }

    /// Off the main actor, where the page is read and parsed and the picture decoded.
    @concurrent func fetch(_ url: URL) async -> Outcome {
        guard ClipboardLinkGuard.allows(url), !ClipboardLinkGuard.looksSingleUse(url) else { return .failed }
        do {
            return try await within(totalTimeout) { try await read(url) }
        } catch {
            return .failed
        }
    }

    // MARK: Reading

    private func read(_ url: URL) async throws -> Outcome {
        let (pageURL, page) = try await get(url, kind: .page, limit: Self.pageByteLimit)
        guard (200..<300).contains(page.status) else { throw Failure.badStatus }
        // A link to a PDF or a download has no head to read.
        guard Self.isHTML(page.contentType) else { return .read(title: nil, image: nil) }
        let head = ClipboardLinkHead.parse(page.body, contentType: page.contentType, pageURL: pageURL)
        var candidates = [head.openGraphImage].compactMap(\.self) + head.icons
        if let favicon = ClipboardLinkHead.absolute("/favicon.ico", relativeTo: pageURL) { candidates.append(favicon) }
        var tried = Set<URL>()
        var image: Data?
        for candidate in candidates {
            guard tried.count < Self.pictureAttempts else { break }
            guard tried.insert(candidate).inserted else { continue }
            try Task.checkCancellation()
            if let png = await picture(at: candidate) {
                image = png
                break
            }
        }
        return .read(title: head.title, image: image)
    }

    /// The picture at `url` as a stored thumbnail; nil for anything that goes wrong, so the next address gets its turn.
    private func picture(at url: URL) async -> Data? {
        guard let (_, response) = try? await get(url, kind: .image, limit: Self.imageByteLimit), (200..<300).contains(response.status),
              !response.wasCut, Self.isPicture(response.contentType), !response.body.isEmpty else { return nil }
        return await ClipboardLinkImage.thumbnailPNG(from: response.body)
    }

    /// One address, following up to three redirects. The answer is the last page's, with that page's address (relative addresses in it
    /// are against that).
    private func get(_ start: URL, kind: ClipboardLinkRequest.Kind, limit: Int) async throws -> (URL, ClipboardLinkResponse) {
        var current = start
        var redirects = 0
        while true {
            try await check(current)
            // A page that sends the request on to a login or a one-time link is not followed there; a picture is part of a page that
            // was already read and is often signed, so it is not held to this.
            if kind == .page, ClipboardLinkGuard.looksSingleUse(current) { throw Failure.forbidden }
            let request = ClipboardLinkRequest(url: current, kind: kind, byteLimit: limit)
            let response = try await within(requestTimeout) { try await transport.get(request) }
            guard Self.redirectStatuses.contains(response.status) else { return (current, response) }
            redirects += 1
            guard redirects <= Self.redirectLimit else { throw Failure.tooManyRedirects }
            guard let location = response.location, let next = ClipboardLinkHead.absolute(location, relativeTo: current) else { throw Failure.badStatus }
            current = next
        }
    }

    private static let redirectStatuses: Set<Int> = [301, 302, 303, 307, 308]

    /// The address is allowed and so is where its name leads. An IP address needs no lookup; a name that does not resolve, or resolves
    /// to even one address that is not public, is refused.
    ///
    /// **This is not a defence against DNS rebinding**: the session resolves the name again when it connects, and a server that answers
    /// differently the second time gets MyNotch to connect to an address chosen by the page. What keeps that harmless is a property outside
    /// this package: App Transport Security refuses plain `http://` to a name, so only https is ever sent, and a LAN server cannot complete a
    /// TLS handshake for the page's name, so no HTTP request reaches it and nothing is read back. **Whoever adds an ATS exception for
    /// http previews makes rebinding a blind GET with a path the page chooses, and must close it first**: check
    /// `URLSessionTaskMetrics.remoteAddress` against `ClipboardLinkGuard.isForbidden(address:)` and drop the answer (which stops the data
    /// being read, not the request), or better connect to the address that was checked, with the certificate evaluated against the name.
    private func check(_ url: URL) async throws {
        guard ClipboardLinkGuard.allows(url), let host = ClipboardLinkGuard.host(of: url) else { throw Failure.forbidden }
        if ClipboardLinkGuard.isLiteralAddress(host) { return }
        let addresses = try await within(requestTimeout) { await transport.addresses(for: host) }
        guard !addresses.isEmpty, !addresses.contains(where: ClipboardLinkGuard.isForbidden(address:)) else { throw Failure.forbidden }
    }

    // MARK: Kinds of answer

    /// No header at all is taken as a page; any other kind is not.
    static func isHTML(_ contentType: String?) -> Bool {
        guard let kind = contentType?.lowercased() else { return true }
        return kind.hasPrefix("text/html") || kind.hasPrefix("application/xhtml+xml")
    }

    /// `image/*` but not SVG, which ImageIO cannot read.
    static func isPicture(_ contentType: String?) -> Bool {
        guard let kind = contentType?.lowercased() else { return false }
        return kind.hasPrefix("image/") && !kind.hasPrefix("image/svg")
    }

    // MARK: Time

    /// Runs `work` and gives up after `limit`: the first of the two to finish wins and the other is cancelled. The limit is the total for
    /// the work, which the transport's own timeout (the time between two bytes) is not: a server that sends a byte a second would never
    /// reach it.
    func within<Value: Sendable>(_ limit: Duration, _ work: @escaping @Sendable () async throws -> Value) async throws -> Value {
        let sleep = sleep
        return try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await sleep(limit)
                throw Failure.timedOut
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw Failure.timedOut }
            return first
        }
    }
}
