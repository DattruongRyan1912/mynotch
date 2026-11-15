import Foundation
import NotchUI

/// What the spectrum bars are drawn on, as far as their colour is concerned, and how light a colour has to be to be seen on it.
/// The notch's black was the only one once, and the cover's colours were lifted for it alone; the classic blur and Liquid Glass
/// are greys, so the bars' colours are lifted once more, for the surface each bars view is on. They are only ever lifted: a colour
/// that already shows is the cover's or the user's own, and nothing is made darker for a light backdrop.
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

    /// Dark glass, over a dark wallpaper or window: the darkest grey that glass is, and so the one a bar's colour has to be light
    /// enough for. Over light glass a colour that is light enough for this one shows less, and the edge (`hasEdge`) carries it there.
    static let darkGlass = SRGBColor(hex: 0x3A3F46)
    /// The veil of the classic blur at its brightest in use: `NotchBackdrop.veilOpacity` (0.72) of black over a blur of mid grey
    /// (0.57), which leaves 0.28 × 0.57 of white.
    static let veilGrey = SRGBColor(red: 0.16, green: 0.16, blue: 0.16)

    /// The grey a bar's colour has to stand out from.
    var reference: SRGBColor {
        switch self {
        case .black: SRGBColor(red: 0, green: 0, blue: 0)
        case .veil: Self.veilGrey
        case .glass: Self.darkGlass
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

    /// The least relative luminance a colour needs to reach `target` against `reference`.
    var minimumLuminance: Double { target * (reference.luminance + 0.05) - 0.05 }

    /// Whether each bar gets a thin dark edge so it reads over a light or a busy backdrop. Glass only: on black and on the veil a
    /// bar already stands out, and an edge there would only blur it.
    var hasEdge: Bool { self == .glass }
}

extension SRGBColor {
    /// The colour as a bar draws it on `backdrop`: lifted, with its hue kept, to the least that shows there.
    func visible(on backdrop: SpectrumBackdrop) -> SRGBColor {
        liftedKeepingHue(toLuminance: backdrop.minimumLuminance)
    }

    func visible(on surface: NotchSurface) -> SRGBColor {
        visible(on: SpectrumBackdrop(surface))
    }
}
