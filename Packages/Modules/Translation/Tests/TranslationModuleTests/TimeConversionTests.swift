import Foundation
import Testing
@testable import TranslationModule

func utc(_ iso: String) -> Date {
    ISO8601DateFormatter().date(from: iso)!
}

@Suite struct TimeZoneCatalogTests {
    func identifier(_ text: String) -> String? {
        TimeZoneCatalog.zone(named: text)?.identifier
    }

    @Test(arguments: [
        ("PST", "America/Los_Angeles"), ("pdt", "America/Los_Angeles"), ("PT", "America/Los_Angeles"), ("EST", "America/New_York"),
        ("ET", "America/New_York"), ("CST", "America/Chicago"), ("MST", "America/Denver"), ("JST", "Asia/Tokyo"),
        ("IST", "Asia/Kolkata"), ("ICT", "Asia/Ho_Chi_Minh"), ("CET", "Europe/Berlin"), ("BST", "Europe/London"),
        ("AEST", "Australia/Sydney"), ("SGT", "Asia/Singapore"), ("KST", "Asia/Seoul"), ("(PST)", "America/Los_Angeles"),
        ("Tokyo", "Asia/Tokyo"), ("tokyo time", "Asia/Tokyo"), ("in Tokyo", "Asia/Tokyo"), ("giờ Tokyo", "Asia/Tokyo"),
        ("theo giờ Tokyo", "Asia/Tokyo"), ("Hà Nội", "Asia/Ho_Chi_Minh"), ("giờ Hà Nội", "Asia/Ho_Chi_Minh"), ("ha noi", "Asia/Ho_Chi_Minh"),
        ("Sài Gòn", "Asia/Ho_Chi_Minh"), ("giờ Việt Nam", "Asia/Ho_Chi_Minh"), ("TP.HCM", "Asia/Ho_Chi_Minh"),
        ("New York", "America/New_York"), ("giờ New York", "America/New_York"), ("Los Angeles", "America/Los_Angeles"),
        ("giờ Nhật", "Asia/Tokyo"), ("giờ Nhật Bản", "Asia/Tokyo"), ("Luân Đôn", "Europe/London"), ("giờ Anh", "Europe/London"),
        ("Sydney", "Australia/Sydney"), ("São Paulo", "America/Sao_Paulo"), ("Asia/Tokyo", "Asia/Tokyo"), ("asia/ho_chi_minh", "Asia/Ho_Chi_Minh"),
        ("America/New_York", "America/New_York"), ("Đà Nẵng", "Asia/Ho_Chi_Minh"), ("London", "Europe/London"),
    ])
    func findsTheZoneByName(text: String, expected: String) {
        #expect(identifier(text) == expected)
    }

    @Test(arguments: [
        ("UTC", 0), ("utc", 0), ("GMT", 0), ("Z", 0), ("UTC+9", 32_400), ("UTC+09:00", 32_400), ("UTC+0900", 32_400), ("GMT+7", 25_200),
        ("UTC-5", -18_000), ("UTC−5", -18_000), ("utc+5:30", 19_800), ("UTC-03:30", -12_600), ("UTC+14", 50_400), ("GMT+0", 0),
    ])
    func readsAnOffset(text: String, seconds: Int) {
        #expect(TimeZoneCatalog.zone(named: text)?.secondsFromGMT() == seconds)
    }

    @Test(arguments: ["", "  ", "nowhere", "UTC+15", "UTC+9:75", "UTC+", "UTC+abc", "UTC+1:2:3", "UTC9", "xyz", "time", "giờ", "5 km", "UTC+123"])
    func refusesWhatIsNotAZone(text: String) {
        #expect(TimeZoneCatalog.zone(named: text) == nil)
    }

    @Test func everyNamedZoneExists() {
        // The tables name zones by identifier; a typo there would make a name silently useless.
        for name in ["Hà Nội", "Tokyo", "Seoul", "Shanghai", "Hong Kong", "Taipei", "Singapore", "Bangkok", "Jakarta", "Kuala Lumpur", "Manila",
                     "Delhi", "Dubai", "London", "Paris", "Berlin", "Madrid", "Rome", "Amsterdam", "Moscow", "Istanbul", "Cairo", "New York",
                     "Los Angeles", "Chicago", "Denver", "Toronto", "Vancouver", "Mexico City", "Sao Paulo", "Sydney", "Melbourne", "Auckland",
                     "Honolulu", "PST", "MST", "CST", "EST", "AKST", "HST", "BST", "CET", "EET", "WET", "MSK", "IST", "PKT", "ICT", "WIB",
                     "SGT", "HKT", "PHT", "JST", "KST", "AEST", "ACST", "AWST", "NZST", "SAST", "BRT", "Universal"] {
            #expect(TimeZoneCatalog.zone(named: name) != nil, "\(name)")
        }
    }

    @Test func labelsShowTheOffsetInForceAtThatMoment() throws {
        let la = try #require(TimeZone(identifier: "America/Los_Angeles"))
        #expect(TimeZoneCatalog.label(for: la, at: utc("2026-01-15T12:00:00Z")) == "Los Angeles · UTC-8")
        #expect(TimeZoneCatalog.label(for: la, at: utc("2026-07-15T12:00:00Z")) == "Los Angeles · UTC-7")
        let kolkata = try #require(TimeZone(identifier: "Asia/Kolkata"))
        #expect(TimeZoneCatalog.label(for: kolkata, at: utc("2026-01-15T12:00:00Z")) == "Kolkata · UTC+5:30")
        let hcm = try #require(TimeZone(identifier: "Asia/Ho_Chi_Minh"))
        #expect(TimeZoneCatalog.label(for: hcm, at: .now) == "Ho Chi Minh · UTC+7")
        #expect(TimeZoneCatalog.label(for: try #require(TimeZone(secondsFromGMT: 32_400)), at: .now) == "UTC+9")
        #expect(TimeZoneCatalog.label(for: try #require(TimeZone(identifier: "GMT")), at: .now) == "UTC")
        #expect(TimeZoneCatalog.offsetText(-12_600) == "UTC-3:30")
        #expect(TimeZoneCatalog.offsetText(0) == "UTC+0")
    }

    @Test func theSettingsPickerListsRegionsAndKeepsAChosenOne() {
        let options = TimeZoneCatalog.pickerOptions(including: "Etc/GMT+5")
        #expect(options.first { $0.id == "Asia/Tokyo" }?.title == "Tokyo (UTC+9)")
        #expect(options.first { $0.id == "America/New_York" } != nil)
        #expect(options.first { $0.id == "UTC" }?.title == "UTC")
        #expect(options.first { $0.id == "Etc/GMT+5" } != nil)
        #expect(options.first { $0.id == "Etc/GMT-3" } == nil)
        #expect(options.map(\.id) == options.map(\.id).sorted())
        // The usual list when the choice is in it, or is no zone at all.
        #expect(TimeZoneCatalog.pickerOptions(including: "Asia/Tokyo").count == options.count - 1)
        #expect(TimeZoneCatalog.pickerOptions(including: "Nowhere/Land").count == options.count - 1)
        #expect(TimeZoneCatalog.pickerOptions(including: "Asia/Tokyo").allSatisfy { !$0.title.isEmpty })
    }
}

@Suite struct TimeQueryTests {
    func query(_ text: String, requiresZone: Bool = false) -> (hour: Int, minute: Int, zone: String?)? {
        TimeQueryParser.parse(text, requiresZone: requiresZone).map { ($0.hour, $0.minute, $0.zone?.identifier) }
    }

    func isTime(_ text: String, _ hour: Int, _ minute: Int, _ zone: String? = nil) -> Bool {
        guard let result = query(text) else { return false }
        return result.hour == hour && result.minute == minute && result.zone == zone
    }

    @Test(arguments: [
        ("3pm PST", 15, 0, "America/Los_Angeles"), ("3 PM PST", 15, 0, "America/Los_Angeles"), ("3pm (PST)", 15, 0, "America/Los_Angeles"),
        ("3:30 pm EST", 15, 30, "America/New_York"), ("12am JST", 0, 0, "Asia/Tokyo"), ("12 pm JST", 12, 0, "Asia/Tokyo"),
        ("12:15 a.m. ET", 0, 15, "America/New_York"), ("9 a.m. PT", 9, 0, "America/Los_Angeles"), ("11:59 p.m. CET", 23, 59, "Europe/Berlin"),
        ("15:00 UTC+9", 15, 0, "GMT+0900"), ("15:00 UTC", 15, 0, "GMT"), ("07:05 GMT-5", 7, 5, "GMT-0500"), ("23:59 Tokyo", 23, 59, "Asia/Tokyo"),
        ("9:30 in Tokyo", 9, 30, "Asia/Tokyo"), ("14:00 Asia/Seoul", 14, 0, "Asia/Seoul"), ("8:00 am London time", 8, 0, "Europe/London"),
        ("0:00 UTC", 0, 0, "GMT"), ("9:30:15 EST", 9, 30, "America/New_York"),
    ])
    func readsEnglishTimesWithAZone(text: String, hour: Int, minute: Int, zone: String) {
        #expect(isTime(text, hour, minute, zone), "\(text) -> \(String(describing: query(text)))")
    }

    @Test(arguments: [
        ("9h sáng giờ Tokyo", 9, 0, "Asia/Tokyo"), ("9h sáng giờ Nhật", 9, 0, "Asia/Tokyo"), ("9 giờ sáng giờ Tokyo", 9, 0, "Asia/Tokyo"),
        ("9h30 sáng giờ Hà Nội", 9, 30, "Asia/Ho_Chi_Minh"), ("3h chiều giờ New York", 15, 0, "America/New_York"),
        ("8h tối giờ London", 20, 0, "Europe/London"), ("8 giờ tối giờ Hà Nội", 20, 0, "Asia/Ho_Chi_Minh"),
        ("21h30 giờ Seoul", 21, 30, "Asia/Seoul"), ("21h30 Seoul", 21, 30, "Asia/Seoul"), ("15 giờ 30 phút giờ Tokyo", 15, 30, "Asia/Tokyo"),
        ("15 giờ 30 giờ Tokyo", 15, 30, "Asia/Tokyo"), ("12h trưa PST", 12, 0, "America/Los_Angeles"), ("1h trưa PST", 13, 0, "America/Los_Angeles"),
        ("12h đêm Tokyo", 0, 0, "Asia/Tokyo"), ("11h đêm Tokyo", 23, 0, "Asia/Tokyo"), ("2h sáng EST", 2, 0, "America/New_York"),
        ("11h khuya Tokyo", 23, 0, "Asia/Tokyo"), ("6h chiều ICT", 18, 0, "Asia/Ho_Chi_Minh"), ("15h chiều Tokyo", 15, 0, "Asia/Tokyo"),
        ("9h SÁNG GIỜ TOKYO", 9, 0, "Asia/Tokyo"), ("10h sáng theo giờ Mỹ".replacing("Mỹ", with: "New York"), 10, 0, "America/New_York"),
    ])
    func readsVietnameseTimesWithAZone(text: String, hour: Int, minute: Int, zone: String) {
        #expect(isTime(text, hour, minute, zone), "\(text) -> \(String(describing: query(text)))")
    }

    @Test(arguments: [
        ("3pm", 15, 0), ("3 PM", 15, 0), ("3:30pm", 15, 30), ("15:00", 15, 0), ("9:05", 9, 5), ("0:00", 0, 0), ("23:59", 23, 59),
        ("9h", 9, 0), ("9h30", 9, 30), ("21h05", 21, 5), ("9h sáng", 9, 0), ("9 giờ sáng", 9, 0), ("7 giờ tối", 19, 0),
        ("12am", 0, 0), ("12pm", 12, 0), ("0h", 0, 0), ("9 giờ", 9, 0), ("9 giờ 15", 9, 15), ("9 giờ 15 phút", 9, 15),
    ])
    func aTimeWithoutAZoneIsTheUsersOwn(text: String, hour: Int, minute: Int) {
        #expect(isTime(text, hour, minute), "\(text) -> \(String(describing: query(text)))")
    }

    @Test func aTimeInsideRunningTextNeedsAZone() {
        #expect(query("3pm", requiresZone: true) == nil)
        #expect(query("15:00", requiresZone: true) == nil)
        #expect(query("9h sáng", requiresZone: true) == nil)
        #expect(query("3pm PST", requiresZone: true)?.zone == "America/Los_Angeles")
    }

    @Test(arguments: [
        "", "3", "25:00", "24:00", "9:60", "13pm", "0pm", "0am", "3 xm", "9:5", "9:5 pm", "123pm", "3pmPST", "3pm nowhere", "9h 61", "9h99",
        "15:00 pm", "9 hours", "9hours", "9 giờ rưỡi", "2h chiều ET".replacing("2h", with: "9h"), "12h sáng Tokyo", "8h sáng Tokyo 9h",
        "3pm PST tomorrow", "10:30 km", "1:2:3", "9:30:5 EST", "5h tối giờ", "7 sáng", "9h sáng giờ", "pm 3", "3 pm pm",
        "13h chiều ngày mai".replacing("ngày mai", with: "xyz"), "5:30 PM IST extra",
    ])
    func refusesWhatIsNotATime(text: String) {
        #expect(query(text) == nil, "\(text) -> \(String(describing: query(text)))")
    }
}

@Suite struct TimeConversionTests {
    let hanoi = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
    let london = TimeZone(identifier: "Europe/London")!
    let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    let newYork = TimeZone(identifier: "America/New_York")!

    func environment(_ now: String, zones: [TimeZone]? = nil, local: TimeZone? = nil) -> TimeEnvironment {
        TimeEnvironment(now: utc(now), local: local ?? hanoi, zones: zones ?? [london, tokyo])
    }

    func lines(_ text: String, now: String, zones: [TimeZone]? = nil, local: TimeZone? = nil) throws -> [String] {
        let query = try #require(TimeQueryParser.parse(text), "\(text)")
        let conversion = TimeConversion.conversion(for: query, source: text, in: environment(now, zones: zones, local: local))
        guard case .lines(let lines) = conversion.outcome else { return [] }
        return lines.map { "\($0.label ?? ""): \($0.text)" }
    }

    @Test func pacificTimeInWinterIsEightHoursBehindUTC() throws {
        // 15:00 PST = 23:00 UTC on 15 January.
        #expect(try lines("3pm PST", now: "2026-01-15T12:00:00Z") == [
            "Giờ máy · UTC+7: 06:00 (hôm sau)", "London · UTC+0: 23:00", "Tokyo · UTC+9: 08:00 (hôm sau)",
        ])
    }

    @Test func pacificTimeInSummerIsSevenHoursBehindUTC() throws {
        // Daylight saving: 15:00 PDT = 22:00 UTC, and London is on summer time as well.
        #expect(try lines("3pm PST", now: "2026-07-15T12:00:00Z") == [
            "Giờ máy · UTC+7: 05:00 (hôm sau)", "London · UTC+1: 23:00", "Tokyo · UTC+9: 07:00 (hôm sau)",
        ])
    }

    @Test func theNoteSaysHowTheTimeWasRead() throws {
        let query = try #require(TimeQueryParser.parse("3pm PST"))
        let winter = TimeConversion.conversion(for: query, source: "3pm PST", in: environment("2026-01-15T12:00:00Z"))
        #expect(winter.note == "Hiểu là 15:00, Los Angeles · UTC-8")
        #expect(winter.source == "3pm PST")
        let summer = TimeConversion.conversion(for: query, source: "3pm PST", in: environment("2026-07-15T12:00:00Z"))
        #expect(summer.note == "Hiểu là 15:00, Los Angeles · UTC-7")
    }

    @Test func aFixedOffsetIgnoresDaylightSaving() throws {
        #expect(try lines("15:00 UTC+9", now: "2026-01-15T12:00:00Z") == [
            "Giờ máy · UTC+7: 13:00", "London · UTC+0: 06:00",
        ])
        #expect(try lines("15:00 UTC+9", now: "2026-07-15T12:00:00Z") == [
            "Giờ máy · UTC+7: 13:00", "London · UTC+1: 07:00",
        ])
    }

    @Test func vietnameseTimeInTokyo() throws {
        // The user's own zone is Hanoi, two hours behind Tokyo; Tokyo itself is the source and is left out.
        #expect(try lines("9h sáng giờ Tokyo", now: "2026-01-15T12:00:00Z") == [
            "Giờ máy · UTC+7: 07:00", "London · UTC+0: 00:00",
        ])
    }

    @Test func theDayIsTheSourceZonesToday() throws {
        // 20:00 UTC on 15 January is already the 16th in Tokyo, so "3pm JST" is the 16th there, and the 16th in Hanoi
        // at 13:00, but only the 16th, 06:00 in London.
        #expect(try lines("3pm JST", now: "2026-01-15T20:00:00Z", zones: [london, newYork]) == [
            "Giờ máy · UTC+7: 13:00", "London · UTC+0: 06:00", "New York · UTC-5: 01:00",
        ])
    }

    @Test func showsTheDayAShiftsInto() throws {
        // 23:00 in Los Angeles is 07:00 UTC the next day and 14:00 in Hanoi on the next day.
        let result = try lines("11pm PST", now: "2026-01-15T12:00:00Z", zones: [newYork, tokyo])
        #expect(result == ["Giờ máy · UTC+7: 14:00 (hôm sau)", "New York · UTC-5: 02:00 (hôm sau)", "Tokyo · UTC+9: 16:00 (hôm sau)"])
        // 01:00 in Tokyo is 17:00 UTC the day before.
        #expect(try lines("1am JST", now: "2026-01-15T12:00:00Z", zones: [newYork, london]) == [
            "Giờ máy · UTC+7: 23:00 (hôm trước)", "New York · UTC-5: 11:00 (hôm trước)", "London · UTC+0: 16:00 (hôm trước)",
        ])
    }

    @Test func twoDaysAwayIsShownAsNumber() throws {
        let kiritimati = try #require(TimeZone(identifier: "Pacific/Kiritimati"))
        let midway = try #require(TimeZone(secondsFromGMT: -12 * 3600))
        let query = try #require(TimeQueryParser.parse("23:00 UTC-12"))
        #expect(query.zone == midway)
        let conversion = TimeConversion.conversion(
            for: query, source: "23:00 UTC-12", in: TimeEnvironment(now: utc("2026-01-15T12:00:00Z"), local: hanoi, zones: [kiritimati])
        )
        guard case .lines(let lines) = conversion.outcome else {
            Issue.record("no lines")
            return
        }
        #expect(lines.map(\.text) == ["18:00 (hôm sau)", "01:00 (+2 ngày)"])
    }

    @Test func aTimeWithoutAZoneIsConvertedToTheChosenOnes() throws {
        #expect(try lines("3pm", now: "2026-01-15T12:00:00Z") == ["London · UTC+0: 08:00", "Tokyo · UTC+9: 17:00"])
        // The user's own zone is where it is written, so it is not repeated even when chosen.
        #expect(try lines("3pm", now: "2026-01-15T12:00:00Z", zones: [hanoi, tokyo]) == ["Tokyo · UTC+9: 17:00"])
    }

    @Test func leavesOutZonesThatAreTheSameClock() throws {
        // Tokyo and Seoul are both UTC+9: the second line would say what the first does.
        let seoul = TimeZone(identifier: "Asia/Seoul")!
        #expect(try lines("3pm PST", now: "2026-01-15T12:00:00Z", zones: [tokyo, seoul]) == [
            "Giờ máy · UTC+7: 06:00 (hôm sau)", "Tokyo · UTC+9: 08:00 (hôm sau)",
        ])
        // Same zone chosen twice, or the zone of the text itself.
        #expect(try lines("3pm PST", now: "2026-01-15T12:00:00Z", zones: [newYork, newYork]) == [
            "Giờ máy · UTC+7: 06:00 (hôm sau)", "New York · UTC-5: 18:00",
        ])
        let la = TimeZone(identifier: "America/Los_Angeles")!
        #expect(try lines("3pm PST", now: "2026-01-15T12:00:00Z", zones: [la]) == ["Giờ máy · UTC+7: 06:00 (hôm sau)"])
        // Another zone with the same offset today, in winter, is the same clock too.
        let vancouver = TimeZone(identifier: "America/Vancouver")!
        #expect(try lines("3pm PST", now: "2026-01-15T12:00:00Z", zones: [vancouver]) == ["Giờ máy · UTC+7: 06:00 (hôm sau)"])
    }

    @Test func aTimeThatDoesNotExistMovesForward() throws {
        // Clocks in New York jump from 02:00 to 03:00 on 8 March 2026: 02:30 is read as 03:30 EDT (07:30 UTC).
        #expect(try lines("2:30 am ET", now: "2026-03-08T12:00:00Z", zones: [london]) == [
            "Giờ máy · UTC+7: 14:30", "London · UTC+0: 07:30",
        ])
    }

    @Test func aTimeThatHappensTwiceIsTheFirstOne() throws {
        // 01:30 happens twice in New York on 1 November 2026; the first is EDT (05:30 UTC).
        #expect(try lines("1:30 am ET", now: "2026-11-01T12:00:00Z", zones: [london]) == [
            "Giờ máy · UTC+7: 12:30", "London · UTC+0: 05:30",
        ])
    }

    @Test func theDayBeforeAndAfterTheChangeUseTheirOwnOffsets() throws {
        // 8 March 2026, 12:00 UTC: New York has just changed to EDT. 3pm ET that day is 19:00 UTC.
        #expect(try lines("3pm ET", now: "2026-03-08T12:00:00Z", zones: [london]) == [
            "Giờ máy · UTC+7: 02:00 (hôm sau)", "London · UTC+0: 19:00",
        ])
        // The day before, still EST: 3pm is 20:00 UTC.
        #expect(try lines("3pm ET", now: "2026-03-07T12:00:00Z", zones: [london]) == [
            "Giờ máy · UTC+7: 03:00 (hôm sau)", "London · UTC+0: 20:00",
        ])
    }

    @Test func nothingToShowWhenEveryZoneIsTheSameClock() throws {
        #expect(try lines("3pm", now: "2026-01-15T12:00:00Z", zones: [hanoi, hanoi]).isEmpty)
    }
}
