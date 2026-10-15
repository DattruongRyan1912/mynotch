import AppKit
import NotchUI
import SwiftUI

/// What to write on a button filled with the user's accent.
enum AccentLabel {
    /// White, as a label on the notch's purple always was, unless the accent is so light that white could hardly be read on it
    /// (yellow, the oranges and the greens), where black is used. Plain white, not the text token: the label is on a solid accent,
    /// which is as dark as the accent whatever the glass behind the notch is.
    static func colour(on accent: Color) -> Color {
        let rgb = NSColor(accent).usingColorSpace(.sRGB) ?? .black
        func linear(_ component: CGFloat) -> Double {
            let value = Double(component)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
        let whiteContrast = 1.05 / (luminance + 0.05)
        return whiteContrast < 2.5 ? Color.black.opacity(0.85) : Color.white
    }
}
