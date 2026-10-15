import NotchUI
import SwiftUI

/// The root of a window the module owns (the library, the floating panel), which sits outside the notch's view tree and so does
/// not inherit its environment: puts in the accent the notch is drawn with, as the environment value and as the tint, the way
/// the notch's own root does. It reads `interface.accent` in its body, so the window follows a change of the accent while it is
/// open. Views that draw with the accent read `@Environment(\.notchAccent)`, in the notch and in these windows alike.
struct ClipboardAccentHost<Content: View>: View {
    let interface: NotchInterface
    let content: Content

    init(interface: NotchInterface = .shared, @ViewBuilder content: () -> Content) {
        self.interface = interface
        self.content = content()
    }

    var body: some View {
        let accent = interface.accent
        content
            .environment(\.notchAccent, accent)
            .tint(accent)
    }
}
