import Foundation

/// What a selection looks like, apart from what language it is in. A language recognizer calls a URL, a path or a line of
/// code English with great confidence, and a preview of a "translation" of those beside every selection in a terminal or an
/// editor is what makes a user switch the feature off. So a text must look like something somebody wrote to be read before the
/// recognizer is asked anything.
nonisolated enum SelectionShape {
    /// How a whitespace-separated token reads.
    private enum Token {
        /// An ordinary word, with its apostrophes and hyphens.
        case word
        /// A link, address, path, hexadecimal number or identifier-like code: not a word, but it can sit in a sentence.
        case other
        /// A name used in code (`item.isEnabled`, `snake_case`, `fooBar`) or a command line flag: no sentence has these.
        case code
        /// A number or only punctuation, which says nothing either way.
        case bare
    }

    /// Whether `text` could be prose: not code, not a log line, mostly words, not just a name, not mostly punctuation or digits.
    static func isProse(_ text: String) -> Bool {
        guard !hasCodeSymbols(text), !looksLikeLog(text) else { return false }
        let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var words = 0
        var others = 0
        for token in tokens {
            switch classify(token) {
            case .word: words += 1
            case .other: others += 1
            case .code: return false
            case .bare: break
            }
        }
        // At least two thirds of the tokens that are anything must be words: a link or two in a sentence is fine.
        guard words >= 1, words * 3 >= (words + others) * 2 else { return false }
        return !isName(tokens) && punctuationShare(of: text) <= 0.25
    }

    /// Vietnamese typed without accents ("toi dang di hoc"), which the recognizer takes for Italian or Romanian. Several
    /// words from a short list of common ones, as many of them as no other language shares: two of the strong ones, or one
    /// and two of the weak ones, which are also words of English, Italian, Dutch and others.
    static func looksLikeUnaccentedVietnamese(_ text: String) -> Bool {
        var strong = 0
        var weak = 0
        for token in text.lowercased().split(whereSeparator: { !$0.isLetter }) {
            if strongVietnamese.contains(String(token)) {
                strong += 1
            } else if weakVietnamese.contains(String(token)) {
                weak += 1
            }
        }
        return strong >= 2 || (strong >= 1 && weak >= 2)
    }

    private static let strongVietnamese: Set<String> = [
        "khong", "duoc", "nhung", "nhieu", "cua", "nay", "minh", "voi", "cac", "dang", "hoc", "truong", "nguoi", "viet", "xin",
        "chao", "nhu", "nao", "roi", "cung", "tren", "duoi", "ngay", "thang", "vao", "nhe", "nha", "chua", "nhan", "gio",
    ]
    private static let weakVietnamese: Set<String> = [
        "ban", "toi", "mot", "cam", "on", "lam", "sao", "bao", "rat", "het", "la", "va", "co", "di", "thi", "cho", "den", "ma", "da",
        "se", "de", "oi", "anh", "em", "dai", "hay", "ve", "vi", "o",
    ]

    // MARK: tokens

    private static let edges = CharacterSet(charactersIn: ".,;:!?()[]\"'“”‘’…")

    private static func classify(_ token: String) -> Token {
        let core = token.trimmingCharacters(in: edges)
        guard core.contains(where: \.isLetter) || core.contains(where: \.isNumber) else { return .bare }
        if core.hasPrefix("--"), core.count > 2 { return .code }
        if core.contains("://") || core.lowercased().hasPrefix("www.") || isEmail(core) || isPath(core) || isHexOrID(core) { return .other }
        if isIdentifier(core) { return .code }
        guard core.contains(where: \.isLetter) else { return .bare }
        // Punctuation inside is fine ("so,then", the full stops of a Chinese sentence); the marks of paths, addresses and
        // code are not.
        return core.contains(where: { codeMarks.contains($0) }) ? .other : .word
    }

    private static let codeMarks: Set<Character> = ["/", "\\", "@", "_", "=", "<", ">", "|", "~", "^", "$", "#", "*", "+", "{", "}", "[", "]", ":"]

    private static func isEmail(_ core: String) -> Bool {
        matches(core, "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$")
    }

    /// A leading `/`, `~/`, `./` or `../`, a drive letter, or two slashes or more. A single slash inside ("and/or") is a word.
    private static func isPath(_ core: String) -> Bool {
        if core.count > 1, ["/", "~/", "./", "../"].contains(where: core.hasPrefix) { return true }
        return matches(core, "^[A-Za-z]:[\\\\/]") || core.filter { $0 == "/" }.count >= 2
    }

    /// `0x7ffee4b2a9c8`, a hash or an ID of eight hex digits or more, or a long mix of letters and digits ("usr8f3a2b").
    private static func isHexOrID(_ core: String) -> Bool {
        if matches(core, "^0[xX][0-9a-fA-F]+$") || matches(core, "^[0-9a-fA-F]{8,}$") { return true }
        // ASCII digits: "一" (one) is a number to Unicode, and a Chinese sentence is not an ID.
        return core.count >= 6 && core.contains(where: \.isLetter) && core.contains(where: \.isASCIIDigit)
    }

    /// `snake_case`, `camelCase` (a run of three lowercase letters or more before the first capital, so "iPhone" and "eBay"
    /// are not), and `item.isEnabled` (a dot between a letter and a letter or digit, but not "U.S." or "e.g.").
    private static func isIdentifier(_ core: String) -> Bool {
        if matches(core, "[A-Za-z0-9]_[A-Za-z0-9]") || matches(core, "^[a-z]{3,}[A-Z]") { return true }
        guard matches(core, "[A-Za-z][.][A-Za-z0-9]|[A-Za-z0-9][.][A-Za-z]") else { return false }
        return !matches(core, "^([A-Za-z]\\.)+[A-Za-z]$")
    }

    // MARK: the whole text

    /// Braces, backticks, a line ending in `;`, `=>` `->` `::` `&&` `||` `==` `!=` `+=`, an HTML tag, a call (`name(`), a lone
    /// `=` between spaces, and anything in square brackets: shell, SQL, JSON, Swift, JavaScript, markup and log levels.
    private static let codePattern = [
        "[{}`]", ";[ \\t]*(\\n|$)", "=>|->|::|&&|\\|\\||==|!=|\\+=|-=", "</?[A-Za-z!]", "[A-Za-z0-9_]\\(", "\\s=\\s", "\\[[^\\]\\n]*\\]",
    ].joined(separator: "|")

    private static func hasCodeSymbols(_ text: String) -> Bool {
        text.range(of: codePattern, options: .regularExpression) != nil
    }

    /// A date or a clock time, or a log level in capitals.
    private static func looksLikeLog(_ text: String) -> Bool {
        matches(text, "\\d{4}-\\d{2}-\\d{2}|\\d{1,2}:\\d{2}:\\d{2}|\\b(INFO|WARN|WARNING|ERROR|DEBUG|TRACE|FATAL)\\b")
    }

    /// Up to three words that all start with a capital: "Tim Cook", "Apple Park", "New York City".
    private static func isName(_ tokens: [String]) -> Bool {
        guard (1...3).contains(tokens.count) else { return false }
        return tokens.allSatisfy { token in
            let core = token.trimmingCharacters(in: edges)
            return core.first?.isUppercase == true && !core.contains(where: \.isASCIIDigit)
        }
    }

    /// Of the characters that are not spaces, the share that are not letters: digits and punctuation. (A letter with its accent
    /// as a separate mark is one character to Swift, and a letter.)
    private static func punctuationShare(of text: String) -> Double {
        let characters = text.filter { !$0.isWhitespace }
        guard !characters.isEmpty else { return 0 }
        return Double(characters.count(where: { !$0.isLetter })) / Double(characters.count)
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}
