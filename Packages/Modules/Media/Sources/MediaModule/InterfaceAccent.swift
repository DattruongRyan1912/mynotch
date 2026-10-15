import NotchUI
import SwiftUI

extension View {
    /// For the root of a window of its own (the lyrics panel), which sits outside the notch's view tree and so does not
    /// inherit its environment: the accent the notch is drawn with, as the environment value and as the tint, the way the
    /// notch's root gives them. Read in a body, so the view redraws when the accent changes.
    func followingAccent(of interface: NotchInterface) -> some View {
        let accent = interface.accent
        return environment(\.notchAccent, accent).tint(accent)
    }
}
