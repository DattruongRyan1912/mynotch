import Foundation
import NotchUI

/// What the spectrum bars are drawn on, as far as their colour is concerned, and how light a colour has to be to be seen on it.
/// The notch's black was the only one once, and the cover's colours were lifted for it alone; the classic blur and Liquid Glass
/// are greys, so the bars' colours are adjusted once more, for the surface each bars view is on.
nonisolated enum SpectrumBackdrop: Equatable, CaseIterable, Sendable {
    /// The classic notch, black.
    case black
    /// The classic blur: a black veil over a blur of what is behind, which leaves a dark grey.
    case veil
    /// Liquid Glass, which is light or dark with what is behind it.
    case glass

    init(_ surface: NotchSurface) {
        switch surface {
        case .solid: self = .black
        case .material: self = .veil
        case .liquidGlass: self = .glass
        }
    }

    /// Dark glass, over a dark wallpaper or window.
    static let darkGlass = SRGBColor(hex: 0x3A3F46)
    /// Light glass, over a light one.
    static let lightGlass = SRGBColor(hex: 0xC9CDD2)
    /// The veil of the classic blur at its brightest in use: `NotchBackdrop.veilOpacity` (0.72) of black over a blur of mid grey
    /// (0.57), which leaves 0.28 × 0.57 of white.
    static let veilGrey = SRGBColor(red: 0.16, green: 0.16, blue: 0.16)

    /// What a colour is up against: the greys the surface can be.
    var references: [SRGBColor] {
        switch self {
        case .black: [SRGBColor(red: 0, green: 0, blue: 0)]
        case .veil: [Self.veilGrey]
        case .glass: [Self.darkGlass, Self.lightGlass]
        }
    }

    /// The contrast ratio the bars aim for: 4.5 to 1, the WCAG's ratio for text, on the two dark surfaces, and 3 to 1, its ratio for
    /// graphics, on glass.
    var target: Double {
        switch self {
        case .black, .veil: 4.5
        case .glass: 3
        }
    }

    /// The relative luminance a colour has to have to reach `target` against every reference.
    ///
    /// On black and on the veil that is a floor: anything lighter shows. On glass it has two sides, because the glass is light or dark:
    /// a colour has to be lighter than the dark glass's floor and darker than the light glass's ceiling. With the references and the
    /// target as they are the two do not meet (lighter than 0.247 to beat the dark glass at 3 to 1, darker than 0.169 to beat the
    /// light one), so no colour has 3 to 1 against both. Then the range is the single luminance that does equally well on both, the best
    /// the worse of the two can be (about 2.6 to 1), and the edge (`hasEdge`) does the rest.
    var luminanceRange: ClosedRange<Double> {
        let luminances = references.map(\.luminance)
        guard let darkest = luminances.min(), let lightest = luminances.max() else { return 0...1 }
        let needed = target * (darkest + 0.05) - 0.05
        guard lightest > darkest else { return needed...1 }
        let allowed = (lightest + 0.05) / target - 0.05
        if needed <= allowed { return needed...allowed }
        let best = ((darkest + 0.05) * (lightest + 0.05)).squareRoot() - 0.05
        return best...best
    }

    var minimumLuminance: Double { luminanceRange.lowerBound }
    var maximumLuminance: Double { luminanceRange.upperBound }

    /// Whether each bar gets a thin dark edge so it reads over a light or a busy backdrop. Glass only: on black and on the veil a
    /// bar already stands out, and an edge there would only blur it.
    var hasEdge: Bool { self == .glass }
}

extension SRGBColor {
    /// The colour as a bar draws it on `backdrop`: moved, with its hue kept, to the nearest luminance that shows there.
    func visible(on backdrop: SpectrumBackdrop) -> SRGBColor {
        keepingHue(inLuminance: backdrop.luminanceRange)
    }

    func visible(on surface: NotchSurface) -> SRGBColor {
        visible(on: SpectrumBackdrop(surface))
    }
}

extension SpectrumColorMode {
    /// Whether the bars adjust this mode's colours to show on their surface. White is what the user asked for and stays white, on
    /// glass too, where the edge is all it gets; the cover's colours and the user's gradient are adjusted, each colour by as little
    /// as it needs.
    var adjustsForSurface: Bool { self != .white }
}
