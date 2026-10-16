import Foundation
import SwiftUI

/// How clear the notch's Liquid Glass is (`interface.glassClarity`).
nonisolated public enum NotchGlassClarity: String, Codable, Sendable, CaseIterable {
    /// `Glass.regular`: it adapts its tint and its text to what is behind it, so it reads on any background. The default.
    case balanced
    /// `Glass.clear`: the wallpaper shows through almost unblurred, as in Control Center. What is behind shows sharply, so on a light
    /// page full of text the notch's own text is hard to read; opt-in.
    case clear

    var glass: Glass {
        switch self {
        case .balanced: .regular
        case .clear: .clear
        }
    }
}

/// What the open notch's glass is made of (`interface.glassShape`).
nonisolated public enum NotchGlassShape: String, Codable, Sendable, CaseIterable {
    /// One piece of glass behind everything. The default.
    case slab
    /// No glass on the panel itself: the tab bar sits in one glass capsule and the module's content in one glass tile, with the
    /// desktop showing in the gap between them (as Control Center's tiles sit on the wallpaper). They come straight out of the
    /// collapsed notch as it opens, and merge back into it as it closes. Only while the notch is open: the collapsed notch, a toast
    /// and the bubbles are glass as before.
    case tiles
}

/// The user's two choices about the Liquid Glass, read live from the settings by `NotchTheme`.
nonisolated struct NotchGlassStyle: Equatable, Sendable {
    var clarity = NotchGlassClarity.balanced
    var shape = NotchGlassShape.slab

    static let `default` = NotchGlassStyle()
}

/// The one key of the glass that is not a setting: a switch for support.
///
/// The Liquid Glass of the notch is always drawn as an active window's (`ActiveGlassAppearance`), which needs a private AppKit method.
/// If a macOS update makes that misbehave, a plain defaults write turns it off without a new build:
///
///     defaults write io.lucasvu.mynotch debug.glass.inactive -int 1
///
/// It is read once, when a notch is made, and is not shown in the settings. It is the only `debug.glass.*` key read.
nonisolated enum NotchGlassSupport {
    static let inactiveKey = "debug.glass.inactive"

    /// Whether the notch's glass is to be drawn as an active window's: the positive meaning of the switch, which is what `ScreenManager`
    /// hands every notch it makes. True unless the key says otherwise.
    static func drawsActiveGlass(_ defaults: UserDefaults) -> Bool {
        !keepsGlassInactive(defaults)
    }

    /// Whether `defaults` asks for the glass to stay subdued: 1, true or yes, as a number or a string. Anything else, and a missing
    /// key, is no.
    static func keepsGlassInactive(_ defaults: UserDefaults) -> Bool {
        switch defaults.object(forKey: inactiveKey) {
        case let number as NSNumber: number.intValue == 1
        case let string as String: ["1", "true", "yes"].contains(string.trimmingCharacters(in: .whitespaces).lowercased())
        default: false
        }
    }
}
