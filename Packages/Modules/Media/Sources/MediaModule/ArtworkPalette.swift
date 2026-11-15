import Foundation

/// The one or two colours an album cover is mostly made of, already fit to be drawn on the notch's black.
nonisolated struct ArtworkPalette: Equatable, Sendable {
    var primary: SRGBColor
    /// A second, different colour; nil when the cover has only one (or its others are too small a part of it).
    var secondary: SRGBColor?
}
