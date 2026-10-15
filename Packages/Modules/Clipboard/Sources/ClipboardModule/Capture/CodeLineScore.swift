import Foundation

/// Scores each line of a text for how much it looks like code, and decides from the lines together. A line scores one
/// point for each of: ending like a statement, calling something, using an operator, being a comment, being dense with
/// symbols and being an indented line with brackets; and two for starting like a declaration or a command. A single
/// line needs two points, several lines need at least half of them to score at all.
nonisolated enum CodeLineScore {
    static func isCode(_ lines: [DetectionSample.Line]) -> Bool {
        let scores = lines.map(score)
        guard lines.count > 1 else { return (scores.first ?? 0) >= 2 }
        let scoring = scores.count { $0 >= 1 }
        return scoring >= 2 && scoring * 2 >= lines.count
    }

    static func score(_ line: DetectionSample.Line) -> Int {
        let text = neutralized(line.text)
        var score = 0
        if hasStrongStart(text) { score += 2 }
        if endsLikeStatement(text) { score += 1 }
        if hasCall(text) { score += 1 }
        if isWholeCall(text) { score += 1 }
        if hasOperator(text) { score += 1 }
        if text.hasPrefix("//") || text.hasPrefix("/*") || text.hasPrefix("*/") || text.hasPrefix("<!--") { score += 1 }
        if isSymbolDense(text) { score += 1 }
        if line.indent >= 2, hasBracket(text) { score += 1 }
        return min(score, 3)
    }

    // MARK: Links and addresses

    /// A link or an e-mail address is full of symbols and says nothing about code, so it is replaced by a word.
    private static func neutralized(_ text: String) -> String {
        guard text.containsBytes("://") || text.containsBytes("@") else { return text }
        return text.split(separator: " ", omittingEmptySubsequences: false)
            .map { isLinkOrAddress($0) ? "x" : String($0) }
            .joined(separator: " ")
    }

    private static func isLinkOrAddress(_ token: Substring) -> Bool {
        if token.contains("://") { return true }
        guard let at = token.firstIndex(of: "@"), at != token.startIndex else { return false }
        return token[at...].contains(".")
    }

    // MARK: Declarations and commands

    private static let modifiers: Set<String> = [
        "public", "private", "protected", "internal", "fileprivate", "open", "static", "final", "override", "abstract", "async",
        "export", "default", "pub", "data", "sealed", "inline", "partial", "readonly", "unsafe",
    ]
    private static let typeWords: Set<String> = [
        "class", "struct", "enum", "interface", "protocol", "trait", "impl", "extension", "object", "record",
    ]
    private static let blockKeywords: Set<String> = [
        "if", "else", "for", "while", "switch", "guard", "catch", "try", "do", "match", "loop", "repeat", "defer", "foreach",
        "finally", "elif", "except", "with", "case", "default",
    ]
    private static let knownDecorators: Set<String> = [
        "dataclass", "staticmethod", "classmethod", "property", "override", "objc", "synthesize", "main", "escaping",
    ]
    private static let fixedStarts = [
        "#include", "#import ", "#define ", "#pragma ", "#ifdef ", "#ifndef ", "#endif", "using System", "use std::",
        "@interface ", "@implementation ", "@property", "@end", "puts ", "require '", "require \"", "require_relative ",
    ]

    /// The line starts with something that only code starts with: a preprocessor line, a declaration, a control
    /// statement that is followed by what code puts there, a decorator or a command.
    private static func hasStrongStart(_ text: String) -> Bool {
        if fixedStarts.contains(where: { text.hasPrefix($0) }) { return true }
        if text.hasPrefix("$ ") { return text.dropFirst(2).first.map { $0.isLetter || "./~".contains($0) } ?? false }
        if text.hasPrefix("@") { return isDecorator(text) }
        // A closing brace may come before "else" or "catch".
        let body = text.drop { $0 == "}" || $0 == " " }
        var rest = body
        var word = leadingWord(rest)
        var skipped = 0
        while modifiers.contains(word), skipped < 4 {
            rest = rest.dropFirst(word.count)
            // "private(set)".
            if rest.hasPrefix("("), let close = rest.firstIndex(of: ")") { rest = rest[rest.index(after: close)...] }
            rest = rest.drop { $0 == " " }
            word = leadingWord(rest)
            skipped += 1
        }
        let after = rest.dropFirst(word.count)
        switch word {
        case "func", "fn", "fun", "function": return after.contains("(")
        case "def": return after.contains { $0 != " " }
        case _ where typeWords.contains(word): return startsWithUppercase(after)
        case "namespace": return after.contains { $0 != " " }
        case "type": return after.containsAnyBytes([" struct", " interface", " = "])
        case "let", "var", "const", "val": return isBinding(after)
        case "return": return hasCodeSymbol(after)
        case "import": return isImport(after)
        case "from": return after.containsBytes(" import ")
        case "package": return after.split(separator: " ").count == 1
        case "use": return after.containsBytes("::") || after.hasSuffix(";")
        case _ where blockKeywords.contains(word): return isControl(word, after: after, line: body)
        default: return isShellCommand(text)
        }
    }

    private static func leadingWord(_ text: Substring) -> String {
        String(text.prefix { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") })
    }

    private static func startsWithUppercase(_ after: Substring) -> Bool {
        var text = after.drop { $0 == " " }
        // Generics before the name: "impl<T> Shape for Circle".
        if text.hasPrefix("<"), let close = text.firstIndex(of: ">") { text = text[text.index(after: close)...].drop { $0 == " " } }
        return text.first.map { $0.isASCII && $0.isUppercase } ?? false
    }

    /// `x = 1`, `name: String`, `a;` and the destructuring forms `(a, b) = …` and `[a, b] = …`.
    private static func isBinding(_ after: Substring) -> Bool {
        let text = after.drop { $0 == " " }
        guard let first = text.first else { return false }
        if "([{".contains(first) { return true }
        let name = text.prefix { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "$") }
        guard !name.isEmpty, let next = text.dropFirst(name.count).drop(while: { $0 == " " }).first else { return false }
        return next == "=" || next == ":" || next == ";"
    }

    private static func hasCodeSymbol(_ after: Substring) -> Bool {
        after.contains { ";([{".contains($0) } || after.containsAnyBytes([" + ", " - ", " * ", "==", "&&", "||", "=>"])
    }

    /// `import os`, `import numpy as np`, `import {a} from "b"`, `import (`; not a sentence that happens to start with it.
    private static func isImport(_ after: Substring) -> Bool {
        let text = after.drop { $0 == " " }
        guard let first = text.first else { return false }
        if "({*\"'".contains(first) || text.containsAnyBytes([" from '", " from \""]) { return true }
        return text.split(whereSeparator: \.isWhitespace).count <= 3 && !text.hasSuffix(".") && !text.containsBytes(". ")
    }

    private static func isControl(_ word: String, after: Substring, line: Substring) -> Bool {
        if line.hasSuffix("{") { return word != "with" }
        if after.drop(while: { $0 == " " }).hasPrefix("(") {
            return ["if", "for", "while", "switch", "catch", "foreach", "elif"].contains(word)
                && (line.hasSuffix(")") || line.hasSuffix(";") || line.hasSuffix(":"))
        }
        guard line.hasSuffix(":") else { return false }
        switch word {
        case "else", "try", "finally": return line == word + ":"
        case "default": return line == "default:"
        case "case", "except": return true
        default: return after.containsAnyBytes(["(", "==", "!=", "<", ">", "_", " in ", " not ", " and ", " or ", " is "])
        }
    }

    /// `@Override`, `@dataclass`, `@app.route("/")`, `@State private var x`; not a mention such as "@nobody xem giúp mình".
    private static func isDecorator(_ text: String) -> Bool {
        let name = text.dropFirst().prefix { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == ".") }
        guard let first = name.first, first.isLetter else { return false }
        let after = text.dropFirst(1 + name.count)
        if after.isEmpty || after.hasPrefix("(") {
            return after.hasPrefix("(") || first.isUppercase || name.contains(".") || knownDecorators.contains(String(name))
        }
        let next = leadingWord(after.drop { $0 == " " })
        return ["var", "let", "func", "class", "struct", "private", "public", "interface", "implementation", "property", "objc"].contains(next)
    }

    // MARK: Shell

    /// Commands nobody starts a sentence with.
    private static let commands: Set<String> = [
        "git", "npm", "npx", "yarn", "pnpm", "docker", "kubectl", "brew", "sudo", "curl", "wget", "pip", "pip3", "chmod", "chown",
        "mkdir", "apt", "apt-get", "cargo", "xcrun", "xcodebuild", "systemctl", "rm", "mv", "cp", "ssh", "scp", "grep", "sed", "awk",
        "ln", "rsync",
    ]
    /// Commands that are also words, which need a flag, a pipe, a path or a variable to count.
    private static let ambiguousCommands: Set<String> = [
        "cd", "ls", "cat", "echo", "open", "find", "go", "kill", "head", "tail", "touch", "ps", "man", "which", "env", "time",
        "make", "python", "python3", "node", "swift", "source", "export", "tar", "java", "ruby", "php", "sort", "wc", "diff", "less",
    ]

    static func isShellCommand(_ text: String) -> Bool {
        let parts = text.split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { return false }
        let command = String(parts[0])
        if commands.contains(command) { return true }
        guard ambiguousCommands.contains(command) else { return false }
        let arguments = parts[1]
        let hasFlag = arguments.split(separator: " ").contains { token in
            token.count >= 2 && token.first == "-" && token.dropFirst().first.map { $0.isLetter || $0 == "-" } == true
        }
        return hasFlag || arguments.containsAnyBytes(["|", "&&", "$", "./", "~/", "\"", "="]) || arguments.hasPrefix("/")
    }

    // MARK: Signs

    private static let blockWords: Set<String> = [
        "end", "fi", "done", "esac", "then", "do", "else", "begin", "rescue", "ensure", "pass", "break", "continue",
    ]

    /// Ends with "{", "}" or ";", is a lone "end" or "fi", or only closes brackets: "}", ");", "})".
    private static func endsLikeStatement(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        return "{};".contains(last) || blockWords.contains(text) || text.utf8.allSatisfy { ")]};,".utf8.contains($0) }
    }

    private static func hasBracket(_ text: String) -> Bool {
        text.utf8.contains { byte in
            switch byte {
            case UInt8(ascii: "("), UInt8(ascii: ")"), UInt8(ascii: "{"), UInt8(ascii: "}"), UInt8(ascii: "["), UInt8(ascii: "]"),
                 UInt8(ascii: ";"), UInt8(ascii: "="), UInt8(ascii: "<"), UInt8(ascii: ">"): true
            default: false
            }
        }
    }

    private static func isIdentifier(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: "_") || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9"))
            || (byte | 0x20 >= UInt8(ascii: "a") && byte | 0x20 <= UInt8(ascii: "z")) || byte >= 0x80
    }

    /// A name right before "(" with a ")" after it: `print(x)`, `a.b(c)`.
    private static func hasCall(_ text: String) -> Bool {
        let bytes = Array(text.utf8)
        guard let open = bytes.indices.dropFirst().first(where: { bytes[$0] == UInt8(ascii: "(") && isIdentifier(bytes[$0 - 1]) }) else {
            return false
        }
        return bytes[open...].contains(UInt8(ascii: ")"))
    }

    /// The whole line is one call with something in it that a word in brackets lacks: `print("hi")`, `f(1, 2);`.
    private static func isWholeCall(_ text: String) -> Bool {
        let bytes = Array(text.utf8)
        guard let open = bytes.firstIndex(of: UInt8(ascii: "(")), open > 0,
              bytes[..<open].allSatisfy({ isIdentifier($0) || $0 == UInt8(ascii: ".") }) else { return false }
        var end = bytes.count
        if bytes[end - 1] == UInt8(ascii: ";") { end -= 1 }
        guard end > open + 2, bytes[end - 1] == UInt8(ascii: ")") else { return false }
        return bytes[(open + 1)..<(end - 1)].contains { byte in
            byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "'") || byte == UInt8(ascii: ",") || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9"))
        }
    }

    private static let operators: [StaticString] = [
        " = ", " == ", " != ", " === ", " !== ", "=>", " -> ", " && ", " || ", "::", " += ", " -= ", "++", ":=", " <= ", " >= ",
        "<<", ">>", " |> ",
    ]

    /// An operator between spaces, or an assignment without them (`x=1`, `--flag=value`).
    private static func hasOperator(_ text: String) -> Bool {
        if text.containsAnyBytes(operators) { return true }
        let bytes = Array(text.utf8)
        guard bytes.count >= 3 else { return false }
        return (1..<bytes.count - 1).contains { index in
            bytes[index] == UInt8(ascii: "=") && isIdentifier(bytes[index - 1])
                && bytes[index + 1] != UInt8(ascii: " ") && bytes[index + 1] != UInt8(ascii: "=")
        }
    }

    /// At least three of `{}[]=<>*&|^~\` and one character in eight.
    private static func isSymbolDense(_ text: String) -> Bool {
        var symbolCount = 0, otherCount = 0
        for byte in text.utf8 {
            switch byte {
            case UInt8(ascii: "{"), UInt8(ascii: "}"), UInt8(ascii: "["), UInt8(ascii: "]"), UInt8(ascii: "="), UInt8(ascii: "<"),
                 UInt8(ascii: ">"), UInt8(ascii: "*"), UInt8(ascii: "&"), UInt8(ascii: "|"), UInt8(ascii: "^"), UInt8(ascii: "~"),
                 UInt8(ascii: "\\"):
                symbolCount += 1
            case UInt8(ascii: " "): break
            default: otherCount += 1
            }
        }
        return symbolCount >= 3 && symbolCount * 8 >= symbolCount + otherCount
    }
}
