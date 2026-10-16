import Foundation

/// A link that is meant to be opened once, by the person it was made for: a login, a verification, an invitation, an unsubscribe, a password
/// reset, a signed download. A request for its page, made before the user opens it, can use it up, and it carries a credential to the server in
/// a request nobody asked for. The R3h secret filter answers another question (what may an agent be shown) and exempts hashes and ids on
/// purpose; this one answers "may MyNotch send a GET for this link", and when in doubt says no: a preview that is not shown costs nothing.
nonisolated extension ClipboardLinkGuard {
    /// A parameter whose name has one of these as a whole word (`token`, `access_token`, `accessToken`, `X-Amz-Signature`; not `keyword`
    /// or `monkey`) carries a credential or names a step that is done once.
    private static let credentialWords: Set<String> = [
        "code", "token", "otp", "magic", "signature", "sig", "key", "apikey", "secret", "pass", "password", "passwd", "pwd", "auth", "session",
        "sessionid", "sessid", "jsessionid", "phpsessid", "sid", "ticket", "nonce", "credential", "credentials", "hash", "invite", "reset",
        "verify", "verification", "confirm", "confirmation", "unsubscribe", "activate", "activation", "login", "signin",
    ]

    /// A short segment of the path (at most three words, so `reset-password` and `confirm-subscription` but not an article's title) that
    /// has one of these as a word is the step of a flow.
    private static let flowWords: Set<String> = [
        "unsubscribe", "invite", "reset", "verify", "verification", "confirm", "confirmation", "magic", "login", "signin", "callback", "activate",
        "activation", "auth", "oauth", "oauth2", "token", "password", "redeem",
    ]

    /// How long a segment of letters, digits, `-` and `_` must be before it can be a token and not a title.
    private static let tokenLength = 20

    /// Whether the link looks like one that is used once, or carries a credential. Looks at the parameters of the query and of the fragment
    /// (also a fragment that is a route, as a single-page app writes `#/auth/callback?code=…`), at the words of the path, and at the shape of
    /// its segments: a UUID, a long run of hex, a long base64url string, or a short code behind a one-letter segment (`/s/Kj8dN2pQ`,
    /// the shape of share and tracking links).
    static func looksSingleUse(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return true }
        if looksSingleUse(path: components.percentEncodedPath, parameters: components.percentEncodedQuery) { return true }
        guard let fragment = components.percentEncodedFragment, !fragment.isEmpty else { return false }
        // `#access_token=…&state=…` is parameters; `#/auth/callback?code=…` is a route with parameters; `#section-2` is neither.
        if let mark = fragment.firstIndex(of: "?") {
            return looksSingleUse(path: String(fragment[..<mark]), parameters: String(fragment[fragment.index(after: mark)...]))
        }
        if let equals = fragment.firstIndex(of: "="), !fragment[..<equals].contains("/") { return looksSingleUse(path: "", parameters: fragment) }
        return looksSingleUse(path: fragment, parameters: nil)
    }

    private static func looksSingleUse(path: String, parameters: String?) -> Bool {
        if let parameters, hasCredentialParameter(parameters) { return true }
        let segments = (path.removingPercentEncoding ?? path).split(separator: "/").map(String.init)
        for (index, whole) in segments.enumerated() {
            // `page;jsessionid=…`: what follows a semicolon is a parameter of the segment.
            let pieces = whole.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
            let segment = pieces.first ?? whole
            if pieces.count > 1, hasCredentialParameter(pieces.dropFirst().joined(separator: "&")) { return true }
            if looksLikeToken(segment) || isFlowStep(segment) { return true }
            if index + 1 < segments.count, isShortLinkPrefix(segment), looksLikeShortCode(segments[index + 1]) { return true }
        }
        return false
    }

    // MARK: Parameters

    private static func hasCredentialParameter(_ parameters: String) -> Bool {
        for parameter in parameters.split(whereSeparator: { $0 == "&" || $0 == ";" }) {
            let parts = parameter.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let name = String(parts[0]).removingPercentEncoding ?? String(parts[0])
            if !credentialWords.isDisjoint(with: words(of: name)) { return true }
            if parts.count > 1, looksLikeWebToken(String(parts[1]).removingPercentEncoding ?? String(parts[1])) { return true }
        }
        return false
    }

    /// A JSON Web Token (`eyJ…`, which is `{"` in base64) as a value: three dot-separated parts.
    private static func looksLikeWebToken(_ value: String) -> Bool {
        value.hasPrefix("eyJ") && value.count >= tokenLength && value.contains(".")
    }

    /// The words of a name: split at anything that is not a letter or digit and where a lower-case letter is followed by an upper-case one,
    /// in lower case.
    static func words(of name: String) -> [String] {
        var words: [String] = []
        var current = ""
        var previousWasLower = false
        for character in name {
            guard character.isLetter || character.isNumber else {
                if !current.isEmpty { words.append(current) }
                current = ""
                previousWasLower = false
                continue
            }
            if character.isUppercase, previousWasLower {
                words.append(current)
                current = ""
            }
            current += character.lowercased()
            previousWasLower = character.isLowercase
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    // MARK: Segments

    private static func isFlowStep(_ segment: String) -> Bool {
        let words = words(of: withoutExtension(segment))
        return words.count <= 3 && !flowWords.isDisjoint(with: words)
    }

    private static func withoutExtension(_ segment: String) -> String {
        guard let dot = segment.lastIndex(of: "."), segment.distance(from: dot, to: segment.endIndex) <= 6, dot != segment.startIndex else { return segment }
        return String(segment[..<dot])
    }

    /// A segment that is not a title or a name: a UUID, hex, or a long string made of pieces that are not words.
    private static func looksLikeToken(_ segment: String) -> Bool {
        let text = withoutExtension(segment)
        guard text.count >= tokenLength, text.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return false }
        // A UUID, or long hex with or without its dashes.
        let withoutDashes = text.filter { $0 != "-" }
        if withoutDashes.count >= tokenLength, withoutDashes.allSatisfy(\.isHexDigit) { return true }
        // Pieces between `-` and `_`: a title is made of words (lower case, UPPER, Capitalised, or digits); a token is made of runs that
        // are not. Half of the characters in such runs is a token.
        let pieces = text.split(whereSeparator: { $0 == "-" || $0 == "_" })
        let opaque = pieces.filter { !isWordLike($0) }.reduce(0) { $0 + $1.count }
        return opaque * 2 >= text.count
    }

    private static func isWordLike(_ piece: Substring) -> Bool {
        if piece.allSatisfy(\.isNumber) { return true }
        guard piece.allSatisfy(\.isLetter) else { return false }
        return piece.allSatisfy(\.isLowercase) || piece.allSatisfy(\.isUppercase) || piece.dropFirst().allSatisfy(\.isLowercase)
    }

    /// `/s/…`, `/l/…`, `/c/…`: one letter, which share and tracking links use before their code.
    private static func isShortLinkPrefix(_ segment: String) -> Bool {
        segment.count == 1 && segment.allSatisfy { $0.isASCII && $0.isLetter }
    }

    /// Six or more characters with a letter and a digit in them: a code, not a name.
    private static func looksLikeShortCode(_ segment: String) -> Bool {
        let text = withoutExtension(segment)
        return text.count >= 6 && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
            && text.contains(where: \.isNumber) && text.contains(where: \.isLetter)
    }
}
