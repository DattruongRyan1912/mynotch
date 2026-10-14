import Foundation

extension Character {
    /// Only 0 to 9: `isNumber` also accepts "²" and the digits of other scripts.
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}

/// Numbers as a Vietnamese reader writes and expects them: "." between thousands and "," before the decimals.
/// Reading accepts both conventions, since selected text may use either.
enum VietnameseNumber {
    /// From this size up, results are shown as "1,5e15": plain digits stop being readable.
    private static let scientificFrom = 1e15

    /// The number that starts at `start` and the index just after it; nil when none starts there or its separators
    /// make no sense ("15.10.2024" is a date, not a number). A separator not followed by a digit ends the number.
    static func scan(_ characters: [Character], from start: Int) -> (value: Decimal, end: Int)? {
        guard start >= 0, start < characters.count, characters[start].isASCIIDigit else { return nil }
        var end = start
        while end < characters.count {
            let character = characters[end]
            let continues = character.isASCIIDigit
                || ((character == "." || character == ",") && end + 1 < characters.count && characters[end + 1].isASCIIDigit)
            guard continues else { break }
            end += 1
        }
        guard let value = interpret(String(characters[start..<end])) else { return nil }
        return (value, end)
    }

    /// A lone separator before exactly three digits (and not after a leading zero) is a thousands separator, because
    /// "100.000đ" and "1,000" are far more common than three decimals. Otherwise it is the decimal separator. With
    /// both kinds present, the last one is the decimal separator.
    private static func interpret(_ token: String) -> Decimal? {
        let separators = token.filter { $0 == "." || $0 == "," }
        let groups = token.split(omittingEmptySubsequences: false) { $0 == "." || $0 == "," }.map(String.init)
        let digits: String
        if separators.isEmpty {
            digits = token
        } else if Set(separators).count == 2 {
            let decimal = separators.last!
            guard separators.dropLast().allSatisfy({ $0 != decimal }), groupsOfThousands(groups.dropLast()) else { return nil }
            digits = groups.dropLast().joined() + "." + groups.last!
        } else if separators.count > 1 {
            guard groupsOfThousands(groups[...]) else { return nil }
            digits = groups.joined()
        } else if groups[1].count == 3, (1...3).contains(groups[0].count), groups[0] != "0" {
            digits = groups.joined()
        } else {
            digits = groups[0] + "." + groups[1]
        }
        return decimal(digits)
    }

    /// Plain digits and at most one point. Short numbers skip `Decimal(string:)`, which is slow and is asked about every
    /// number of a long text.
    private static func decimal(_ digits: String) -> Decimal? {
        let parts = digits.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let all = parts.joined()
        guard all.count <= 18, let significand = UInt64(all) else { return Decimal(string: digits, locale: posix) }
        return Decimal(sign: .plus, exponent: parts.count > 1 ? -parts[1].count : 0, significand: Decimal(significand))
    }

    private static let posix = Locale(identifier: "en_US_POSIX")

    /// One to three digits (no leading zero) and then groups of exactly three.
    private static func groupsOfThousands(_ groups: ArraySlice<String>) -> Bool {
        guard let first = groups.first, (1...3).contains(first.count), first.first != "0" else { return false }
        return groups.dropFirst().allSatisfy { $0.count == 3 }
    }

    /// A converted measure: whole numbers from 10 up, two decimals from 1 to 10 and two significant digits below 1, so
    /// "180,34 cm" is "180", "22,2 °C" is "22" and "0,907 kg" is "0,91". Zeros after the comma are dropped.
    static func quick(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        let magnitude = abs(value)
        let decimals: Int
        if magnitude >= 10 || magnitude == 0 {
            decimals = 0
        } else if magnitude >= 1 {
            decimals = 2
        } else {
            decimals = min(1 - Int(floor(log10(magnitude))), 9)
        }
        return fixed(value, decimals: decimals, dropsZeros: true)
    }

    /// Always `decimals` digits after the comma, as money is written.
    static func fixed(_ value: Double, decimals: Int) -> String {
        fixed(value, decimals: decimals, dropsZeros: false)
    }

    /// An exact result, rounded to ten decimals, without trailing zeros; "1,5e15" from a quadrillion up.
    static func format(_ value: Decimal) -> String {
        let double = NSDecimalNumber(decimal: value).doubleValue
        if abs(double) >= scientificFrom {
            let parts = String(format: "%.9g", double).split(separator: "e")
            let mantissa = parts[0].replacing(".", with: ",")
            let exponent = Int(parts.last ?? "0") ?? 0
            return "\(mantissa)e\(exponent)"
        }
        var rounded = Decimal()
        var original = value
        NSDecimalRound(&rounded, &original, 10, .plain)
        return assemble(rounded.description, dropsZeros: true)
    }

    private static func fixed(_ value: Double, decimals: Int, dropsZeros: Bool) -> String {
        // Halves round away from zero, where `%f` rounds them to even ("1.234,5" would lose its half).
        let scale = pow(10, Double(decimals))
        let rounded = (value * scale).rounded(.toNearestOrAwayFromZero) / scale
        return assemble(String(format: "%.\(decimals)f", rounded), dropsZeros: dropsZeros)
    }

    /// "-1234567.50" becomes "-1.234.567,5" (or "-1.234.567,50" when keeping the zeros).
    private static func assemble(_ plain: String, dropsZeros: Bool) -> String {
        var text = Substring(plain)
        let isNegative = text.first == "-"
        if isNegative { text = text.dropFirst() }
        let parts = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        var fraction = parts.count > 1 ? Substring(parts[1]) : ""
        if dropsZeros { while fraction.last == "0" { fraction = fraction.dropLast() } }
        var integer = ""
        for (offset, digit) in parts[0].reversed().enumerated() {
            if offset > 0, offset % 3 == 0 { integer.append(".") }
            integer.append(digit)
        }
        let isZero = parts[0].allSatisfy { $0 == "0" } && fraction.allSatisfy { $0 == "0" }
        return (isNegative && !isZero ? "-" : "") + String(integer.reversed()) + (fraction.isEmpty ? "" : "," + fraction)
    }
}
