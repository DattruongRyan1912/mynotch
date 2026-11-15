import SwiftUI

/// A faint glow of the cover's colours behind the open player: the first colour round the cover, the second on the other side.
/// Drawn once and never animated except by a track change; it is the tab's background, so it adds nothing to the tab's size.
struct ArtworkGlow: View {
    struct Spot: Equatable {
        var color: SRGBColor
        var opacity: Double
        /// Where the light is brightest, as a part of the tab.
        var center: UnitPoint
        /// How far it reaches, as a part of the tab's width and height: it is gone at the tab's edge, so the glow has no hard edge.
        var reach: CGFloat
    }

    /// Faint enough that white text over the strongest part still has a contrast over 7 to 1.
    static let primaryOpacity = 0.30
    static let secondaryOpacity = 0.20

    let tint: ArtworkPalette?

    static func spots(for tint: ArtworkPalette?) -> [Spot] {
        guard let tint else { return [] }
        var spots = [Spot(color: tint.primary, opacity: primaryOpacity, center: UnitPoint(x: 0.2, y: 0.5), reach: 0.5)]
        if let secondary = tint.secondary {
            spots.append(Spot(color: secondary, opacity: secondaryOpacity, center: UnitPoint(x: 0.85, y: 0.5), reach: 0.4))
        }
        return spots
    }

    var body: some View {
        ZStack {
            ForEach(Array(Self.spots(for: tint).enumerated()), id: \.offset) { _, spot in
                EllipticalGradient(
                    colors: [spot.color.color.opacity(spot.opacity), spot.color.color.opacity(0)],
                    center: spot.center, startRadiusFraction: 0, endRadiusFraction: spot.reach
                )
            }
        }
        .animation(.easeInOut(duration: 0.5), value: tint)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
