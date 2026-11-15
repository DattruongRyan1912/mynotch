import Foundation

/// Decides from the lines of a text whether it is code, and is careful to say no: prose must never be shown as code.
///
/// A line is *strong* when it starts the way only code does (a declaration, an import, a control statement with its
/// brackets, a decorator, a preprocessor line, a shell command that has arguments) and *supporting* when it has the shape of
/// a statement (ends a block, calls something, assigns a name). Signs that prose has too (a closing `;`, ` = `, `->`, `=>`,
/// `>>`, a command word at the start) count for nothing alone. A line with letters beyond ASCII outside quotes and comments,
/// such as Vietnamese words, is prose. A block is code when it has two strong lines, or a strong line and a supporting one,
/// or brackets that nest with indentation, and at least half of its lines are one of the two.
nonisolated enum CodeLineScore {
    enum Start {
        case declaration, statement, control, shell, preprocessor, decorator
    }

    /// What makes a supporting line one: it opens or closes a block (or is a comment), calls something, or is a statement.
    enum Support {
        case structural, call, statement
    }

    enum Kind: Equatable {
        case strong(Start)
        case supporting(Support)
        case neutral
        case prose
    }

    static func isCode(_ lines: [DetectionSample.Line]) -> Bool {
        let kinds = lines.map(kind)
        if lines.count == 1 { return isCodeShaped(neutralized(lines[0].text), kinds[0]) }
        var strong = 0, structural = 0, calls = 0, supporting = 0, prose = 0
        for kind in kinds {
            switch kind {
            case .strong: strong += 1
            case .supporting(let support):
                supporting += 1
                if support == .structural { structural += 1 } else if support == .call { calls += 1 }
            case .prose: prose += 1
            case .neutral: break
            }
        }
        // A block with more than a stray line of prose is prose, whatever it holds.
        guard prose * 4 <= lines.count else { return false }
        let codeLike = strong + supporting
        guard codeLike >= 2, codeLike * 2 >= lines.count else { return false }
        // Statements alone prove nothing; a block that opens or closes, with calls in it, does.
        return strong >= 2 || (strong >= 1 && supporting >= 1) || opensBlock(lines) || (supporting >= 3 && structural >= 1 && calls >= 1)
    }

    private static func kind(_ line: DetectionSample.Line) -> Kind {
        let text = neutralized(line.text)
        if CodeLineText.hasProseLetters(text) { return .prose }
        if let start = strongStart(text) { return .strong(start) }
        return support(text, indent: line.indent).map(Kind.supporting) ?? .neutral
    }

    /// A single line is code only when it is strong and shows brackets or a closing `;` (`func f() {}`, `const x = () => 1;`),
    /// is a shell command or a preprocessor line, or is a whole call with a string, a comma or a closing `;`.
    private static func isCodeShaped(_ text: String, _ kind: Kind) -> Bool {
        switch kind {
        case .strong(let start):
            return start == .shell || start == .preprocessor || CodeLineText.hasBracketPair(text) || text.hasSuffix(";")
        case .supporting:
            return isWholeCall(text, needsContent: true) && (text.hasSuffix(";") || text.contains(where: { "\"',".contains($0) }))
        case .neutral, .prose:
            return false
        }
    }

    /// A line that ends with `{` and another indented under it. A text can be cut anywhere, so the braces need not balance.
    private static func opensBlock(_ lines: [DetectionSample.Line]) -> Bool {
        zip(lines, lines.dropFirst()).contains { $0.text.hasSuffix("{") && $1.indent > $0.indent }
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

    // MARK: Strong starts

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
        "#include <", "#include \"", "#import <", "#import \"", "#import @", "#define ", "#pragma ", "#ifdef ", "#ifndef ", "#endif",
        "using System", "use std::", "@interface ", "@implementation ", "@property", "@end", "puts \"", "puts '", "require '",
        "require \"", "require_relative '", "require_relative \"",
    ]

    private static func strongStart(_ text: String) -> Start? {
        if let fixed = fixedStarts.first(where: { text.hasPrefix($0) }) {
            return fixed.hasPrefix("#") ? .preprocessor : .statement
        }
        if text.hasPrefix("$ ") { return CodeShellLine.isCommand(String(text.dropFirst(2))) ? .shell : nil }
        if text.hasPrefix("@") { return isDecorator(text) ? .decorator : nil }
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
        case "func", "fn", "fun", "function": return opensCallable(after) ? .declaration : nil
        case "def": return isDefinition(after) ? .declaration : nil
        case _ where typeWords.contains(word): return namesType(after) ? .declaration : nil
        case "namespace": return after.contains { $0 != " " } && !CodeLineText.hasAdjacentWords(String(after)) ? .declaration : nil
        case "type": return isTypeAlias(after) ? .declaration : nil
        case "let", "var", "const", "val": return isBinding(after) ? .declaration : nil
        case "return": return isReturn(after) ? .statement : nil
        case "import": return isImport(after) ? .statement : nil
        case "from": return isFromImport(after) ? .statement : nil
        case "package": return isPackage(after) ? .statement : nil
        case "use": return after.hasSuffix(";") && (after.containsBytes("::") || after.containsBytes("\\")) ? .statement : nil
        case "defer", "go", "throw", "yield", "await": return isCallStatement(after) ? .statement : nil
        case "puts": return isShortStatement(after) ? .statement : nil
        case _ where blockKeywords.contains(word): return isControl(word, after: after, line: body) ? .control : nil
        default:
            if skipped > 0, isMember(text) { return .declaration }
            if isTypedDeclaration(text) { return .declaration }
            return CodeShellLine.isCommand(text) ? .shell : nil
        }
    }

    private static func leadingWord(_ text: Substring) -> String {
        String(text.prefix { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") })
    }

    private static func trimmed(_ text: Substring) -> Substring {
        text.drop { $0 == " " }
    }

    /// `func name(…) {`, `func (…) …` and `fn name<T>(…) -> T`: a name or nothing, then parameters that close, then what code
    /// puts after parameters. "fun with friends (summer)" and "function f(x) is defined above" are not.
    private static func opensCallable(_ after: Substring) -> Bool {
        let text = trimmed(after)
        if !text.hasPrefix("(") {
            let name = text.prefix { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
            guard !name.isEmpty, let next = text.dropFirst(name.count).first, next == "(" || next == "<" else { return false }
        }
        guard let open = text.firstIndex(of: "(") else { return false }
        return parametersEnd(text[open...])
    }

    /// `def name(…)`, `def name:` and Ruby's bare `def name`.
    private static func isDefinition(_ after: Substring) -> Bool {
        let text = trimmed(after)
        let name = text.prefix { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "." || $0 == "?" || $0 == "!") }
        guard !name.isEmpty else { return false }
        guard let next = text.dropFirst(name.count).first else { return true }
        if next == "(" { return parametersEnd(text.dropFirst(name.count)) }
        return next == ":" || next == ";"
    }

    /// The text starts with "(", and what follows its matching ")" is nothing, or a block, a colon, a return type, or an
    /// arrow, a semicolon: not a sentence.
    private static func parametersEnd(_ text: Substring) -> Bool {
        var depth = 0
        for index in text.indices {
            if text[index] == "(" { depth += 1 } else if text[index] == ")" {
                depth -= 1
                if depth == 0 {
                    let tail = trimmed(text[text.index(after: index)...])
                    return tail.isEmpty || tail.hasSuffix("{") || tail.hasSuffix(":") || tail.hasSuffix(";")
                        || tail.hasPrefix("->") || tail.hasPrefix("=>") || tail.hasPrefix("{") || tail.hasPrefix(":")
                }
            }
        }
        return false
    }

    /// An upper-case name that a block, a colon, parameters, a base or nothing follows: `class Foo {`, `struct Foo: Bar {`,
    /// `impl<T> Shape for Circle {`. "class Notes today" has words after the name.
    private static func namesType(_ after: Substring) -> Bool {
        var text = trimmed(after)
        // Generics before the name: "impl<T> Shape for Circle".
        if text.hasPrefix("<"), let close = text.firstIndex(of: ">") { text = trimmed(text[text.index(after: close)...]) }
        guard let first = text.first, first.isASCII, first.isUppercase else { return false }
        let name = text.prefix { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == ".") }
        let remainder = trimmed(text.dropFirst(name.count))
        guard let next = remainder.first else { return true }
        if "{:(<,".contains(next) || remainder.hasSuffix("{") || remainder.hasSuffix(":") { return true }
        return ["extends", "implements", "for", "where", "inherits", "with"].contains(leadingWord(remainder))
    }

    /// `type Foo struct`, `type Foo interface`, `type Foo<T> =`, `type Foo =`.
    private static func isTypeAlias(_ after: Substring) -> Bool {
        let text = trimmed(after)
        let name = text.prefix { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
        guard !name.isEmpty else { return false }
        let rest = trimmed(text.dropFirst(name.count))
        return rest.hasPrefix("struct") || rest.hasPrefix("interface") || rest.hasPrefix("=") || rest.hasPrefix("<")
    }

    /// `x = 1`, `name: String`, `a;`, `mut x: T` and the destructuring forms `(a, b) = …` and `[a, b] = …`.
    private static func isBinding(_ after: Substring) -> Bool {
        var text = trimmed(after)
        for qualifier in ["mut ", "ref "] where text.hasPrefix(qualifier) { text = trimmed(text.dropFirst(qualifier.count)) }
        guard let first = text.first else { return false }
        if "([{".contains(first) { return true }
        let name = text.prefix { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "$") }
        guard !name.isEmpty, let next = trimmed(text.dropFirst(name.count)).first else { return false }
        return next == "=" || next == ":" || next == ";"
    }

    /// `return x;`, `return f(x)`, `return a + b`, `return "ok"`; not "return to base before the storm".
    private static func isReturn(_ after: Substring) -> Bool {
        let text = String(trimmed(after))
        guard !text.isEmpty else { return false }
        let stripped = CodeLineText.strippingStrings(text)
        let hasSymbol = stripped.contains { ";([{\"'`".contains($0) } || stripped.containsAnyBytes([" + ", " - ", " * ", "==", "&&", "||", "=>"])
        return hasSymbol && !CodeLineText.hasAdjacentWords(text)
    }

    /// `import os`, `import numpy as np`, `import os, sys`, `import java.util.List;`, `import {a} from "b"`, `import (`; not
    /// "import duty is charged on every parcel".
    private static func isImport(_ after: Substring) -> Bool {
        let text = trimmed(after)
        guard let first = text.first else { return false }
        if "({*\"'".contains(first) || text.containsAnyBytes([" from '", " from \""]) { return true }
        let path = text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || " _.,;*".contains($0)) }
        return path && !text.hasSuffix(".") && !CodeLineText.hasAdjacentWords(String(text))
    }

    /// `from a.b import c`.
    private static func isFromImport(_ after: Substring) -> Bool {
        let text = trimmed(after)
        let module = text.prefix { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == ".") }
        guard !module.isEmpty, text.dropFirst(module.count).hasPrefix(" import ") else { return false }
        return trimmed(text.dropFirst(module.count + " import ".count)).first.map { $0.isLetter || "*(_".contains($0) } ?? false
    }

    /// Go's `package main`, and Java's `package com.example;`.
    private static func isPackage(_ after: Substring) -> Bool {
        let name = trimmed(after)
        guard !name.isEmpty, !name.contains(" ") else { return false }
        return name == "main" || name.contains(".") || name.hasSuffix(";")
    }

    /// `defer f.Close()`, `throw new Error("x");`, `await load(1)`.
    private static func isCallStatement(_ after: Substring) -> Bool {
        let text = String(trimmed(after))
        return hasCall(text) && !CodeLineText.hasAdjacentWords(text)
    }

    private static func isShortStatement(_ after: Substring) -> Bool {
        let text = String(trimmed(after))
        return !text.isEmpty && !CodeLineText.hasAdjacentWords(text)
    }

    /// A member declared with modifiers: `private final List<int> items = new ArrayList<>();`, `public string Name { get; set; }`.
    private static func isMember(_ text: String) -> Bool {
        guard text.hasSuffix(";") || text.hasSuffix("{") || text.hasSuffix("}") else { return false }
        return CodeLineText.hasBracketPair(text) || text.containsBytes(" = ")
    }

    private static let builtinTypes: Set<String> = [
        "int", "long", "short", "byte", "float", "double", "char", "bool", "boolean", "string", "String", "auto", "uint", "size_t", "Int",
        "UInt", "Double", "Float", "Bool", "Character", "var",
    ]

    /// `int x = 5;` and `String name = "An";`: a type, a name and a value, ended with `;`.
    private static func isTypedDeclaration(_ text: String) -> Bool {
        guard text.hasSuffix(";"), text.containsBytes(" = "), let range = text.range(of: " = ") else { return false }
        let left = text[..<range.lowerBound].split(separator: " ")
        guard left.count == 2, left[1].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) else { return false }
        let type = String(left[0])
        guard builtinTypes.contains(type) || type.contains("<") || type.hasSuffix("[]") else { return false }
        let value = text[range.upperBound...].dropLast()
        return !value.isEmpty && !CodeLineText.hasAdjacentWords(String(value))
    }

    /// A control statement with the punctuation code gives it: a block, brackets around a condition, a Python colon after a
    /// condition that is not a sentence.
    private static func isControl(_ word: String, after: Substring, line: Substring) -> Bool {
        let line = String(line)
        if line.hasSuffix("{") { return word != "with" }
        let rest = trimmed(after)
        if rest.hasPrefix("(") { return isBracketedControl(word, rest) }
        guard line.hasSuffix(":") else { return false }
        switch word {
        case "else", "try", "finally": return line == word + ":"
        case "default": return line == "default:"
        case "case": return rest.first.map { $0 == "." || $0 == "\"" || $0 == "'" || $0.isNumber || ($0.isASCII && $0.isUppercase) } ?? false
        case "except": return rest.first == ":" || rest.first == "(" || rest.first.map { $0.isASCII && $0.isUppercase } == true
        case "for": return isForIn(String(rest))
        case "if", "elif", "while", "with":
            let condition = String(rest.dropLast())
            let hasCode = condition.containsAnyBytes(["(", "==", "!=", "<", ">", "_", "."])
            return hasCode && !CodeLineText.hasAdjacentWords(condition)
        default: return false
        }
    }

    /// `if (x > 0) {`, `for (int i = 0; i < n; i++)`, `while (x) y();`. The condition must hold something code holds; "for (the
    /// record) you were right:" does not.
    private static func isBracketedControl(_ word: String, _ rest: Substring) -> Bool {
        guard ["if", "for", "while", "switch", "catch", "foreach", "elif"].contains(word) else { return false }
        var depth = 0
        var close: Substring.Index?
        for index in rest.indices {
            if rest[index] == "(" { depth += 1 } else if rest[index] == ")" {
                depth -= 1
                if depth == 0 {
                    close = index
                    break
                }
            }
        }
        guard let close else { return false }
        let condition = rest[rest.index(after: rest.startIndex)..<close]
        let tail = trimmed(rest[rest.index(after: close)...])
        let isCondition = condition.contains { "=<>!&|;.()+-*/%[]:".contains($0) } || (!condition.isEmpty && condition.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") })
        return isCondition && (tail.isEmpty || tail.hasPrefix("{") || tail.hasSuffix(";") || tail.hasSuffix(":"))
    }

    /// `for item in items:`, `for i in range(10):`.
    private static func isForIn(_ text: String) -> Bool {
        guard text.hasSuffix(":") else { return false }
        let parts = text.dropLast().split(separator: " ")
        guard parts.count == 3, parts[1] == "in" else { return false }
        return parts[0].allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == ",") }
            && parts[2].allSatisfy { $0.isASCII && !$0.isWhitespace }
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

    // MARK: Supporting lines

    private static let blockWords: Set<String> = [
        "end", "fi", "done", "esac", "then", "do", "else", "begin", "rescue", "ensure", "pass", "break", "continue",
    ]

    /// A line shaped like a statement: it opens or closes a block, is a comment, is a call, or assigns a name with something
    /// that is not a sentence on the right.
    private static func support(_ text: String, indent: Int) -> Support? {
        if text.hasPrefix("//") || text.hasPrefix("/*") || text.hasPrefix("*/") || text.hasPrefix("<!--") { return .structural }
        if blockWords.contains(text) || text.utf8.allSatisfy({ ")]};,".utf8.contains($0) }) { return .structural }
        if text.hasSuffix("{") || endsRubyBlock(text) { return .structural }
        if text.hasSuffix("}") { return hasCall(text) || CodeLineText.hasBracketPair(text) ? .call : nil }
        if isWholeCall(text, needsContent: false) { return .call }
        if text.hasSuffix(";") {
            if hasCall(text) { return .call }
            if CodeLineText.hasBracketPair(text) { return .statement }
            return isAssignment(String(text.dropLast())) ? .statement : nil
        }
        if indent >= 2, hasCall(text), text.hasSuffix(")") || text.hasSuffix(",") { return .call }
        return isAssignment(text) ? .statement : nil
    }

    /// Ruby's `… do` and `… do |x|`.
    private static func endsRubyBlock(_ text: String) -> Bool {
        if text.hasSuffix(" do") { return true }
        guard text.hasSuffix("|"), let open = text.dropLast().lastIndex(of: "|") else { return false }
        return text[..<open].hasSuffix(" do ")
    }

    /// `name = value`, `a.b = value`, `x, y := value`: one or two names, an operator between spaces, and a right side that
    /// does not read as a sentence.
    private static func isAssignment(_ text: String) -> Bool {
        guard text.containsAnyBytes([" = ", " := "]), let range = text.range(of: " = ") ?? text.range(of: " := ") else { return false }
        let left = text[..<range.lowerBound]
        let right = text[range.upperBound...]
        let names = left.split(whereSeparator: { $0 == " " || $0 == "," }).filter { !$0.isEmpty }
        guard (1...3).contains(names.count), !right.isEmpty,
              left.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "_$@.[], ".contains($0)) }) else { return false }
        return !CodeLineText.hasAdjacentWords(String(right))
    }

    // MARK: Calls

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

    /// The whole line is one call: `print(total)`, `a.b(c);`. With `needsContent`, the brackets must hold a string, a comma or
    /// a digit, which a word in brackets ("hello(world)", "item(s)") lacks: a line alone has nothing else to show it is code.
    private static func isWholeCall(_ text: String, needsContent: Bool) -> Bool {
        let bytes = Array(text.utf8)
        guard let open = bytes.firstIndex(of: UInt8(ascii: "(")), open > 0,
              bytes[..<open].allSatisfy({ isIdentifier($0) || $0 == UInt8(ascii: ".") }) else { return false }
        var end = bytes.count
        if bytes[end - 1] == UInt8(ascii: ";") { end -= 1 }
        guard end > open + 2, bytes[end - 1] == UInt8(ascii: ")") else { return false }
        guard needsContent else { return true }
        return bytes[(open + 1)..<(end - 1)].contains { byte in
            byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "'") || byte == UInt8(ascii: ",") || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9"))
        }
    }

    // MARK: Shell

    /// Used by the language guess, which counts shell lines.
    static func isShellCommand(_ text: String) -> Bool {
        CodeShellLine.isCommand(text)
    }
}
