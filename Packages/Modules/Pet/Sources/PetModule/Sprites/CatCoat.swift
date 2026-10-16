import Foundation

/// The colour of the cat's coat. The art is drawn once, in letters, and a coat only says what each letter is.
nonisolated enum CatCoat: String, CaseIterable, Codable, Sendable {
    /// Marmalade, striped: the cat the module began with.
    case tabby
    /// Black with a white chest, paws and muzzle, which needs its light rim most.
    case tuxedo
    case grey

    var displayName: String {
        switch self {
        case .tabby: "Mèo vàng"
        case .tuxedo: "Mèo đen trắng"
        case .grey: "Mèo xám"
        }
    }

    /// Every colour one coat is drawn with.
    var palette: PixelPalette {
        var colors: [Character: UInt32] = [
            "R": 0xFFF4DC,  // the light rim all round the cat
            "P": 0xF590B0,  // nose, ears, tongue, cheeks
            "L": 0xFFFFFF,  // the shine in an eye
            "V": 0xEEF2F7,  // whiskers
            "Z": 0x2563EB,  // sleep
            "H": 0xE11D48,  // hearts
            "B": 0xDC2626,  // the bang of a startled cat
            "N": 0xB45309,  // notes
            "S": 0x0369A1,  // a sweat drop
            "M": 0xE7DEFF,  // a moth's wings
            "A": 0x5A4636,  // and its body
            "Y": 0xE8505B,  // a ball of yarn
            "U": 0xA8283A,  // and its windings
        ]
        switch self {
        case .tabby:
            colors["K"] = 0x4A2A17
            colors["O"] = 0xF0A14E
            colors["D"] = 0xC4702A
            colors["W"] = 0xFDECD2
            colors["E"] = 0x1C130E
        case .tuxedo:
            colors["K"] = 0x0B0B10
            colors["O"] = 0x30303A
            colors["D"] = 0x4A4A57
            colors["W"] = 0xFAFAFA
            colors["E"] = 0xE9D84A
        case .grey:
            colors["K"] = 0x2D3440
            colors["O"] = 0x98A2B0
            colors["D"] = 0x6F7A8B
            colors["W"] = 0xEEF1F6
            colors["E"] = 0x1B2530
        }
        return PixelPalette(colors: colors)
    }
}
