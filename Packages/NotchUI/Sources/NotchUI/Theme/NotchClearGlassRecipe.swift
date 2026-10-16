import Foundation
import SwiftUI

/// TEMPORARY (U3g, step 1): candidates for what "Trong vắt" is made of, to compare on screen. Step 2 keeps the one that is chosen as
/// `NotchGlassClarity.clear`'s glass, deletes this file, the two keys and the plumbing, and puts a source guard in their place.
///
/// Today's clear glass (`Glass.clear`) shows the wallpaper almost unblurred and dims it under dark content. These keep the glass's
/// rim and lens but try to blur what is behind it the way `Glass.regular` does, and to darken it less. They are for the glass of
/// `interface.glassClarity = clear` and for nothing else: "Cân bằng" and the classic look do not read them.
///
/// Plain `UserDefaults.standard` keys, read once, when the app makes its notches (relaunch after a change), with no settings UI;
/// a value that is missing, of another type or not a name below falls back to today's glass:
///
///     debug.glass.clearRecipe    raw | regularLight | regularTint | clearOverBlur | regularOverBlur
///     debug.glass.clearTint      0 ... 0.6 (regularTint only; default 0.12)
///     debug.glass.clearMaterial  ultraThin | thin | regular | thick | ultraThick (the two OverBlur recipes only; default ultraThin)
nonisolated enum NotchClearRecipe: String, CaseIterable, Sendable {
    /// Today's `Glass.clear`.
    case raw
    /// `Glass.regular` with the notch's colour scheme forced to light, so the glass takes its light look (less dark). The scheme
    /// flows into everything in the notch, so the text tokens follow it: `.primary` and `.secondary` (the notch's own text, glyphs and
    /// the tab bar, and a module's system text) become dark on the light glass, whatever the system's appearance is; a colour a
    /// module fixes itself (a literal white) stays as it is.
    case regularLight
    /// `Glass.regular` tinted with white at `debug.glass.clearTint`: the tint lifts the dark regular glass towards a clear one.
    case regularTint
    /// `Glass.clear` over a material (`debug.glass.clearMaterial`) drawn under it for the notch's and the tiles' shapes (not the
    /// bubbles'), so the blur comes from the material and the rim and lens from the glass. Every SwiftUI material blurs with the same
    /// radius (60, measured in the layer tree, against 4 in the regular glass's own filter, at the same quarter resolution); they differ
    /// in how much they saturate and in the grey they lay over it.
    case clearOverBlur
    /// The same under `Glass.regular`: the strongest blur of the candidates, and the darkest.
    case regularOverBlur
}

/// The SwiftUI materials a candidate can draw under the glass.
nonisolated enum NotchBlurMaterial: String, CaseIterable, Sendable {
    case ultraThin, thin, regular, thick, ultraThick

    var material: Material {
        switch self {
        case .ultraThin: .ultraThinMaterial
        case .thin: .thinMaterial
        case .regular: .regularMaterial
        case .thick: .thickMaterial
        case .ultraThick: .ultraThickMaterial
        }
    }
}

nonisolated struct NotchClearRecipeSwitch: Equatable, Sendable {
    enum Key {
        static let recipe = "debug.glass.clearRecipe"
        static let tint = "debug.glass.clearTint"
        static let material = "debug.glass.clearMaterial"
    }

    static let tintRange: ClosedRange<Double> = 0...0.6
    static let defaultTint = 0.12

    var recipe = NotchClearRecipe.raw
    var tint = defaultTint
    var material = NotchBlurMaterial.ultraThin

    /// Today's glass.
    static let `default` = NotchClearRecipeSwitch()

    init(recipe: NotchClearRecipe = .raw, tint: Double = defaultTint, material: NotchBlurMaterial = .ultraThin) {
        self.recipe = recipe
        self.material = material
        self.tint = tint.isFinite ? min(max(tint, Self.tintRange.lowerBound), Self.tintRange.upperBound) : Self.defaultTint
    }

    /// What `defaults` holds. The name is matched ignoring case and surrounding spaces; the tint may be a number or a string
    /// (`defaults write` stores a bare `0.12` as a string, and `-float` as a number) and is held to `tintRange`.
    init(reading defaults: UserDefaults) {
        func name(_ key: String) -> String? { (defaults.object(forKey: key) as? String).map { $0.trimmingCharacters(in: .whitespaces).lowercased() } }
        let recipe = NotchClearRecipe.allCases.first { $0.rawValue.lowercased() == name(Key.recipe) }
        let material = NotchBlurMaterial.allCases.first { $0.rawValue.lowercased() == name(Key.material) }
        let tint: Double? = switch defaults.object(forKey: Key.tint) {
        case let number as NSNumber: number.doubleValue
        case let string as String: Double(string.trimmingCharacters(in: .whitespaces))
        default: nil
        }
        self.init(recipe: recipe ?? .raw, tint: tint ?? Self.defaultTint, material: material ?? .ultraThin)
    }

    /// The glass of "Trong vắt" under this recipe.
    var clearGlass: Glass {
        switch recipe {
        case .raw, .clearOverBlur: .clear
        case .regularLight, .regularOverBlur: .regular
        case .regularTint: .regular.tint(.white.opacity(tint))
        }
    }

    /// The colour scheme the notch is forced to, if any.
    var forcedScheme: ColorScheme? { recipe == .regularLight ? .light : nil }

    /// The material drawn under the notch's and the tiles' glass, if any.
    var materialUnder: NotchBlurMaterial? { recipe == .clearOverBlur || recipe == .regularOverBlur ? material : nil }
}
