import AppKit
import NotchUI
import SwiftUI

/// Cover art, else the playing app's icon, else a music note: players such as browsers often send no artwork.
struct ArtworkView: View {
    let artwork: NSImage?
    let icon: NSImage?
    let size: CGFloat
    let cornerRadius: CGFloat

    private var isLarge: Bool { size >= 40 }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    // A new identity per image, so a track change cross-fades instead of cutting.
                    .id(ObjectIdentifier(artwork))
                    .transition(.opacity)
            } else if let icon {
                // Icons have their own shape and margins: alone at activity size, on a tile in the tab.
                if isLarge { shape.fill(NotchTokens.fill(0.1)) }
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(isLarge ? size * 0.18 : 0)
            } else {
                shape.fill(NotchTokens.fill(0.1))
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(NotchTokens.secondaryText)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .animation(.easeInOut(duration: 0.25), value: artwork.map(ObjectIdentifier.init))
        .accessibilityHidden(true)
    }
}
