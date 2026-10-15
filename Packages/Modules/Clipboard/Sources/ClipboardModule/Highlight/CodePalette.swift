import AppKit
import SwiftUI

/// The colours of the five token kinds. Xcode's default themes, so code looks as it does in an editor.
nonisolated enum CodePalette: Sendable, Hashable {
    /// For the notch, which is always dark.
    case dark
    /// Follows the system's light or dark appearance, for windows and panels.
    case adaptive

    func color(for kind: CodeTokenKind) -> Color {
        let scheme = switch self {
        case .dark: Scheme.dark
        case .adaptive: Scheme.adaptive
        }
        return switch kind {
        case .keyword: scheme.keyword
        case .string: scheme.string
        case .comment: scheme.comment
        case .number: scheme.number
        case .punctuation: scheme.punctuation
        }
    }

    private struct Scheme: Sendable {
        let keyword: Color
        let string: Color
        let comment: Color
        let number: Color
        let punctuation: Color

        static let dark = Scheme(
            keyword: rgb(0.99, 0.37, 0.64), string: rgb(0.99, 0.42, 0.36), comment: rgb(0.51, 0.56, 0.62),
            number: rgb(0.82, 0.75, 0.41), punctuation: rgb(0.66, 0.67, 0.71)
        )
        private static let light = Scheme(
            keyword: rgb(0.68, 0.24, 0.64), string: rgb(0.82, 0.18, 0.11), comment: rgb(0.44, 0.50, 0.55),
            number: rgb(0.15, 0.16, 0.85), punctuation: rgb(0.35, 0.35, 0.38)
        )
        /// Each colour is chosen when it is drawn, so one highlighted string serves both appearances.
        static let adaptive = Scheme(
            keyword: pair(\.keyword), string: pair(\.string), comment: pair(\.comment), number: pair(\.number),
            punctuation: pair(\.punctuation)
        )

        private static func rgb(_ red: Double, _ green: Double, _ blue: Double) -> Color {
            Color(.sRGB, red: red, green: green, blue: blue)
        }

        private static func pair(_ part: KeyPath<Scheme, Color>) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return NSColor((isDark ? dark : light)[keyPath: part])
            })
        }
    }
}
