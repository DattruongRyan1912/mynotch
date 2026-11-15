import Foundation
import Testing
@testable import ClipboardModule

/// What the tokenizer finds, as "k:" keyword, "s:" string, "c:" comment, "n:" number or "p:" punctuation followed by the
/// text of the token. Text between tokens (names, spaces) has no token.
private func scan(_ text: String, _ language: CodeLanguage) -> [String] {
    let bytes = Array(text.utf8)
    return CodeTokenizer.tokens(in: text, language: language).map { token in
        let tag = switch token.kind {
        case .keyword: "k"
        case .string: "s"
        case .comment: "c"
        case .number: "n"
        case .punctuation: "p"
        }
        return tag + ":" + String(decoding: bytes[token.range], as: UTF8.self)
    }
}

@Suite struct CodeTokenizerTests {
    // MARK: Swift

    @Test func swiftKeywordsNumbersAndLineComments() {
        #expect(scan("let x = 42 // answer", .swift) == ["k:let", "p:=", "n:42", "c:// answer"])
    }

    @Test func swiftStringsKeepTheirEscapes() {
        #expect(scan(#""a\"b" + "c""#, .swift) == [#"s:"a\"b""#, "p:+", #"s:"c""#])
        #expect(scan(#""trailing backslash \\" + 1"#, .swift) == [#"s:"trailing backslash \\""#, "p:+", "n:1"])
    }

    @Test func swiftBlockCommentsNest() {
        #expect(scan("/* a /* b */ c */ x", .swift) == ["c:/* a /* b */ c */"])
    }

    @Test func swiftRawAndMultilineStrings() {
        #expect(scan(##"#"say "hi" \n"#"##, .swift) == [##"s:#"say "hi" \n"#"##])
        #expect(scan("\"\"\"\nline \"one\"\n\"\"\" x", .swift) == ["s:\"\"\"\nline \"one\"\n\"\"\""])
    }

    @Test func swiftInterpolationIsCodeInsideAString() {
        #expect(scan(#""x \(a + 1) y""#, .swift) == [#"s:"x "#, #"p:\("#, "p:+", "n:1", "p:)", #"s: y""#])
        #expect(scan(#""\(f(1)) done""#, .swift) == [#"s:""#, #"p:\("#, "p:(", "n:1", "p:))", #"s: done""#])
    }

    @Test func aKeywordInsideANameIsNotAKeyword() {
        #expect(scan("letter iffy for_each elseif", .swift).isEmpty)
        #expect(scan("if_else = 1", .swift) == ["p:=", "n:1"])
    }

    @Test func numbersInTheirUsualForms() {
        #expect(scan("0xFF 1_000 3.14e-2 1..5 x1", .swift) == ["n:0xFF", "n:1_000", "n:3.14e-2", "n:1", "p:..", "n:5"])
        #expect(scan("t.0 .5", .swift) == ["p:.", "n:0", "n:.5"])
    }

    @Test func aStringWithoutItsEndStopsAtTheEndOfTheLine() {
        #expect(scan("\"abc\nlet", .swift) == ["s:\"abc", "k:let"])
    }

    @Test func aCommentWithoutItsEndRunsToTheEndOfTheText() {
        #expect(scan("x /* abc\n def", .swift) == ["c:/* abc\n def"])
    }

    // MARK: JavaScript

    @Test func javascriptTemplateLiteralsNestAndRunCode() {
        #expect(scan("`a ${b + `c ${d}`} e`", .javascript) == [
            "s:`a ", "p:${", "p:+", "s:`c ", "p:${", "p:}", "s:`", "p:}", "s: e`",
        ])
        #expect(scan("`two\nlines`", .javascript) == ["s:`two\nlines`"])
    }

    @Test func javascriptStringsComments() {
        #expect(scan(#"'it\'s' + "x" // c"#, .javascript) == [#"s:'it\'s'"#, "p:+", #"s:"x""#, "c:// c"])
        #expect(scan("const f = (a) => a /* c */", .javascript) == ["k:const", "p:=", "p:(", "p:)", "p:=>", "c:/* c */"])
        #expect(scan("type T = string", .javascript) == ["k:type", "p:=", "k:string"])
    }

    @Test func javascriptBlockCommentsDoNotNest() {
        #expect(scan("/* a /* b */ c", .javascript) == ["c:/* a /* b */"])
    }

    // MARK: Python

    @Test func pythonComments() {
        #expect(scan("def f(x): # note", .python) == ["k:def", "p:(", "p:):", "c:# note"])
        #expect(scan(#""a # b""#, .python) == [#"s:"a # b""#])
    }

    @Test func pythonTripleQuotedStringsSpanLines() {
        #expect(scan("\"\"\"doc\nmore\"\"\" + x", .python) == ["s:\"\"\"doc\nmore\"\"\"", "p:+"])
        #expect(scan("'''a \"quoted\" b'''", .python) == ["s:'''a \"quoted\" b'''"])
    }

    @Test func pythonStringPrefixesBelongToTheString() {
        #expect(scan(#"f"{x}" r'\d' rb"x""#, .python) == [#"s:f"{x}""#, #"s:r'\d'"#, #"s:rb"x""#])
        #expect(scan("fx = 1", .python) == ["p:=", "n:1"])
    }

    @Test func pythonConstants() {
        #expect(scan("None True x", .python) == ["k:None", "k:True"])
    }

    // MARK: Shell

    @Test func shellCommentsNeedASpaceBeforeThem() {
        #expect(scan(#"echo "a $b" # done"#, .shell) == [#"s:"a $b""#, "c:# done"])
        #expect(scan("a#b", .shell) == ["p:#"])
        #expect(scan("# whole line", .shell) == ["c:# whole line"])
    }

    @Test func shellSingleQuotesHaveNoEscapes() {
        #expect(scan(#"'raw \' x"#, .shell) == [#"s:'raw \'"#])
    }

    @Test func shellKeywords() {
        #expect(scan("for f in *; do", .shell) == ["k:for", "k:in", "p:*;", "k:do"])
    }

    // MARK: Go, Rust, Java, C, C#, Ruby, PHP

    @Test func goRawStringsAndRunes() {
        #expect(scan("`a\nb` 'x' '\\n'", .go) == ["s:`a\nb`", "s:'x'", "s:'\\n'"])
        #expect(scan("func main() {}", .go) == ["k:func", "p:()", "p:{}"])
    }

    @Test func rustRawStringsLifetimesAndChars() {
        #expect(scan(##"r#"a "b" c"# + 1"##, .rust) == [##"s:r#"a "b" c"#"##, "p:+", "n:1"])
        #expect(scan(#"&'a str 'x' '\n'"#, .rust) == ["p:&", "s:'x'", #"s:'\n'"#])
        #expect(scan("&'static str", .rust) == ["p:&"])
        #expect(scan(#"b"ab" br"c\d""#, .rust) == [#"s:b"ab""#, #"s:br"c\d""#])
    }

    @Test func rustCommentsNestAndNumbersHaveSuffixes() {
        #expect(scan("/* /* */ */ fn", .rust) == ["c:/* /* */ */", "k:fn"])
        #expect(scan("1_000u32 0b1010 1e3 2.5f32", .rust) == ["n:1_000u32", "n:0b1010", "n:1e3", "n:2.5f32"])
    }

    @Test func javaTextBlocksAndCharacters() {
        #expect(scan("\"\"\"\n a \"b\"\n\"\"\" 'c' '\\u0041'", .java) == ["s:\"\"\"\n a \"b\"\n\"\"\"", "s:'c'", #"s:'\u0041'"#])
        #expect(scan("public static void main // c", .java) == ["k:public", "k:static", "k:void", "c:// c"])
    }

    @Test func cPreprocessorLinesCharactersAndNumbers() {
        #expect(scan("#include <stdio.h>", .c) == ["k:#include", "p:<", "p:.", "p:>"])
        #expect(scan(#"'\'' "x" 10UL 0x1F 1.5f"#, .c) == [#"s:'\''"#, #"s:"x""#, "n:10UL", "n:0x1F", "n:1.5f"])
        #expect(scan("@interface Foo", .c) == ["k:@interface"])
        #expect(scan("/* a /* b */ c", .c) == ["c:/* a /* b */"])
    }

    @Test func csharpVerbatimStrings() {
        #expect(scan(##"@"a ""q"" b" + 1"##, .csharp) == [##"s:@"a ""q"" b""##, "p:+", "n:1"])
        #expect(scan("using System; // c", .csharp) == ["k:using", "p:;", "c:// c"])
    }

    @Test func rubyAndPHP() {
        #expect(scan(#"puts "a" # c"#, .ruby) == [#"s:"a""#, "c:# c"])
        #expect(scan("def x; end", .ruby) == ["k:def", "p:;", "k:end"])
        #expect(scan("<?php echo $a; // c", .php) == ["k:<?php", "k:echo", "p:;", "c:// c"])
        #expect(scan("$if = 1; # c", .php) == ["p:=", "n:1", "p:;", "c:# c"])
    }

    // MARK: SQL, JSON, YAML

    @Test func sqlKeywordsAreCaseInsensitiveAndQuotesDouble() {
        #expect(scan("SELECT 'it''s' -- c", .sql) == ["k:SELECT", "s:'it''s'", "c:-- c"])
        #expect(scan(#"select "Name" From t /* x */ 1.5"#, .sql) == ["k:select", #"s:"Name""#, "k:From", "c:/* x */", "n:1.5"])
    }

    @Test func jsonKeysValuesAndNegativeNumbers() {
        #expect(scan(#"{"a": [1, -2.5e3, true, null, "x\"y"]}"#, .json) == [
            "p:{", #"k:"a""#, "p::", "p:[", "n:1", "p:,", "n:-2.5e3", "p:,", "k:true", "p:,", "k:null", "p:,", #"s:"x\"y""#, "p:]}",
        ])
    }

    @Test func yamlKeysCommentsAndListMarks() {
        let yaml = "name: \"x\" # c\nlist:\n  - 1\n  - true"
        #expect(scan(yaml, .yaml) == ["k:name", "p::", #"s:"x""#, "c:# c", "k:list", "p::", "p:-", "n:1", "p:-", "k:true"])
        #expect(scan("a: b#c", .yaml) == ["k:a", "p::", "p:#"])
        #expect(scan("runs-on: ubuntu", .yaml) == ["k:runs-on", "p::"])
    }

    // MARK: Markup

    @Test func xmlTagsAttributesAndComments() {
        #expect(scan(#"<a href="x">t<!-- c --></a>"#, .xml) == ["p:<", "k:a", "p:=", #"s:"x""#, "p:>", "c:<!-- c -->", "p:</", "k:a", "p:>"])
        #expect(scan("<br/>", .xml) == ["p:<", "k:br", "p:/>"])
        #expect(scan(#"<?xml version="1.0"?>"#, .xml) == ["p:<?", "k:xml", "p:=", #"s:"1.0""#, "p:?>"])
        #expect(scan("<!DOCTYPE html>", .xml) == ["p:<!", "k:DOCTYPE", "p:>"])
    }

    @Test func cssRulesAtRulesAndColours() {
        #expect(scan("a { color: #fff; margin: -4px 1.5em; } /* c */", .css) == [
            "p:{", "k:color", "p::", "n:#fff", "p:;", "k:margin", "p::", "p:-", "n:4px", "n:1.5em", "p:;", "p:}", "c:/* c */",
        ])
        #expect(scan("@media (min-width: 600px) { }", .css) == ["k:@media", "p:(", "p::", "n:600px", "p:)", "p:{", "p:}"])
        #expect(scan("a:hover { }", .css) == ["p::", "p:{", "p:}"])
        #expect(scan("#main { }", .css) == ["p:#", "p:{", "p:}"])
    }

    @Test func markdownHeadingsFencesInlineCodeAndQuotes() {
        let text = "# Title\n- item `code`\n> quote\n```x\ncode\n```"
        #expect(scan(text, .markdown) == ["k:# Title", "p:-", "s:`code`", "c:> quote", "s:```x\ncode\n```"])
    }

    @Test func aFenceWithoutItsEndRunsToTheEndOfTheText() {
        #expect(scan("```\nunfinished", .markdown) == ["s:```\nunfinished"])
    }

    @Test func genericCodeGetsStringsCommentsAndNumbers() {
        #expect(scan(#"foo("a", 1) // c"#, .generic) == ["p:(", #"s:"a""#, "p:,", "n:1", "p:)", "c:// c"])
    }

    // MARK: Robustness

    @Test func tokensAreOrderedInsideTheTextAndOnCharacterBoundaries() {
        let samples = (CodeSamples.code + CodeSamples.prose).map(\.text) + ["\"Hôm nay\" // đẹp 日本語 `x ${ế}` 🙏", "\u{0}\u{1}ế\"", ""]
        for language in CodeLanguage.allCases {
            for text in samples {
                let bytes = Array(text.utf8)
                var end = 0
                for token in CodeTokenizer.tokens(in: text, language: language) {
                    #expect(token.range.lowerBound >= end && token.range.lowerBound < token.range.upperBound && token.range.upperBound <= bytes.count)
                    end = token.range.upperBound
                    if token.range.upperBound <= bytes.count {
                        let slice = String(decoding: bytes[token.range], as: UTF8.self)
                        #expect(!slice.contains("\u{FFFD}") || text.contains("\u{FFFD}"), "\(language) \(text.debugDescription)")
                    }
                }
            }
        }
    }

    @Test func deeplyNestedInterpolationDoesNotOverflowTheStack() {
        let text = "`" + String(repeating: "${`", count: 5_000) + String(repeating: "`}", count: 5_000) + "`"
        #expect(!CodeTokenizer.tokens(in: text, language: .javascript).isEmpty)
        let swift = "\"" + String(repeating: "\\(\"", count: 5_000)
        #expect(!CodeTokenizer.tokens(in: swift, language: .swift).isEmpty)
    }

    @Test func aLongLineWithoutAnythingToColourIsFine() {
        let text = String(repeating: "word ", count: 20_000)
        #expect(CodeTokenizer.tokens(in: text, language: .swift).isEmpty)
    }
}
