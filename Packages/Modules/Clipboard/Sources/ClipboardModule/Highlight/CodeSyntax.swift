import Foundation

/// What one family of languages writes comments, strings and keywords like. `CodeScanner` is the same for all of them.
nonisolated struct CodeSyntax {
    enum SingleQuote {
        /// A string, with or without backslash escapes.
        case string(escapes: Bool)
        /// A one-character literal: `'x'`, `'\n'`; a lone quote is punctuation.
        case character
        /// A character literal, or a lifetime (`'a`, `'static`), which has no colour.
        case rustCharacter
        /// Not a quote at all.
        case none
    }

    enum Backtick {
        /// JavaScript: may span lines and holds `${…}` code.
        case template
        /// Go: a raw string.
        case raw
        case none
    }

    var keywords: Set<String> = []
    var ignoresCase = false
    var lineComments: [StaticString] = []
    /// A `#` comment starts only at the beginning of a line or after a space (shell, YAML), so `a#b` is not one.
    var commentNeedsSpace = false
    var blockComment: (open: StaticString, close: StaticString)?
    var nestedComments = false
    /// Backslash escapes in double quotes (all but SQL).
    var backslashEscapes = true
    var singleQuote = SingleQuote.string(escapes: true)
    var backtick = Backtick.none
    /// `"""…"""` (and `'''…'''` where single quotes make strings).
    var tripleQuotes = false
    /// `#"…"#` (Swift) and `r#"…"#` (Rust): no escapes, closed by a quote and as many `#`.
    var hashStrings = false
    /// Words that, right before a quote, belong to the string: Python's `f"…"`, Rust's `b"…"` and `r"…"`.
    var stringPrefixes: Set<String> = []
    /// C#'s `@"…"`, where `""` is a quote.
    var verbatimStrings = false
    /// `''` inside a quoted string is a quote (SQL, YAML).
    var doubledQuotes = false
    /// Swift's `\(…)`.
    var interpolatesParentheses = false
    /// `$name` is a variable, never a keyword (shell, PHP).
    var variables = false
    /// `@word` is a keyword: Objective-C's `@interface`, CSS's `@media`.
    var atKeywords = false
    /// `#include` at the start of a line.
    var preprocessor = false
    /// A string or word followed by a colon is a key (JSON, YAML, CSS declarations).
    var highlightsKeys = false
    var negativeNumbers = false
    /// `#fff` inside braces is a number.
    var hexColors = false
    /// Characters that may continue a word without starting one: `runs-on`, `margin-top`.
    var wordExtras: Set<UInt8> = []
    /// PHP's `<?php` and `?>`.
    var phpTags = false

    static func of(_ language: CodeLanguage) -> CodeSyntax {
        switch language {
        case .swift:
            CodeSyntax(
                keywords: Keywords.swift, lineComments: ["//"], blockComment: ("/*", "*/"), nestedComments: true,
                singleQuote: .none, tripleQuotes: true, hashStrings: true, interpolatesParentheses: true
            )
        case .javascript:
            CodeSyntax(keywords: Keywords.javascript, lineComments: ["//"], blockComment: ("/*", "*/"), backtick: .template)
        case .python:
            CodeSyntax(
                keywords: Keywords.python, lineComments: ["#"], tripleQuotes: true,
                stringPrefixes: ["r", "b", "f", "u", "rb", "br", "fr", "rf", "bf", "fb", "ur"]
            )
        case .go:
            CodeSyntax(keywords: Keywords.go, lineComments: ["//"], blockComment: ("/*", "*/"), singleQuote: .character, backtick: .raw)
        case .rust:
            CodeSyntax(
                keywords: Keywords.rust, lineComments: ["//"], blockComment: ("/*", "*/"), nestedComments: true,
                singleQuote: .rustCharacter, hashStrings: true, stringPrefixes: ["b", "r", "br"]
            )
        case .java:
            CodeSyntax(
                keywords: Keywords.java, lineComments: ["//"], blockComment: ("/*", "*/"), singleQuote: .character, tripleQuotes: true
            )
        case .c:
            CodeSyntax(
                keywords: Keywords.c, lineComments: ["//"], blockComment: ("/*", "*/"), singleQuote: .character, atKeywords: true,
                preprocessor: true
            )
        case .csharp:
            CodeSyntax(
                keywords: Keywords.csharp, lineComments: ["//"], blockComment: ("/*", "*/"), singleQuote: .character,
                tripleQuotes: true, verbatimStrings: true
            )
        case .ruby:
            CodeSyntax(keywords: Keywords.ruby, lineComments: ["#"])
        case .php:
            CodeSyntax(keywords: Keywords.php, lineComments: ["//", "#"], blockComment: ("/*", "*/"), variables: true, phpTags: true)
        case .shell:
            CodeSyntax(
                keywords: Keywords.shell, lineComments: ["#"], commentNeedsSpace: true, singleQuote: .string(escapes: false),
                variables: true
            )
        case .sql:
            CodeSyntax(
                keywords: Keywords.sql, ignoresCase: true, lineComments: ["--"], blockComment: ("/*", "*/"), backslashEscapes: false,
                singleQuote: .string(escapes: false), doubledQuotes: true
            )
        case .json:
            CodeSyntax(keywords: ["true", "false", "null"], singleQuote: .none, highlightsKeys: true, negativeNumbers: true)
        case .yaml:
            CodeSyntax(
                keywords: ["true", "false", "null"], lineComments: ["#"], commentNeedsSpace: true,
                singleQuote: .string(escapes: false), doubledQuotes: true, highlightsKeys: true, wordExtras: Set("-./".utf8)
            )
        case .css:
            CodeSyntax(blockComment: ("/*", "*/"), atKeywords: true, highlightsKeys: true, hexColors: true, wordExtras: Set("-".utf8))
        case .generic, .xml, .markdown:
            CodeSyntax(keywords: Keywords.generic, lineComments: ["//"], blockComment: ("/*", "*/"))
        }
    }
}

/// Space-separated lists, so each language reads at a glance.
private nonisolated enum Keywords {
    static func set(_ words: String) -> Set<String> {
        Set(words.split(separator: " ").map(String.init))
    }

    static let swift = set("""
    associatedtype class deinit enum extension fileprivate func import init inout internal let open operator private \
    precedencegroup protocol public rethrows static struct subscript typealias var break case catch continue default defer do \
    else fallthrough for guard if in repeat return throw switch where while as await async false is nil self Self super throws \
    true try some any actor final override mutating lazy weak unowned convenience required indirect nonisolated isolated
    """)
    static let javascript = set("""
    break case catch class const continue debugger default delete do else export extends finally for function if import in \
    instanceof let new return super switch this throw try typeof var void while with yield async await of static get set null \
    undefined true false interface type enum implements private protected public readonly abstract declare namespace as from \
    keyof infer never unknown any string number boolean symbol bigint
    """)
    static let python = set("""
    False None True and as assert async await break class continue def del elif else except finally for from global if import \
    in is lambda nonlocal not or pass raise return try while with yield
    """)
    static let go = set("""
    break default func interface select case defer go map struct chan else goto package switch const fallthrough if range type \
    continue for import return var nil true false iota
    """)
    static let rust = set("""
    as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref \
    return self Self static struct super trait true type unsafe use where while union macro_rules
    """)
    static let java = set("""
    abstract assert boolean break byte case catch char class const continue default do double else enum extends final finally \
    float for goto if implements import instanceof int interface long native new package private protected public return short \
    static strictfp super switch synchronized this throw throws transient try void volatile while true false null var record \
    sealed permits yield fun val when object companion data override open internal lateinit by is as typealias suspend inline \
    reified init constructor out operator infix tailrec vararg
    """)
    static let c = set("""
    auto break case char const continue default do double else enum extern float for goto if inline int long register restrict \
    return short signed sizeof static struct switch typedef union unsigned void volatile while bool true false NULL nullptr class \
    namespace template typename public private protected virtual override final new delete this using try catch throw operator \
    constexpr noexcept explicit friend mutable self nil YES NO id BOOL SEL
    """)
    static let csharp = set("""
    abstract as base bool break byte case catch char checked class const continue decimal default delegate do double else enum \
    event explicit extern false finally fixed float for foreach goto if implicit in int interface internal is lock long namespace \
    new null object operator out override params private protected public readonly ref return sbyte sealed short sizeof static \
    string struct switch this throw true try typeof uint ulong unchecked unsafe ushort using virtual void volatile while var \
    async await dynamic yield record init required partial
    """)
    static let ruby = set("""
    BEGIN END alias and begin break case class def do else elsif end ensure false for if in module next nil not or redo rescue \
    retry return self super then true undef unless until when while yield
    """)
    static let php = set("""
    abstract and array as break callable case catch class clone const continue declare default do echo else elseif empty \
    enddeclare endfor endforeach endif endswitch endwhile eval exit extends final finally fn for foreach function global goto if \
    implements include include_once instanceof insteadof interface isset list match namespace new or print private protected \
    public readonly require require_once return static switch throw trait try unset use var while xor yield true false null
    """)
    static let shell = set("""
    if then else elif fi for while until do done case esac in function select return exit break continue local export readonly \
    declare unset shift source alias set trap eval exec
    """)
    static let sql = set("""
    select from where insert into values update set delete create alter drop table index view database schema join inner left \
    right outer full cross on group by order having limit offset union all distinct as and or not null is in like between exists \
    case when then else end primary key foreign references default unique check constraint asc desc count sum avg min max with \
    begin commit rollback truncate if cascade returning using natural true false
    """)
    static let generic = set("if else for while return function class import let var const true false null nil fn func def")
}
