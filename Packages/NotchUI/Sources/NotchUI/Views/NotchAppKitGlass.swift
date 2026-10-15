import AppKit
import SwiftUI

/// An `NSGlassEffectView` that lets every click through to the SwiftUI notch above it.
final class NotchGlassEffectView: NSGlassEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The notch's glass drawn by AppKit's own glass view instead of `glassEffect`: the debug host `appkit`, to see whether the
/// view draws brighter rims than SwiftUI's in this panel, which never becomes the active app.
struct NotchAppKitGlass: NSViewRepresentable {
    let surface: NotchGlassPlan.AppKitSurface
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NotchGlassEffectView {
        let view = NotchGlassEffectView()
        // Only the content view is guaranteed a place inside the glass; an empty one keeps the view a plain piece of glass.
        view.contentView = NSView()
        return view
    }

    func updateNSView(_ view: NotchGlassEffectView, context: Context) {
        view.style = surface.variant == .clear ? .clear : .regular
        view.tintColor = surface.tint.map { NSColor($0) }
        view.cornerRadius = cornerRadius
    }
}

extension View {
    /// Draws the AppKit-hosted glass `surface` behind the view, as big as the view, which is the notch's shape once it has its
    /// size, so it follows the same spring as the notch and so grows about its centre like the SwiftUI glass does; the view itself
    /// when there is none. A uniform corner radius cannot make the notch's concave ears, so the glass is inset by the ears' radius
    /// at each side and runs up past the top of the panel by the bottom radius: what shows is the body of the notch, flat at
    /// the top, with its two bottom corners rounded as the notch's are. The ears have no glass. It is not clipped to the notch's
    /// shape (a mask on a glass view may stop it drawing); the content on top is.
    @ViewBuilder func notchAppKitGlass(_ surface: NotchGlassPlan.AppKitSurface?, topRadius: CGFloat, bottomRadius: CGFloat) -> some View {
        if let surface {
            background {
                NotchAppKitGlass(surface: surface, cornerRadius: bottomRadius)
                    .padding(.horizontal, topRadius)
                    .padding(.top, -bottomRadius)
                    .allowsHitTesting(false)
            }
        } else {
            self
        }
    }
}
