import Foundation

/// The languages the detector tells apart. Related ones share a case (TypeScript is `javascript`, Kotlin is `java`,
/// C++ and Objective-C are `c`), because they share one tokenizer; `generic` is code in no language it knows.
nonisolated enum CodeLanguage: String, Codable, Sendable, CaseIterable {
    case swift, javascript, python, go, rust, java, c, csharp, ruby, php, shell, sql, json, yaml, xml, css, markdown, generic

    var title: String {
        switch self {
        case .swift: "Swift"
        case .javascript: "JavaScript / TypeScript"
        case .python: "Python"
        case .go: "Go"
        case .rust: "Rust"
        case .java: "Java / Kotlin"
        case .c: "C / C++ / Objective-C"
        case .csharp: "C#"
        case .ruby: "Ruby"
        case .php: "PHP"
        case .shell: "Shell"
        case .sql: "SQL"
        case .json: "JSON"
        case .yaml: "YAML"
        case .xml: "XML / HTML"
        case .css: "CSS"
        case .markdown: "Markdown"
        case .generic: "Mã"
        }
    }
}

/// What a text turned out to be when it was copied, decided once and stored with the item. An item saved before code
/// detection existed has none, and gets one when the history loads.
nonisolated enum CodeDetection: Hashable, Sendable {
    case notCode
    case code(CodeLanguage)

    var language: CodeLanguage? {
        if case .code(let language) = self { language } else { nil }
    }
}

/// Stored as one word, "text" or the language's name, so the history file stays readable and a language this version does
/// not know (written by a later one) still reads as code.
nonisolated extension CodeDetection: Codable {
    private static let notCodeWord = "text"

    init(from decoder: any Decoder) throws {
        let word = try decoder.singleValueContainer().decode(String.self)
        self = word == Self.notCodeWord ? .notCode : .code(CodeLanguage(rawValue: word) ?? .generic)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(language?.rawValue ?? Self.notCodeWord)
    }
}
