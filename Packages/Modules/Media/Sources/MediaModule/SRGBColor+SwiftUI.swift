import AppKit
import SwiftUI

extension SRGBColor {
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }

    /// The colour a picker gave, converted to sRGB; what sRGB cannot show is clamped into it.
    init(_ color: Color) {
        let converted = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(red: converted.redComponent, green: converted.greenComponent, blue: converted.blueComponent)
    }
}
