import Foundation

/// The CSS color functions rgb(), rgba(), hsl() and hsla(), in the comma syntax ("rgb(255, 136, 0, 0.5)") and the space
/// syntax ("rgb(255 136 0 / 50%)"). Pure, so every rule is testable without a pasteboard.
nonisolated enum ClipboardCSSColor {
    /// Anything longer is not tried: the longest sensible color is about 60 characters, and a copied document is not one.
    private static let maxLength = 100

    /// "#RRGGBB", or "#RRGGBBAA" when the alpha is below 1, for a trimmed text that is exactly one color function; nil
    /// for anything else. Out-of-range numbers are clamped like CSS does (`rgb(300, 0, 0)` is red); what CSS would
    /// accept but is rarely copied is left as text: exponents (`1e2`) and `none`.
    static func hex(_ text: String) -> String? {
        guard text.utf8.count <= maxLength, text.hasSuffix(")"), let open = text.firstIndex(of: "(") else { return nil }
        let isHSL: Bool
        switch text[..<open].lowercased() {
        case "rgb", "rgba": isHSL = false
        case "hsl", "hsla": isHSL = true
        default: return nil
        }
        guard let arguments = arguments(of: text[text.index(after: open)..<text.index(before: text.endIndex)]) else { return nil }
        let channels: (Double, Double, Double)?
        if isHSL {
            channels = hsl(arguments.values, isLegacy: arguments.isLegacy)
        } else {
            channels = rgb(arguments.values, isLegacy: arguments.isLegacy)
        }
        guard let channels else { return nil }
        var alpha = 1.0
        if let text = arguments.alpha {
            guard let value = fraction(text) else { return nil }
            alpha = value
        }
        let bytes = [channels.0, channels.1, channels.2, alpha].map { UInt8(($0 * 255).rounded()) }
        // Alpha 1 is the plain "#RRGGBB" a hex color is stored as.
        return "#" + (bytes[3] == 255 ? bytes[..<3] : bytes[...]).map { String(format: "%02X", $0) }.joined()
    }

    // MARK: Arguments

    /// The three channel values and the alpha, as written. The comma syntax puts alpha fourth, the space syntax after a "/".
    private static func arguments(of body: Substring) -> (values: [String], alpha: String?, isLegacy: Bool)? {
        func trimmed(_ part: Substring) -> String { part.trimmingCharacters(in: .whitespacesAndNewlines) }
        if body.contains(",") {
            guard !body.contains("/") else { return nil }
            let parts = body.split(separator: ",", omittingEmptySubsequences: false).map(trimmed)
            guard parts.count == 3 || parts.count == 4 else { return nil }
            return (Array(parts[..<3]), parts.count == 4 ? parts[3] : nil, true)
        }
        let halves = body.split(separator: "/", omittingEmptySubsequences: false)
        guard let first = halves.first, halves.count <= 2 else { return nil }
        let values = first.split(whereSeparator: \.isWhitespace).map(String.init)
        guard values.count == 3 else { return nil }
        return (values, halves.count == 2 ? trimmed(halves[1]) : nil, false)
    }

    // MARK: Channels

    /// The comma syntax takes numbers or percentages for all three channels; the space syntax may mix them.
    private static func rgb(_ values: [String], isLegacy: Bool) -> (Double, Double, Double)? {
        let parsed = values.compactMap(percentOrNumber)
        guard parsed.count == 3, !isLegacy || Set(parsed.map { $0.isPercent }).count == 1 else { return nil }
        let channels = parsed.map { $0.isPercent ? clamp($0.value / 100) : clamp($0.value / 255) }
        return (channels[0], channels[1], channels[2])
    }

    /// Hue wraps around; saturation and lightness are percentages, or plain numbers in the space syntax.
    private static func hsl(_ values: [String], isLegacy: Bool) -> (Double, Double, Double)? {
        guard let hue = hue(values[0]), let saturation = percentOrNumber(values[1]), let lightness = percentOrNumber(values[2]),
              !isLegacy || (saturation.isPercent && lightness.isPercent) else { return nil }
        let s = clamp(saturation.value / 100), l = clamp(lightness.value / 100)
        let degrees = hue.truncatingRemainder(dividingBy: 360) + (hue < 0 ? 360 : 0)
        // CSS Color 4: each channel is the lightness, moved by up to the chroma along a trapezoid of the hue.
        func channel(_ offset: Double) -> Double {
            let k = (offset + degrees / 30).truncatingRemainder(dividingBy: 12)
            return l - s * min(l, 1 - l) * max(-1, min(k - 3, 9 - k, 1))
        }
        return (channel(0), channel(8), channel(4))
    }

    /// An alpha: 0…1 or a percentage, clamped.
    private static func fraction(_ text: String) -> Double? {
        percentOrNumber(text).map { clamp($0.isPercent ? $0.value / 100 : $0.value) }
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    // MARK: Numbers

    private static func percentOrNumber(_ text: String) -> (value: Double, isPercent: Bool)? {
        if text.hasSuffix("%") { return number(text.dropLast()).map { ($0, true) } }
        return number(text[...]).map { ($0, false) }
    }

    /// A hue in degrees: a number, optionally followed by an angle unit. "grad" is checked before "rad", which it ends with.
    private static func hue(_ text: String) -> Double? {
        let lowercased = text.lowercased()
        for (unit, degrees) in [("deg", 1.0), ("grad", 0.9), ("rad", 180 / Double.pi), ("turn", 360.0)] where lowercased.hasSuffix(unit) {
            return number(lowercased.dropLast(unit.count)).map { $0 * degrees }
        }
        return number(lowercased[...])
    }

    /// Optional sign, ASCII digits and at most one dot, with at least one digit. `Double(_:)` alone would also take "inf",
    /// "nan", "0x10" and exponents. Beyond the range of a Double it is not a number either.
    private static func number(_ text: Substring) -> Double? {
        let digits = text.first == "+" || text.first == "-" ? text.dropFirst() : text
        guard digits.contains(where: \.isASCIIDigit), digits.filter({ $0 == "." }).count <= 1,
              digits.allSatisfy({ $0.isASCIIDigit || $0 == "." }), let value = Double(text), value.isFinite else { return nil }
        return value
    }
}

private nonisolated extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
