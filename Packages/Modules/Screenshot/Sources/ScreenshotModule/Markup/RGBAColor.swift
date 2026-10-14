import CoreGraphics

/// An sRGB colour with components in 0…1, stored in the markup JSON.
nonisolated struct RGBAColor: Codable, Equatable, Sendable {
    var r: CGFloat
    var g: CGFloat
    var b: CGFloat
    var a: CGFloat = 1

    static let red = RGBAColor(r: 1, g: 0.23, b: 0.19)
    static let yellow = RGBAColor(r: 1, g: 0.8, b: 0)
    static let green = RGBAColor(r: 0.2, g: 0.78, b: 0.35)
    static let blue = RGBAColor(r: 0, g: 0.48, b: 1)
    static let black = RGBAColor(r: 0, g: 0, b: 0)

    /// The editor's colour choices, in toolbar order.
    static let presets: [(name: String, color: RGBAColor)] = [
        ("Đỏ", .red), ("Vàng", .yellow), ("Xanh lá", .green), ("Xanh dương", .blue), ("Đen", .black),
    ]

    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }

    /// Whether black reads better than white on top of this colour, by its perceived brightness.
    var prefersDarkText: Bool { 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.5 }
}
