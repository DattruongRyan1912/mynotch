import AppKit
import SwiftUI

/// The colours of the five token kinds. Xcode's default themes in spirit, darkened or lightened where needed so that every
/// colour reads at 4.5:1 or better on the backgrounds it is drawn on.
nonisolated enum CodePalette: Sendable, Hashable {
    /// For the notch, which is always dark.
    case dark
    /// Follows the system's light or dark appearance, for windows and panels.
    case adaptive

    enum Appearance: Sendable {
        case dark, light
    }

    struct RGB: Sendable, Equatable {
        let red: Double
        let green: Double
        let blue: Double
    }

    /// The numbers behind the colours, so tests can measure contrast.
    static func rgb(for kind: CodeTokenKind, in appearance: Appearance) -> RGB {
        switch (appearance, kind) {
        case (.dark, .keyword): RGB(red: 0.99, green: 0.37, blue: 0.64)
        case (.dark, .string): RGB(red: 0.99, green: 0.42, blue: 0.36)
        case (.dark, .comment): RGB(red: 0.55, green: 0.60, blue: 0.66)
        case (.dark, .number): RGB(red: 0.82, green: 0.75, blue: 0.41)
        case (.dark, .punctuation): RGB(red: 0.66, green: 0.67, blue: 0.71)
        case (.light, .keyword): RGB(red: 0.64, green: 0.20, blue: 0.60)
        case (.light, .string): RGB(red: 0.78, green: 0.15, blue: 0.09)
        case (.light, .comment): RGB(red: 0.34, green: 0.40, blue: 0.45)
        case (.light, .number): RGB(red: 0.15, green: 0.16, blue: 0.85)
        case (.light, .punctuation): RGB(red: 0.35, green: 0.35, blue: 0.38)
        }
    }

    private static let kinds: [CodeTokenKind] = [.keyword, .string, .comment, .number, .punctuation]

    private static let darkColors: [CodeTokenKind: Color] = Dictionary(uniqueKeysWithValues: kinds.map { kind in
        let rgb = rgb(for: kind, in: .dark)
        return (kind, Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue))
    })

    /// Each colour is chosen when it is drawn, so one highlighted string serves both appearances.
    private static let adaptiveColors: [CodeTokenKind: Color] = Dictionary(uniqueKeysWithValues: kinds.map { kind in
        (kind, Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let rgb = rgb(for: kind, in: isDark ? .dark : .light)
            return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        }))
    })

    func color(for kind: CodeTokenKind) -> Color {
        switch self {
        case .dark: Self.darkColors[kind] ?? .primary
        case .adaptive: Self.adaptiveColors[kind] ?? .primary
        }
    }
}
