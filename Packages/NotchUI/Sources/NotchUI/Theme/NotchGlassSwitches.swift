import Foundation
import SwiftUI

/// Which `Glass` the notch and its bubbles ask for.
nonisolated enum NotchGlassVariant: String, CaseIterable, Sendable {
    /// Today's glass.
    case regular
    /// The system's clear glass: the wallpaper shows through almost unblurred.
    case clear

    var glass: Glass {
        switch self {
        case .regular: .regular
        case .clear: .clear
        }
    }
}

/// The colour scheme the notch's content is drawn in on glass.
nonisolated enum NotchGlassScheme: String, CaseIterable, Sendable {
    /// Whatever the window has (today).
    case system
    /// Dark, so the text tokens (the system's primary and secondary colours on glass) are white.
    case dark
}

/// What the open notch is made of.
nonisolated enum NotchGlassPanel: String, CaseIterable, Sendable {
    /// One piece of glass behind everything, as today.
    case slab
    /// No glass on the panel itself: the tab bar sits in one glass capsule, the module's content in one glass tile, and the strip's
    /// shapes straight on the desktop as glass of their own, with the desktop showing in the gaps between them (as Control Center's
    /// tiles sit on the wallpaper). Only while the notch is open: the collapsed notch, a toast and the bubbles are glass as before.
    case tiles
}

/// How the selected chip and the selected tab look on Liquid Glass.
nonisolated enum NotchGlassSelected: String, CaseIterable, Sendable {
    /// The accent: a chip on the desktop is glass tinted with it, a tab on glass is the accent wash with its rim (as today).
    case tint
    /// A solid white tile with a dark glyph, like an "on" tile of Control Center.
    case white
}

/// The debug switches of the glass look, one build to compare the open questions on screen (U3c). They are plain
/// `UserDefaults.standard` keys read once, when the notch is built, with no settings UI; every default is today's behaviour, and
/// a value that is missing, of another type or not one of the names falls back to it.
///
/// Every switch but `sample` does nothing unless the notch is Liquid Glass (`active` included), so a key left in the defaults
/// cannot change the classic notch. `sample` follows its key in either look: the strip on the classic black notch is a baseline to compare with.
///
///     debug.glass.variant   regular | clear
///     debug.glass.panel     slab | tiles
///     debug.glass.dim       0 ... 0.4
///     debug.glass.scheme    system | dark
///     debug.glass.sample    0 | 1
///     debug.glass.selected  tint | white
///     debug.glass.active    0 | 1
nonisolated struct NotchGlassSwitches: Equatable, Sendable {
    enum Key {
        static let variant = "debug.glass.variant"
        static let panel = "debug.glass.panel"
        static let dim = "debug.glass.dim"
        static let scheme = "debug.glass.scheme"
        static let sample = "debug.glass.sample"
        static let selected = "debug.glass.selected"
        static let active = "debug.glass.active"
        static let all = [variant, panel, dim, scheme, sample, selected, active]
    }

    /// The most the black layer can take: clear glass needs some dimming over bright content, but past this it is no longer glass.
    static let dimRange: ClosedRange<Double> = 0...0.4

    var variant = NotchGlassVariant.regular
    var panel = NotchGlassPanel.slab
    var dim = 0.0
    var scheme = NotchGlassScheme.system
    var sample = false
    var selected = NotchGlassSelected.tint
    /// Draw the notch panel's glass as an active window's, without making the panel key (`ActiveGlassAppearance`). A switch of the
    /// window, not of the plan: it only means anything on Liquid Glass, where the window controller applies it.
    var active = false

    /// Today's behaviour in every switch.
    static let `default` = NotchGlassSwitches()

    init(
        variant: NotchGlassVariant = .regular, panel: NotchGlassPanel = .slab, dim: Double = 0, scheme: NotchGlassScheme = .system,
        sample: Bool = false, selected: NotchGlassSelected = .tint, active: Bool = false
    ) {
        self.variant = variant
        self.panel = panel
        self.dim = Self.clamped(dim)
        self.scheme = scheme
        self.sample = sample
        self.selected = selected
        self.active = active
    }

    /// The switches `defaults` holds. A name is matched ignoring case and surrounding spaces; `dim` may be a number or a string
    /// (`defaults write` stores a bare `0.15` as a string, and `-float` as a number) and is held to `dimRange`; `sample` is 1,
    /// true or yes, as a number or a string. Anything else is today's behaviour.
    init(reading defaults: UserDefaults) {
        func name<Name: RawRepresentable>(_ key: String, as _: Name.Type) -> Name? where Name.RawValue == String {
            (defaults.object(forKey: key) as? String).flatMap { Name(rawValue: $0.trimmed) }
        }
        self.init(
            variant: name(Key.variant, as: NotchGlassVariant.self) ?? .regular,
            panel: name(Key.panel, as: NotchGlassPanel.self) ?? .slab,
            dim: Self.number(defaults.object(forKey: Key.dim)) ?? 0,
            scheme: name(Key.scheme, as: NotchGlassScheme.self) ?? .system,
            sample: Self.flag(defaults.object(forKey: Key.sample)),
            selected: name(Key.selected, as: NotchGlassSelected.self) ?? .tint,
            active: Self.flag(defaults.object(forKey: Key.active))
        )
    }

    private static func clamped(_ value: Double) -> Double {
        value.isFinite ? min(max(value, dimRange.lowerBound), dimRange.upperBound) : 0
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: number.doubleValue
        case let string as String: Double(string.trimmed)
        default: nil
        }
    }

    private static func flag(_ value: Any?) -> Bool {
        switch value {
        case let number as NSNumber: number.intValue == 1
        case let string as String: ["1", "true", "yes"].contains(string.trimmed)
        default: false
        }
    }
}

private nonisolated extension String {
    var trimmed: String { trimmingCharacters(in: .whitespaces).lowercased() }
}

extension EnvironmentValues {
    /// The debug switches of the glass look, which the notch's root view sets for everything in it. Today's behaviour outside it.
    @Entry var notchGlassSwitches: NotchGlassSwitches = .default
}
