/// A calendar's colour as plain numbers (0...1, sRGB): `NSColor` is not `Sendable`, so it can't leave the EventKit actor.
nonisolated struct RGBAColor: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1

    /// Stands in for a calendar EventKit gives no usable colour for.
    static let gray = RGBAColor(red: 0.56, green: 0.56, blue: 0.58)
}
