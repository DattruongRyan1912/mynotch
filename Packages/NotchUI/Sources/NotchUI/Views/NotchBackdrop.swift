import SwiftUI

/// What the notch's shape is filled with. Black, which is also what the hardware notch is, so the two join. As the classic look's
/// blur (the open notch only, when the user asks) it is a blur of what is behind the window under a veil of black, except the
/// strip the notch's own body takes at the top, which stays solid so there is no seam where it meets the cutout. As Liquid
/// Glass it is nothing: `View.notchGlass` draws the glass behind the whole notch once the shape has its size.
struct NotchBackdrop: View {
    let surface: NotchSurface
    let bodyHeight: CGFloat

    /// How much of the blur shows through the veil: little, so the notch still reads as black.
    static let veilOpacity = 0.72

    var body: some View {
        ZStack(alignment: .top) {
            switch surface {
            case .liquidGlass:
                // Nothing: the glass is drawn behind the whole notch by `View.notchGlass`, and it is the system's alone. A
                // black scrim over it, and a dark scheme, made it read as dark frosted glass rather than as Liquid Glass.
                Color.clear
            case .material:
                Rectangle().fill(.ultraThinMaterial)
                NotchTokens.background.opacity(Self.veilOpacity)
                NotchTokens.background.frame(height: bodyHeight)
            case .solid:
                NotchTokens.background
            }
        }
        // A black notch is a dark surface, so the material is the dark one whatever the app's appearance is.
        .environment(\.colorScheme, .dark)
    }
}
