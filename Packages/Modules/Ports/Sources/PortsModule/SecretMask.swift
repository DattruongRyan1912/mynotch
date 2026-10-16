import Foundation

/// Hides what looks like a secret in the arguments a process was started with, before they are ever kept: the row shows
/// `mysql -u root -p••••`, never the password. The rules are few on purpose, and a miss shows a value where a masking rule that
/// reached further would have hidden something that is not a secret (`--port 5432`, `--keep-alive`).
nonisolated enum SecretMask {
    static let mask = "••••"

    /// A name with one of these words (`--access-token`, `DB_PASSWORD`, `clientSecret`) holds a secret. `requirepass` is
    /// Redis's, which listens on a development port.
    private static let secretWords: Set<String> = [
        "password", "passwd", "pwd", "pass", "passphrase", "token", "secret", "bearer", "requirepass", "apikey",
    ]
    /// With one of these the value only says where a secret is, or how it is given: `--password-file /run/secrets/db`.
    private static let pointerWords: Set<String> = ["file", "path", "dir", "stdin", "prompt", "through", "env"]
    /// Tools whose `-pSECRET` is the password. For `psql` and most others `-p` is the port, so they are not here.
    private static let passwordAfterP: Set<String> = [
        "mysql", "mysqldump", "mysqladmin", "mysqlimport", "mysqlcheck", "mysqlshow", "mariadb", "mariadb-dump", "mariadb-admin",
    ]

    private static let assignment = try! NSRegularExpression(pattern: "([A-Za-z0-9_.\\-]+)=")
    /// `scheme://user:password@host`
    private static let urlPassword = try! NSRegularExpression(pattern: "(://[^/?#@\\s:]*:)[^/?#@\\s]+(@)")
    private static let bearer = try! NSRegularExpression(pattern: "(\\bbearer\\s+)[^\\s\"']+", options: .caseInsensitive)

    /// The arguments with the values of secrets replaced by `mask`, flag names kept.
    static func mask(_ arguments: [String]) -> [String] {
        let program = arguments.first.map { URL(fileURLWithPath: $0).lastPathComponent.lowercased() } ?? ""
        var masked: [String] = []
        var hideNext = false
        for (index, argument) in arguments.enumerated() {
            if hideNext, !argument.hasPrefix("-") {
                masked.append(mask)
                hideNext = false
                continue
            }
            hideNext = false
            guard index > 0 else {
                masked.append(argument)
                continue
            }
            if passwordAfterP.contains(program), argument.hasPrefix("-p"), !argument.hasPrefix("--"), argument.count > 2 {
                masked.append("-p" + mask)
                continue
            }
            // `--token abc`: the value is the next argument, unless that is another flag (`--password --verbose`).
            if argument.hasPrefix("-"), !argument.contains("="), isSecretName(argument) { hideNext = true }
            masked.append(maskInline(argument))
        }
        return masked
    }

    /// Whether a flag, variable or query parameter name holds a secret.
    static func isSecretName(_ name: String) -> Bool {
        let words = words(in: name)
        if words.contains(where: pointerWords.contains) { return false }
        if words.contains(where: secretWords.contains) { return true }
        return zip(words, words.dropFirst()).contains { $0 == "api" && $1 == "key" }
    }

    /// `--access-token`, `DB_PASSWORD` and `clientSecret` as lowercase words: split at anything that is not a letter or a digit
    /// and where a lower case letter meets an upper case one.
    static func words(in name: String) -> [String] {
        var words: [String] = []
        var current = ""
        var previousWasLower = false
        for character in name {
            guard character.isLetter || character.isNumber else {
                if !current.isEmpty { words.append(current.lowercased()) }
                current = ""
                previousWasLower = false
                continue
            }
            if character.isUppercase, previousWasLower {
                words.append(current.lowercased())
                current = ""
            }
            current.append(character)
            previousWasLower = character.isLowercase
        }
        if !current.isEmpty { words.append(current.lowercased()) }
        return words
    }

    /// One argument on its own: `name=value` pairs with a secret name (at the start, after another `=`, or in a URL's query),
    /// the password of a URL, and what follows `Bearer`.
    private static func maskInline(_ argument: String) -> String {
        let source = argument as NSString
        var edits: [NSRange] = []
        var resumeAt = 0
        for match in assignment.matches(in: argument, range: NSRange(location: 0, length: source.length)) where match.range.location >= resumeAt {
            guard isSecretName(source.substring(with: match.range(at: 1))) else { continue }
            let start = match.range.upperBound
            var end = source.length
            // In a query string the value ends at the next parameter; anywhere else it is the rest of the argument.
            if match.range.location > 0, "&?;".utf16.contains(source.character(at: match.range.location - 1)) {
                end = (start..<source.length).first { index in
                    let unit = source.character(at: index)
                    return unit == 38 || unit == 59 || Unicode.Scalar(unit).map(CharacterSet.whitespacesAndNewlines.contains) == true
                } ?? source.length
            }
            guard end > start else { continue }
            edits.append(NSRange(location: start, length: end - start))
            resumeAt = end
        }
        var text = argument
        for range in edits.reversed() { text = (text as NSString).replacingCharacters(in: range, with: mask) }
        text = urlPassword.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: "$1\(mask)$2")
        return bearer.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: "$1\(mask)")
    }
}
