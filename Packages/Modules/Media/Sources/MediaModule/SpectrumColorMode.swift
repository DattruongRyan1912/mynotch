import Foundation

/// Where the spectrum bars take their colour from. The raw values are what the settings keep, so they never change.
nonisolated enum SpectrumColorMode: String, CaseIterable, Codable, Sendable {
    /// The colours of the album cover (the artwork tint); the bars keep their own colour while there is none.
    case artwork
    case white
    /// The two colours the user picked.
    case gradient

    /// The name in Settings.
    var title: String {
        switch self {
        case .artwork: "Theo ảnh bìa"
        case .white: "Trắng"
        case .gradient: "Gradient"
        }
    }

    /// The first picker's colour and the second's when the user has not chosen: the notch's accent and a cyan, which differ
    /// enough to be a gradient on black.
    static let defaultStart = SRGBColor(red: 0.49, green: 0.36, blue: 1.0)
    static let defaultEnd = SRGBColor(red: 0.25, green: 0.85, blue: 0.95)

    /// The colour of each of `count` bars, left to right; nil when the bars should keep their own colour (the cover's mode
    /// while there is no tint, which is also how the bars always looked).
    func colors(count: Int, tint: ArtworkPalette?, start: SRGBColor, end: SRGBColor) -> [SRGBColor]? {
        switch self {
        case .artwork:
            guard let tint else { return nil }
            return Self.ramp(from: tint.primary, to: tint.secondary ?? tint.primary, count: count)
        case .white:
            return Array(repeating: SRGBColor(red: 1, green: 1, blue: 1), count: max(count, 0))
        case .gradient:
            return Self.ramp(from: start, to: end, count: count)
        }
    }

    /// `count` colours in even steps from `first` to `last`, both included.
    private static func ramp(from first: SRGBColor, to last: SRGBColor, count: Int) -> [SRGBColor] {
        guard count > 1 else { return count == 1 ? [first] : [] }
        return (0..<count).map { first.mixed(with: last, amount: Double($0) / Double(count - 1)) }
    }
}
