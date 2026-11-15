import SwiftUI

/// A list's colour as plain numbers (0...1, sRGB): `NSColor` is not `Sendable`, so it can't leave the EventKit actor.
nonisolated struct TodoColor: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1

    /// Stands in for a list EventKit gives no usable colour for.
    static let gray = TodoColor(red: 0.56, green: 0.56, blue: 0.58)
}

extension Color {
    init(_ color: TodoColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
    }
}
