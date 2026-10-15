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

/// What draws the notch's glass surface.
nonisolated enum NotchGlassHost: String, CaseIterable, Sendable {
    /// `glassEffect` on the notch's shape, in the family that morphs (today).
    case swiftui
    /// An `NSGlassEffectView` behind the SwiftUI content.
    case appkit
}

/// The colour scheme the notch's content is drawn in on glass.
nonisolated enum NotchGlassScheme: String, CaseIterable, Sendable {
    /// Whatever the window has (today).
    case system
    /// Dark, so the text tokens (the system's primary and secondary colours on glass) are white.
    case dark
}

/// How a card, a field, a chip and the selected tab are drawn.
nonisolated enum NotchGlassCards: String, CaseIterable, Sendable {
    /// A wash of the text colour (`NotchTokens.fill`), as today.
    case fill
    /// A glass shape of its own.
    case glass
}

/// How the selected chip and the selected tab look when they are glass.
nonisolated enum NotchGlassSelected: String, CaseIterable, Sendable {
    /// Glass tinted with the accent.
    case tint
    /// A solid white tile with a dark glyph, like an "on" tile of Control Center.
    case white
}

/// The debug switches of the glass look, one build to compare the open questions on screen (U3c). They are plain
/// `UserDefaults.standard` keys read once, when the notch is built, with no settings UI; every default is today's behaviour, and
/// a value that is missing, of another type or not one of the names falls back to it.
///
/// Every switch but `sample` does nothing unless the notch is Liquid Glass, so a key left in the defaults cannot change the
/// classic notch. `sample` follows its key in either look: the strip on the classic black notch is a baseline to compare with.
///
///     debug.glass.variant   regular | clear
///     debug.glass.host      swiftui | appkit
///     debug.glass.dim       0 ... 0.4
///     debug.glass.scheme    system | dark
///     debug.glass.sample    0 | 1
///     debug.glass.cards     fill | glass
///     debug.glass.selected  tint | white
nonisolated struct NotchGlassSwitches: Equatable, Sendable {
    enum Key {
        static let variant = "debug.glass.variant"
        static let host = "debug.glass.host"
        static let dim = "debug.glass.dim"
        static let scheme = "debug.glass.scheme"
        static let sample = "debug.glass.sample"
        static let cards = "debug.glass.cards"
        static let selected = "debug.glass.selected"
        static let all = [variant, host, dim, scheme, sample, cards, selected]
    }

    /// The most the black layer can take: clear glass needs some dimming over bright content, but past this it is no longer glass.
    static let dimRange: ClosedRange<Double> = 0...0.4

    var variant = NotchGlassVariant.regular
    var host = NotchGlassHost.swiftui
    var dim = 0.0
    var scheme = NotchGlassScheme.system
    var sample = false
    var cards = NotchGlassCards.fill
    var selected = NotchGlassSelected.tint

    /// Today's behaviour in every switch.
    static let `default` = NotchGlassSwitches()

    init(
        variant: NotchGlassVariant = .regular, host: NotchGlassHost = .swiftui, dim: Double = 0, scheme: NotchGlassScheme = .system,
        sample: Bool = false, cards: NotchGlassCards = .fill, selected: NotchGlassSelected = .tint
    ) {
        self.variant = variant
        self.host = host
        self.dim = Self.clamped(dim)
        self.scheme = scheme
        self.sample = sample
        self.cards = cards
        self.selected = selected
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
            host: name(Key.host, as: NotchGlassHost.self) ?? .swiftui,
            dim: Self.number(defaults.object(forKey: Key.dim)) ?? 0,
            scheme: name(Key.scheme, as: NotchGlassScheme.self) ?? .system,
            sample: Self.flag(defaults.object(forKey: Key.sample)),
            cards: name(Key.cards, as: NotchGlassCards.self) ?? .fill,
            selected: name(Key.selected, as: NotchGlassSelected.self) ?? .tint
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
