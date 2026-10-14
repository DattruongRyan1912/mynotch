import Foundation

/// A time of day, with the zone it was written in (nil when it had none, which means the user's own).
struct TimeQuery: Equatable {
    var hour: Int
    var minute: Int
    var zone: TimeZone?
}

/// Reads a whole text as a time of day and optionally a zone: "3pm PST", "15:00 UTC+9", "9h sáng giờ Tokyo", "9:30 AM",
/// "21h30", "8 giờ tối giờ Hà Nội". Hours are 24-hour unless "am"/"pm" or a Vietnamese part of the day follows.
enum TimeQueryParser {
    private enum DayPart: String, CaseIterable {
        case morning = "sang", noon = "trua", afternoon = "chieu", evening = "toi", night = "dem", lateNight = "khuya"

        /// "1 trưa" is 13:00, "8 tối" is 20:00, "12 đêm" is midnight; nil for combinations nobody says ("2 sáng giờ chiều").
        func hour24(_ hour: Int) -> Int? {
            if hour > 12 { return hour }
            switch self {
            case .morning: return (1...11).contains(hour) ? hour : nil
            case .noon: return (10...12).contains(hour) ? hour : (1...3).contains(hour) ? hour + 12 : nil
            case .afternoon: return hour == 12 ? 12 : (1...7).contains(hour) ? hour + 12 : nil
            case .evening: return (5...11).contains(hour) ? hour + 12 : nil
            case .night, .lateNight:
                if hour == 12 { return 0 }
                return (1...5).contains(hour) ? hour : (8...11).contains(hour) ? hour + 12 : nil
            }
        }
    }

    /// With `requiresZone`, a time without a zone is refused: "7 am" inside a sentence is no reason to convert anything.
    static func parse(_ text: String, requiresZone: Bool = false) -> TimeQuery? {
        // Every form has a colon or a word ("h", "giờ", "pm"); the scan of running text asks this about every number.
        guard text.contains(where: { $0.isLetter || $0 == ":" }) else { return nil }
        let characters = Array(text.folded.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let (hour, afterHour) = readInt(characters, from: 0, maxDigits: 2) else { return nil }
        var index = afterHour
        var minute = 0
        var hour24: Int?

        if index < characters.count, characters[index] == ":" {
            // 9:30, 21:05, 9:30 am
            guard let (minutes, afterMinutes) = readInt(characters, from: index + 1, exactDigits: 2) else { return nil }
            minute = minutes
            index = afterMinutes
            if index < characters.count, characters[index] == ":" {
                guard let (_, afterSeconds) = readInt(characters, from: index + 1, exactDigits: 2) else { return nil }
                index = afterSeconds
            }
            if let (afterMeridiem, isPM) = meridiem(characters, from: skippingSpaces(characters, from: index)) {
                guard (1...12).contains(hour) else { return nil }
                hour24 = hour % 12 + (isPM ? 12 : 0)
                index = afterMeridiem
            } else {
                hour24 = hour
            }
        } else if index < characters.count, characters[index] == "h", isBoundary(characters, at: index + 1, allowingDigit: true) {
            // 9h, 9h30, 9h sáng
            index += 1
            if let (minutes, afterMinutes) = readInt(characters, from: index, maxDigits: 2) {
                minute = minutes
                index = afterMinutes
            }
            hour24 = try? dayPartHour(characters, hour: hour, index: &index)
        } else if let afterWord = word("gio", in: characters, from: skippingSpaces(characters, from: index)) {
            // 9 giờ, 9 giờ 30, 9 giờ 30 phút, 9 giờ tối
            index = skippingSpaces(characters, from: afterWord)
            if let (minutes, afterMinutes) = readInt(characters, from: index, maxDigits: 2) {
                minute = minutes
                index = skippingSpaces(characters, from: afterMinutes)
                index = word("phut", in: characters, from: index) ?? word("p", in: characters, from: index) ?? index
            }
            hour24 = try? dayPartHour(characters, hour: hour, index: &index)
        } else if let (afterMeridiem, isPM) = meridiem(characters, from: skippingSpaces(characters, from: index)) {
            // 3pm, 3 PM
            guard (1...12).contains(hour) else { return nil }
            hour24 = hour % 12 + (isPM ? 12 : 0)
            index = afterMeridiem
        } else {
            return nil
        }
        guard let hour24, (0...23).contains(hour24), (0...59).contains(minute) else { return nil }

        let rest = String(characters[min(index, characters.count)...])
        if rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return requiresZone ? nil : TimeQuery(hour: hour24, minute: minute, zone: nil)
        }
        guard let zone = TimeZoneCatalog.zone(named: rest) else { return nil }
        return TimeQuery(hour: hour24, minute: minute, zone: zone)
    }

    /// The hour once the optional part of the day after "9h" or "9 giờ" is applied; `index` moves past it.
    private static func dayPartHour(_ characters: [Character], hour: Int, index: inout Int) throws -> Int {
        let start = skippingSpaces(characters, from: index)
        for part in DayPart.allCases {
            guard let end = word(part.rawValue, in: characters, from: start) else { continue }
            guard let adjusted = part.hour24(hour) else { throw ParseFailure.invalid }
            index = end
            return adjusted
        }
        return hour
    }

    private enum ParseFailure: Error { case invalid }

    private static func readInt(_ characters: [Character], from start: Int, maxDigits: Int) -> (Int, Int)? {
        var end = start
        while end < characters.count, end - start < maxDigits, characters[end].isASCIIDigit { end += 1 }
        guard end > start, !(end < characters.count && characters[end].isASCIIDigit) else { return nil }
        return (Int(String(characters[start..<end]))!, end)
    }

    private static func readInt(_ characters: [Character], from start: Int, exactDigits: Int) -> (Int, Int)? {
        guard let (value, end) = readInt(characters, from: start, maxDigits: exactDigits), end - start == exactDigits else { return nil }
        return (value, end)
    }

    private static func skippingSpaces(_ characters: [Character], from start: Int) -> Int {
        var index = start
        while index < characters.count, characters[index].isWhitespace { index += 1 }
        return index
    }

    private static func isBoundary(_ characters: [Character], at index: Int, allowingDigit: Bool = false) -> Bool {
        guard index < characters.count else { return true }
        return !characters[index].isLetter && (allowingDigit || !characters[index].isASCIIDigit)
    }

    /// The end of `word` if it stands at `start` as a word of its own.
    private static func word(_ word: String, in characters: [Character], from start: Int) -> Int? {
        let letters = Array(word)
        guard start + letters.count <= characters.count, Array(characters[start..<start + letters.count]) == letters,
              isBoundary(characters, at: start + letters.count, allowingDigit: true) else { return nil }
        return start + letters.count
    }

    /// "am", "pm", "a.m.", "p.m." as a word of their own.
    private static func meridiem(_ characters: [Character], from start: Int) -> (end: Int, isPM: Bool)? {
        for (spelling, isPM) in [("am", false), ("a.m.", false), ("a.m", false), ("pm", true), ("p.m.", true), ("p.m", true)] {
            if let end = word(spelling, in: characters, from: start) { return (end, isPM) }
            // "a.m." ends in a dot, which is not a letter, so `word` already treats what follows as a boundary.
        }
        return nil
    }
}
