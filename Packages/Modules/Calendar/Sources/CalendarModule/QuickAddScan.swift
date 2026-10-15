import Foundation

/// The line being read: what the user typed, a lower-case copy without accents that the patterns run on, and which
/// letters have been used up. Typing "chiều" or "chieu" must read the same, so words are found in the copy. Both texts
/// have the same length in UTF-16 units, so one range fits both and the title can be cut out of what was typed.
nonisolated struct QuickAddScan {
    enum Use: Equatable {
        case free
        /// A date, a time or a word that belongs to one: it leaves the title.
        case used
        /// A length. It only leaves the title when there is a start for it to belong to.
        case length
    }

    /// Stands where a used letter was, so a pattern never reads across it and `\s` never matches it.
    static let used: UInt16 = 0xE000

    private let original: [UInt16]
    /// The accent-free copy as it was made; `folded` is the same with the used letters blanked out.
    private let base: [UInt16]
    private var folded: [UInt16]
    private var uses: [Use]
    /// `folded` as a string, kept in step with it: the patterns run on this, many times over.
    private(set) var text: String

    init(_ text: String) {
        let typed = text.precomposedStringWithCanonicalMapping
        original = Array(typed.utf16)
        var folded: [UInt16] = []
        folded.reserveCapacity(original.count)
        for character in typed {
            let units = Array(String(character).utf16)
            let simple = Array(Self.fold(character).utf16)
            // A letter that folds to something of another length keeps its own units, so the two texts stay aligned.
            folded += simple.count == units.count ? simple : units
        }
        base = folded
        self.folded = folded
        self.text = String(decoding: folded, as: UTF16.self)
        uses = Array(repeating: .free, count: folded.count)
    }

    private static func fold(_ character: Character) -> String {
        if character.isASCII { return character.lowercased() }
        if character == "đ" || character == "Đ" { return "d" }
        return String(character).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    var count: Int { folded.count }
    var fullRange: NSRange { NSRange(location: 0, length: folded.count) }

    /// Nothing but spaces.
    var isBlank: Bool {
        String(decoding: original, as: UTF16.self).allSatisfy(\.isWhitespace)
    }

    // MARK: Looking

    func matches(_ regex: NSRegularExpression) -> [NSTextCheckingResult] {
        regex.matches(in: text, range: fullRange)
    }

    /// A match that starts exactly at `location`.
    func match(_ regex: NSRegularExpression, at location: Int) -> NSTextCheckingResult? {
        guard location < folded.count else { return nil }
        return regex.firstMatch(
            in: text, options: .anchored, range: NSRange(location: location, length: folded.count - location)
        )
    }

    /// What the pattern read for one of its named groups, in the accent-free copy; nil if the group took no part.
    func group(_ name: String, of result: NSTextCheckingResult) -> String? {
        range(of: name, in: result).map(string(in:))
    }

    func string(in range: NSRange) -> String {
        String(decoding: folded[range.location ..< range.location + range.length], as: UTF16.self)
    }

    /// The text as typed (accents and capitals kept), for the few words that depend on them.
    func typed(in range: NSRange) -> String {
        String(decoding: original[range.location ..< range.location + range.length], as: UTF16.self)
    }

    /// Where one of the pattern's named groups matched; nil if the group took no part.
    func range(of name: String, in result: NSTextCheckingResult) -> NSRange? {
        let range = result.range(withName: name)
        return range.location == NSNotFound ? nil : range
    }

    /// Whether a letter or digit stands right before `location`: a number there belongs to a longer word or number.
    func isInsideWord(at location: Int) -> Bool {
        guard location > 0 else { return false }
        let before = folded[location - 1]
        guard let scalar = Unicode.Scalar(before) else { return false }
        return ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) || ":/.".unicodeScalars.contains(scalar)
    }

    /// The word, as a pattern, that ends right before `location` (spaces between ignored): `(?<![a-z0-9])(?:words)\s*$`.
    func lastWord(before location: Int, in regex: NSRegularExpression) -> NSTextCheckingResult? {
        let head = String(decoding: folded[0 ..< location], as: UTF16.self)
        return regex.firstMatch(in: head, range: NSRange(location: 0, length: location))
    }

    // MARK: Using

    mutating func take(_ range: NSRange, as use: Use = .used) {
        for index in range.location ..< range.location + range.length {
            folded[index] = Self.used
            uses[index] = use
        }
        text = String(decoding: folded, as: UTF16.self)
    }

    /// Gives the lengths back to the title: they were only taken out of the way of the times.
    mutating func releaseLengths() {
        for index in uses.indices where uses[index] == .length {
            folded[index] = base[index]
            uses[index] = .free
        }
        text = String(decoding: folded, as: UTF16.self)
    }

    /// Takes the little words that introduce what was just read ("lúc 9h", "on friday") along with it. Looks at every
    /// run of used letters and takes a connector standing right before it.
    mutating func takeConnectors(_ connectors: NSRegularExpression) {
        var index = 0
        while index < uses.count {
            guard uses[index] == .used else { index += 1; continue }
            if let found = lastWord(before: index, in: connectors), let word = range(of: "word", in: found) {
                take(word)
            }
            // Skip to the end of this run, spaces inside it included.
            while index < uses.count, uses[index] == .used || folded[index] == 0x20 { index += 1 }
        }
    }

    // MARK: The title

    /// What is left of the typed text: single spaces, no stray punctuation at the ends.
    var title: String {
        var kept: [UInt16] = []
        for index in original.indices where uses[index] == .free { kept.append(original[index]) }
        let words = String(decoding: kept, as: UTF16.self).split(whereSeparator: \.isWhitespace)
        return words.joined(separator: " ").trimmingCharacters(in: Self.edgePunctuation)
    }

    private static let edgePunctuation = CharacterSet(charactersIn: ",;:-–—@ ")
}
