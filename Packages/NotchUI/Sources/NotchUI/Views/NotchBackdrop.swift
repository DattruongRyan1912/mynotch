import SwiftUI

/// What the notch's shape is filled with. Black, which is also what the hardware notch is, so the two join. As glass (the
/// open notch only, when the user asks) it is a blur of what is behind the window under a veil of black, except the strip
/// the notch's own body takes at the top, which stays solid so there is no seam where it meets the cutout.
struct NotchBackdrop: View {
    let glass: Bool
    let bodyHeight: CGFloat

    /// How much of the blur shows through the veil: little, so the notch still reads as black.
    static let veilOpacity = 0.72

    var body: some View {
        ZStack(alignment: .top) {
            if glass {
                Rectangle().fill(.ultraThinMaterial)
                NotchTokens.background.opacity(Self.veilOpacity)
                NotchTokens.background.frame(height: bodyHeight)
            } else {
                NotchTokens.background
            }
        }
        // A black notch is a dark surface, so the material is the dark one whatever the app's appearance is.
        .environment(\.colorScheme, .dark)
    }
}
