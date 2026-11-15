import Foundation

/// Names of time zones as people write them next to a time: "PST", "UTC+9", "Tokyo", "giờ Hà Nội".
nonisolated enum TimeZoneCatalog {
    /// A zone by abbreviation, offset ("UTC+9", "GMT-05:30"), city or country in English or Vietnamese, or IANA name.
    /// "giờ", "in", "at" and a trailing "time" are ignored.
    ///
    /// An abbreviation stands for the region, with its daylight saving: "PST" in July is Los Angeles' summer time,
    /// since "3pm PST" nearly always means "3pm in California" and a literal UTC-8 would be an hour off.
    static func zone(named text: String) -> TimeZone? {
        var words = text.folded.replacing(".", with: " ").trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "()[],-–:;.")))
            .split(whereSeparator: \.isWhitespace).map(String.init)
        while let first = words.first, ["theo", "gio", "o", "tai", "in", "at", "by"].contains(first), words.count > 1 { words.removeFirst() }
        while let last = words.last, ["time", "timezone", "tz"].contains(last), words.count > 1 { words.removeLast() }
        let name = words.joined(separator: " ")
        guard !name.isEmpty else { return nil }
        if let offset = fixedOffset(name) { return offset }
        if let identifier = names[name] { return TimeZone(identifier: identifier) }
        return identifiers[name.replacing(" ", with: "_")].flatMap { TimeZone(identifier: $0) }
    }

    /// A zone the text names unmistakably, which is all a time inside a sentence may rely on:
    ///
    /// - a capital abbreviation ("PST", "ICT") or an offset ("UTC+9", "gmt-5:30") or an IANA name ("Asia/Tokyo");
    /// - "giờ" or "theo giờ" and a place ("giờ Tokyo", "giờ Nga");
    /// - a place and "time" ("Tokyo time", "Russia time").
    ///
    /// A bare place never counts, since "Nga" is Russia and a common name, "anh" is England and "elder brother", "ý" is Italy
    /// and "meaning", and "west" is a direction. Lower-case abbreviations ("pst", "et", "west") are words as well.
    static func explicitZone(_ text: String) -> TimeZone? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "()[],-–:;.")))
        let words = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = words.first else { return nil }
        if words.count == 1 {
            if let offset = fixedOffset(first.folded), first.folded != "z" { return offset }
            if first == "Z" { return TimeZone(identifier: "GMT") }
            if first == first.uppercased(), let identifier = abbreviations[first.folded] { return TimeZone(identifier: identifier) }
            return first.contains("/") ? identifiers[first.folded].flatMap { TimeZone(identifier: $0) } : nil
        }
        let folded = words.map(\.folded)
        if folded[0] == "gio" || (folded[0] == "theo" && folded[1] == "gio") {
            return zone(named: words.joined(separator: " "))
        }
        if folded.last == "time" { return zone(named: words.dropLast().joined(separator: " ")) }
        return nil
    }

    /// "UTC", "GMT+7", "utc-03:30", "utc+0530", "z".
    private static func fixedOffset(_ name: String) -> TimeZone? {
        let rest: Substring
        if name == "z" { return TimeZone(identifier: "GMT") }
        if name.hasPrefix("utc") || name.hasPrefix("gmt") { rest = name.dropFirst(3) } else { return nil }
        if rest.isEmpty { return TimeZone(identifier: "GMT") }
        guard let sign = rest.first, sign == "+" || sign == "-" || sign == "−" else { return nil }
        let digits = rest.dropFirst().split(separator: ":", omittingEmptySubsequences: false)
        var hours: Int?
        var minutes = 0
        switch digits.count {
        case 1 where digits[0].count <= 2: hours = Int(digits[0])
        case 1 where digits[0].count == 4: hours = Int(digits[0].prefix(2)); minutes = Int(digits[0].suffix(2)) ?? 99
        case 2: hours = Int(digits[0]); minutes = Int(digits[1]) ?? 99
        default: return nil
        }
        guard let hours, digits.allSatisfy({ $0.allSatisfy(\.isASCIIDigit) }), hours <= 14, minutes < 60 else { return nil }
        let seconds = (hours * 3600 + minutes * 60) * (sign == "+" ? 1 : -1)
        return TimeZone(secondsFromGMT: seconds)
    }

    /// "UTC+9", "UTC+5:30", "UTC-3:30", "UTC+0".
    static func offsetText(_ seconds: Int) -> String {
        let minutes = abs(seconds) / 60
        let sign = seconds < 0 ? "-" : "+"
        return "UTC\(sign)\(minutes / 60)" + (minutes % 60 == 0 ? "" : ":" + String(format: "%02d", minutes % 60))
    }

    /// "Tokyo · UTC+9" for a region, "UTC+9" for a bare offset and "UTC" for UTC itself, with the offset in force at
    /// `date`.
    static func label(for zone: TimeZone, at date: Date) -> String {
        let seconds = zone.secondsFromGMT(for: date)
        guard zone.identifier.contains("/") else { return seconds == 0 ? "UTC" : offsetText(seconds) }
        let offset = offsetText(seconds)
        let city = zone.identifier.split(separator: "/").last.map { String($0).replacing("_", with: " ") } ?? zone.identifier
        return "\(city) · \(offset)"
    }

    /// The zones the Settings picker offers, as "Tokyo (UTC+9)", sorted by identifier so regions stay together. A chosen
    /// zone the list lacks (an `Etc/` one) is added, so the picker never shows an empty selection.
    static func pickerOptions(including current: String) -> [(id: String, title: String)] {
        guard !allPickerOptions.contains(where: { $0.id == current }), let zone = TimeZone(identifier: current) else { return allPickerOptions }
        return (allPickerOptions + [(current, title(of: zone, at: .now))]).sorted { $0.id < $1.id }
    }

    private static let allPickerOptions: [(id: String, title: String)] = {
        let now = Date.now
        let regions = TimeZone.knownTimeZoneIdentifiers.filter { $0.contains("/") && !$0.hasPrefix("Etc/") } + ["UTC"]
        return Set(regions).sorted().compactMap { identifier in
            TimeZone(identifier: identifier).map { (identifier, title(of: $0, at: now)) }
        }
    }()

    private static func title(of zone: TimeZone, at date: Date) -> String {
        let text = label(for: zone, at: date)
        guard let separator = text.range(of: " · ") else { return text }
        return text.replacingCharacters(in: separator, with: " (") + ")"
    }

    private static let identifiers: [String: String] = {
        Dictionary(TimeZone.knownTimeZoneIdentifiers.map { ($0.folded, $0) }, uniquingKeysWith: { first, _ in first })
    }()

    /// Abbreviation (folded, as in "pst") to IANA identifier.
    private static let abbreviations: [String: String] = {
        let table: [String: [String]] = [
            "America/Los_Angeles": ["pst", "pdt", "pt"],
            "America/Denver": ["mst", "mdt", "mt"],
            "America/Chicago": ["cst", "cdt", "ct"],
            "America/New_York": ["est", "edt", "et"],
            "America/Anchorage": ["akst", "akdt"],
            "Pacific/Honolulu": ["hst"],
            "Europe/London": ["bst"],
            "Europe/Berlin": ["cet", "cest"],
            "Europe/Athens": ["eet", "eest"],
            "Europe/Lisbon": ["wet", "west"],
            "Europe/Moscow": ["msk"],
            "Asia/Kolkata": ["ist"],
            "Asia/Karachi": ["pkt"],
            "Asia/Ho_Chi_Minh": ["ict"],
            "Asia/Jakarta": ["wib"],
            "Asia/Singapore": ["sgt"],
            "Asia/Hong_Kong": ["hkt"],
            "Asia/Manila": ["pht"],
            "Asia/Tokyo": ["jst"],
            "Asia/Seoul": ["kst"],
            "Australia/Sydney": ["aest", "aedt"],
            "Australia/Adelaide": ["acst", "acdt"],
            "Australia/Perth": ["awst"],
            "Pacific/Auckland": ["nzst", "nzdt"],
            "Africa/Johannesburg": ["sast"],
            "America/Sao_Paulo": ["brt"],
        ]
        var result: [String: String] = [:]
        for (identifier, names) in table {
            for name in names { result[name] = identifier }
        }
        return result
    }()

    /// Folded name to IANA identifier: the abbreviations and the places.
    private static let names: [String: String] = {
        let places: [String: [String]] = [
            "Asia/Ho_Chi_Minh": ["Hà Nội", "Hanoi", "Sài Gòn", "Saigon", "Hồ Chí Minh", "Ho Chi Minh", "TP HCM", "TPHCM", "HCM", "Đà Nẵng", "Da Nang", "Việt Nam", "Vietnam"],
            "Asia/Tokyo": ["Tokyo", "Tôkyô", "Đông Kinh", "Osaka", "Kyoto", "Nhật", "Nhật Bản", "Japan"],
            "Asia/Seoul": ["Seoul", "Hàn Quốc", "Hàn", "Korea", "Busan"],
            "Asia/Shanghai": ["Shanghai", "Thượng Hải", "Beijing", "Bắc Kinh", "Trung Quốc", "China", "Shenzhen"],
            "Asia/Hong_Kong": ["Hong Kong", "Hồng Kông"],
            "Asia/Taipei": ["Taipei", "Đài Bắc", "Đài Loan", "Taiwan"],
            "Asia/Singapore": ["Singapore", "Xin-ga-po"],
            "Asia/Bangkok": ["Bangkok", "Băng Cốc", "Thái Lan", "Thailand"],
            "Asia/Jakarta": ["Jakarta", "Indonesia"],
            "Asia/Kuala_Lumpur": ["Kuala Lumpur", "Malaysia"],
            "Asia/Manila": ["Manila", "Philippines"],
            "Asia/Kolkata": ["Delhi", "New Delhi", "Mumbai", "Kolkata", "Bangalore", "India", "Ấn Độ"],
            "Asia/Dubai": ["Dubai"],
            "Europe/London": ["London", "Luân Đôn", "Anh", "UK", "England"],
            "Europe/Paris": ["Paris", "Pa-ri", "Pháp", "France"],
            "Europe/Berlin": ["Berlin", "Đức", "Germany"],
            "Europe/Madrid": ["Madrid", "Tây Ban Nha", "Spain"],
            "Europe/Rome": ["Rome", "Rô-ma", "Italy", "Ý"],
            "Europe/Amsterdam": ["Amsterdam", "Hà Lan"],
            "Europe/Moscow": ["Moscow", "Mát-xcơ-va", "Nga", "Russia"],
            "Europe/Istanbul": ["Istanbul"],
            "Africa/Cairo": ["Cairo"],
            "America/New_York": ["New York", "NYC", "Nữu Ước", "Boston", "Washington", "Washington DC", "Miami", "Atlanta"],
            "America/Los_Angeles": ["Los Angeles", "San Francisco", "Seattle", "San Jose", "Silicon Valley", "California"],
            "America/Chicago": ["Chicago", "Dallas", "Houston"],
            "America/Denver": ["Denver"],
            "America/Toronto": ["Toronto"],
            "America/Vancouver": ["Vancouver"],
            "America/Mexico_City": ["Mexico City"],
            "America/Sao_Paulo": ["São Paulo", "Sao Paulo"],
            "Australia/Sydney": ["Sydney"],
            "Australia/Melbourne": ["Melbourne"],
            "Pacific/Auckland": ["Auckland", "New Zealand"],
            "Pacific/Honolulu": ["Honolulu", "Hawaii"],
            "UTC": ["Universal"],
        ]
        var table = abbreviations
        for (identifier, names) in places {
            for name in names { table[name.folded] = identifier }
        }
        return table
    }()
}
