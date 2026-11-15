import Foundation

/// What looks like a password or a key, and so is never handed to an agent: not redacted, since an agent that sees where
/// something was cut still knows something was there, but dropped as a whole. It is a guess from the shape of the text, and
/// MyNotch says so; it runs on every item whatever its flag says, because the flag is set only by the app that copied (a password
/// manager does; a web page, a terminal or an admin console does not).
///
/// It reads the start of a text, as much as an agent could be given or could search (`maxScannedCharacters`), and what it hides it
/// hides whole.
nonisolated enum ClipboardMCPSecretFilter {
    /// More than an item's returned 8 KB and than the 20,000 characters the search index looks at.
    static let maxScannedCharacters = 32_768

    // MARK: Items

    /// The text an agent could be given of the item. A file is its names, which is all an agent is told of it.
    static func texts(of item: ClipboardItem) -> [String] {
        switch item.content {
        case .image: []
        case .files(let urls): [urls.map(\.lastPathComponent).joined(separator: "\n")]
        case .text, .richText, .link, .color: item.content.plainText.map { [$0] } ?? []
        }
    }

    static func hides(_ item: ClipboardItem) -> Bool {
        texts(of: item).contains(where: looksLikeSecret)
    }

    /// Verdicts kept per item, so a history is read once and not at every call. The hash fixes the content: an item that is
    /// copied again with other text has another hash.
    final class Cache {
        private var verdicts: [UUID: (hash: String, hides: Bool)] = [:]
        /// How many items were actually read, for tests.
        private(set) var scanCount = 0
        var verdictCount: Int { verdicts.count }

        func hides(_ item: ClipboardItem) -> Bool {
            if let known = verdicts[item.id], known.hash == item.contentHash { return known.hides }
            scanCount += 1
            let hides = ClipboardMCPSecretFilter.hides(item)
            verdicts[item.id] = (item.contentHash, hides)
            return hides
        }

        /// Drops the verdicts of items that are no longer in the history.
        func keepOnly(_ ids: Set<UUID>) {
            verdicts = verdicts.filter { ids.contains($0.key) }
        }
    }

    // MARK: Text

    static func looksLikeSecret(_ text: String) -> Bool {
        let scanned = String(text.unicodeScalars.prefix(maxScannedCharacters))
        guard !scanned.isEmpty else { return false }
        return hasKnownShape(scanned) || hasPasswordLine(scanned) || hasRandomToken(scanned)
    }

    // MARK: Known shapes

    private struct Shape {
        let expression: NSRegularExpression
        /// Looks at the match, for the shapes that a pattern alone would take for ordinary words.
        let accepts: (@Sendable (String) -> Bool)?

        init(_ pattern: String, options: NSRegularExpression.Options = [], accepts: (@Sendable (String) -> Bool)? = nil) {
            // The patterns are constants and every one is exercised by a test.
            expression = try! NSRegularExpression(pattern: pattern, options: options)
            self.accepts = accepts
        }
    }

    /// Not in the middle of a word, so "desk-lamp..." is not a key that starts with "sk-".
    private static let boundary = "(?<![A-Za-z0-9])"

    private static let shapes: [Shape] = [
        // A PEM block of any kind: a key, a certificate, a signature.
        Shape("-----BEGIN [A-Z0-9][A-Z0-9 ]*-----"),
        // sk-, sk-ant-, sk-proj-: a hyphenated word is not one, so the tail must have a digit or a capital.
        Shape("\(boundary)sk-(?:ant-|proj-)?[A-Za-z0-9_-]{20,}") { match in
            match.contains { $0.isNumber || $0.isUppercase }
        },
        Shape("\(boundary)gh[pousr]_[A-Za-z0-9]{20,}"),
        Shape("\(boundary)github_pat_[A-Za-z0-9_]{20,}"),
        Shape("\(boundary)xox[abprso]-[A-Za-z0-9-]{10,}"),
        Shape("hooks\\.slack\\.com/services/T[A-Z0-9]+/B[A-Z0-9]+/[A-Za-z0-9]+"),
        Shape("discord(?:app)?\\.com/api/webhooks/[0-9]+/[A-Za-z0-9_-]+"),
        Shape("\(boundary)(?:AKIA|ASIA)[0-9A-Z]{16}(?![A-Za-z0-9])"),
        Shape("\(boundary)AIza[0-9A-Za-z_-]{30,}"),
        Shape("\(boundary)glpat-[A-Za-z0-9_-]{20,}"),
        Shape("\(boundary)[sr]k_(?:live|test)_[A-Za-z0-9]{16,}"),
        // A JWT: three base64url segments, the first of which is a JSON header. From the start of a run only, as above.
        Shape("(?<![A-Za-z0-9_-])eyJ[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]*"),
        Shape("bearer\\s+[A-Za-z0-9._~+/=-]{16,}", options: .caseInsensitive),
        Shape("authorization\\s*[:=]\\s*(?:basic|bearer|token|digest)\\s+\\S{8,}", options: .caseInsensitive),
        // scheme://user:password@host, with or without a user name. Only from the start of a word, or a long run of letters would be
        // tried from every letter in it.
        Shape("(?<![A-Za-z0-9+.-])[A-Za-z][A-Za-z0-9+.-]*://[^\\s:/@]*:[^\\s@/]+@[^\\s/]+"),
        // A link that carries a credential in its query or fragment, whatever else is in it.
        Shape(
            "[?&;#](?:token|access_token|id_token|refresh_token|auth|key|api_?key|api-key|password|passwd|pwd|secret|client_secret|sig|signature|session_?id|jwt)=[^&\\s#\"']{4,}",
            options: .caseInsensitive
        ),
    ]

    private static func hasKnownShape(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return shapes.contains { shape in
            guard let accepts = shape.accepts else { return shape.expression.firstMatch(in: text, range: range) != nil }
            return shape.expression.matches(in: text, range: range).contains { match in
                Range(match.range, in: text).map { accepts(String(text[$0])) } ?? false
            }
        }
    }

    // MARK: Password lines

    /// A word that names a secret, then `:` or `=`, then a value. Read on the folded text (lower case, no accents), so
    /// "Mật khẩu: abc123" is "mat khau: abc123". `pwd` and `otp` must start a word: "hotpot: delicious" is not an OTP.
    private static let passwordLine = try! NSRegularExpression(
        pattern: "(?:(?<![a-z])(?:pwd|otp)|password|passwd|passphrase|secret|api[_ -]?key|access[_ -]?key|private[_ -]?key|token|mat khau|ma bi mat|ma otp)[\"']?\\s*(?::(?!:)|=(?!=))\\s*[\"']?([^\\s\"'<>]{4,})"
    )

    /// What follows the colon in a declaration or a form, not a value.
    private static let notValues: Set<String> = [
        "string", "str", "int", "integer", "bool", "boolean", "number", "float", "double", "data", "bytes", "any", "object", "void", "null",
        "nil", "none", "true", "false", "undefined", "required", "optional",
    ]

    private static func hasPasswordLine(_ text: String) -> Bool {
        let folded = ClipboardSearchIndex.fold(text)
        let range = NSRange(folded.startIndex..., in: folded)
        return passwordLine.matches(in: folded, range: range).contains { match in
            guard let value = Range(match.range(at: 1), in: folded) else { return false }
            let word = folded[value].trimmingCharacters(in: CharacterSet(charactersIn: ";,.)}]"))
            return !notValues.contains(word)
        }
    }

    // MARK: Random tokens

    /// A key has no spaces, is long, mixes letters and digits and looks random. A path, a slug, a file name, an identifier, a UUID
    /// and a hash are long too; each fails one of the tests below. A link is read by the segments of its path only: its query
    /// and fragment are where ordinary links keep their opaque ids (a key there is caught by name instead).
    private static let minimumLength = 32
    private static let minimumEntropy = 4.0
    /// The longest run between separators: a random token has one, words and file names do not.
    private static let minimumChunk = 20
    private static let tokenDelimiters = CharacterSet(charactersIn: "\"'`(){}[]<>,;|=:")

    private static func hasRandomToken(_ text: String) -> Bool {
        text.split(whereSeparator: \.isWhitespace).contains { run in
            if let schemeEnd = run.range(of: "://"), run[run.startIndex..<schemeEnd.lowerBound].allSatisfy({ $0.isLetter || $0.isNumber || "+.-".contains($0) }) {
                return linkSegments(of: run[schemeEnd.upperBound...]).contains(where: looksRandom)
            }
            let pieces = run.components(separatedBy: tokenDelimiters)
            return pieces.contains { piece in
                // An absolute or relative path, which has the folders' names in it.
                let isPath = ["/", "~/", "./", "../"].contains { piece.hasPrefix($0) } && piece.split(separator: "/").count >= 3
                return !isPath && looksRandom(Substring(piece))
            }
        }
    }

    /// The path of a link, after its host, split into segments.
    private static func linkSegments(of rest: Substring) -> [Substring] {
        let withoutQuery = rest.prefix { $0 != "?" && $0 != "#" }
        guard let firstSlash = withoutQuery.firstIndex(of: "/") else { return [] }
        return withoutQuery[firstSlash...].split(separator: "/")
    }

    private static func looksRandom(_ token: Substring) -> Bool {
        guard token.unicodeScalars.count >= minimumLength else { return false }
        let hasDigit = token.contains(where: \.isNumber)
        let hasLetter = token.contains(where: \.isLetter)
        guard hasDigit, hasLetter else { return false }
        // A hash is long and has digits and letters, and is something worth keeping.
        guard !token.allSatisfy(\.isHexDigit) else { return false }
        guard token.split(whereSeparator: { "-_./".contains($0) }).contains(where: { $0.count >= minimumChunk }) else { return false }
        return entropy(of: token) >= minimumEntropy
    }

    /// Shannon entropy, in bits per character.
    private static func entropy(of token: Substring) -> Double {
        var counts: [Unicode.Scalar: Int] = [:]
        for scalar in token.unicodeScalars { counts[scalar, default: 0] += 1 }
        let total = Double(token.unicodeScalars.count)
        return counts.values.reduce(0) { sum, count in
            let share = Double(count) / total
            return sum - share * log2(share)
        }
    }
}
