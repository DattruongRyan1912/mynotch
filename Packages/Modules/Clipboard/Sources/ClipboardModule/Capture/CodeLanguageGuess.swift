import Foundation

/// Names the language of text that is code: each language has telltale snippets worth a few points, and the highest score
/// wins (the earlier language on a tie). Below two points it is `generic`. Documents with a shape of their own never get here.
nonisolated enum CodeLanguageGuess {
    private struct Profile {
        let language: CodeLanguage
        /// Snippets anywhere in the text, with their points.
        let snippets: [(StaticString, Int)]
        /// Whole lines, e.g. Ruby's "end".
        var lines: [String: Int] = [:]
    }

    private static let profiles: [Profile] = [
        Profile(language: .swift, snippets: [
            ("import SwiftUI", 3), ("import UIKit", 3), ("import Foundation", 3), ("import AppKit", 3), ("@State", 2),
            ("@Published", 2), ("@MainActor", 2), ("@escaping", 2), ("some View", 3), ("guard let ", 3), ("guard ", 1),
            ("if let ", 2), ("func ", 1), ("let ", 1), ("var ", 1), ("-> ", 1), ("nil", 1), ("struct ", 1), ("extension ", 1),
            ("protocol ", 1), ("try await", 2), ("async throws", 2), ("weak self", 2), ("private(set)", 2), ("case .", 2),
            (".init(", 1), ("$0", 1), ("\\(", 2),
        ]),
        Profile(language: .javascript, snippets: [
            ("console.log", 3), ("require(", 2), ("module.exports", 3), ("export default", 3), ("export const", 2),
            (" from '", 2), (" from \"", 2), ("=>", 1), ("===", 2), ("!==", 2), ("const ", 1), ("let ", 1), ("var ", 1),
            ("function", 1), ("function ", 1), ("document.", 2), ("window.", 2), ("async ", 1), ("await ", 1), ("useState", 3),
            ("Promise<", 2), ("`", 1), ("${", 1), (": string", 2), (": number", 2), ("interface ", 1), (".then(", 2),
            ("JSON.", 2),
        ]),
        Profile(language: .python, snippets: [
            ("def ", 2), ("elif ", 3), ("self.", 1), ("self,", 2), ("self)", 2), ("None", 2), ("True", 1), ("False", 1),
            ("__name__", 3), ("__init__", 3), ("lambda ", 2), ("print(", 1), (" is not ", 2), ("except ", 2), ("try:", 2),
            ("finally:", 2), ("raise ", 2), (" in range(", 3), ("@dataclass", 3), ("@staticmethod", 3), ("import numpy", 3),
            ("from ", 1), ("    return", 1),
        ], lines: ["pass": 2]),
        Profile(language: .go, snippets: [
            ("package ", 2), ("func ", 1), (":= ", 2), ("fmt.", 3), ("err != nil", 3), ("defer ", 2), ("go func", 3), ("chan ", 2),
            ("interface{}", 3), ("struct {", 2), ("import (", 2), ("import \"", 1), ("func (", 2), ("make(", 1), ("nil", 1),
            ("`json:", 3),
        ]),
        Profile(language: .rust, snippets: [
            ("fn ", 2), ("let mut ", 3), ("impl ", 2), ("pub fn", 3), ("use std::", 3), ("println!", 3), ("&self", 3), ("&mut ", 2),
            ("match ", 1), ("Option<", 2), ("Result<", 2), ("Vec<", 1), ("#[derive", 3), ("::new(", 1), ("unwrap()", 2),
            ("mod ", 1), ("trait ", 1), ("Some(", 2), ("None", 1), ("Ok(", 1), ("Err(", 1), ("=> ", 1), ("-> ", 1),
        ]),
        Profile(language: .java, snippets: [
            ("public class", 3), ("public static void main", 5), ("System.out", 4), ("import java.", 4), ("private ", 1),
            ("public ", 1), ("protected ", 1), ("@Override", 3), ("new ", 1), ("String[]", 3), ("void ", 1), ("extends ", 1),
            ("implements ", 2), ("final ", 1), ("static ", 1), ("throws ", 2), ("fun ", 3), ("val ", 2), ("data class", 4),
            ("println(", 1), ("listOf(", 3), ("companion object", 4), ("import kotlin", 4), ("import androidx", 4), ("when (", 2),
            (": Int", 2), ("?.", 1), ("!!", 1),
        ]),
        Profile(language: .c, snippets: [
            ("#include", 4), ("int main", 3), ("printf(", 2), ("std::", 3), ("cout <<", 3), ("nullptr", 2), ("template<", 3),
            ("template <", 3), ("#define", 2), ("#import", 3), ("@interface", 4), ("@implementation", 4), ("@property", 3),
            ("NSString", 3), ("[self ", 3), ("#ifdef", 2), ("typedef", 2), ("sizeof(", 2), ("malloc(", 2), ("unsigned ", 1),
            ("void ", 1), ("char *", 2), ("->", 1), ("- (void)", 3), ("@end", 3),
        ]),
        Profile(language: .csharp, snippets: [
            ("using System", 4), ("namespace ", 2), ("Console.WriteLine", 4), ("Console.", 2), ("{ get; set; }", 4),
            ("public class", 1), ("async Task", 3), ("foreach (", 2), ("List<", 2), ("new List<", 3), ("string ", 1), ("var ", 1),
            ("readonly ", 2), ("[Serializable]", 3), ("public static", 1), ("override ", 1), ("await ", 1), ("IEnumerable<", 3),
        ]),
        Profile(language: .ruby, snippets: [
            ("puts ", 3), ("require '", 3), ("require \"", 2), ("attr_accessor", 4), ("attr_reader", 4), (" do |", 4),
            (".each do", 3), ("elsif", 4), ("unless ", 3), ("#{", 3), ("def initialize", 4), ("def ", 1), ("nil", 1), ("=> ", 1),
            ("rescue", 3), (".map do", 3), ("module ", 1),
        ], lines: ["end": 3]),
        Profile(language: .php, snippets: [
            ("$this->", 4), ("->", 1), ("echo ", 2), ("function ", 1), ("namespace ", 1), ("public function", 3), ("array(", 2),
            ("isset(", 3), ("foreach (", 1), ("$_", 3), ("=> ", 1), ("?>", 2), ("::", 1),
        ]),
        Profile(language: .shell, snippets: [
            ("#!/bin/", 5), ("#!/usr/bin/env", 3), ("echo ", 2), ("$(", 2), ("${", 1), ("export ", 2), ("if [", 3), ("[[ ", 3),
            (" | ", 1), (" && ", 1), ("sudo ", 3), ("grep ", 2), ("cd ", 1), ("$1", 2), ("\"$", 2),
        ], lines: ["fi": 3, "done": 3, "then": 2, "esac": 3, "do": 2]),
    ]

    /// The telltale snippets are near the top of a file, so only its first 1.5 KB and 30 lines are looked at.
    private static let searchedBytes = 1536
    private static let searchedLines = 30

    static func guess(_ sample: DetectionSample) -> CodeLanguage {
        let head = sample.lines.prefix(searchedLines)
        let lines = Set(head.map(\.text))
        let shellCommands = head.count { CodeLineScore.isShellCommand($0.text) || $0.text.hasPrefix("$ ") }
        var text = sample.text
        return text.withUTF8 { all in
            let bytes = UnsafeBufferPointer(rebasing: all.prefix(searchedBytes))
            var best = (language: CodeLanguage.generic, score: 1)
            for profile in profiles {
                var score = 0
                for (snippet, points) in profile.snippets where contains(bytes, snippet) { score += points }
                for (line, points) in profile.lines where lines.contains(line) { score += points }
                if profile.language == .shell { score += 3 * shellCommands }
                if score > best.score { best = (profile.language, score) }
            }
            return best.language
        }
    }

    private static func contains(_ bytes: UnsafeBufferPointer<UInt8>, _ snippet: StaticString) -> Bool {
        guard let base = bytes.baseAddress else { return false }
        return memmem(base, bytes.count, snippet.utf8Start, snippet.utf8CodeUnitCount) != nil
    }
}
