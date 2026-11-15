import Foundation
import Testing
@testable import BatteryModule
@testable import MyNotchCore
@testable import MyNotchTestSupport

@Suite("Battery Schedule Tests")
struct BatteryScheduleTests {
    private func makeCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 7 * 3600) ?? .current // GMT+7
        return cal
    }

    private func makeDate(weekday: Int, hour: Int, minute: Int, calendar: Calendar) -> Date {
        // weekday: 1 = CN, 2 = T2, ..., 7 = T7
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 11
        comps.day = 2 + (weekday - 2) // Nov 2, 2026 is Monday (weekday 2)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return calendar.date(from: comps)!
    }

    @Test("Contract Test 4: Default Schedule Rules Match Across Week")
    func testDefaultScheduleRulesMatchAcrossWeek() {
        let calendar = makeCalendar()
        let isolatedDefaults = makeIsolatedDefaults()
        let engine = BatteryScheduleEngine(userDefaults: isolatedDefaults)
        engine.isEnabled = true

        let defaults = BatteryScheduleEngine.defaultRules
        #expect(defaults.count == 3)
        #expect(defaults[0].title == "Giờ làm việc văn phòng")
        #expect(defaults[0].action == .chargeLimit(80))
        #expect(defaults[1].title == "Buổi tối xả pin tự nhiên")
        #expect(defaults[1].action == .forceDischarge(target: 60))
        #expect(defaults[2].title == "Cuối tuần đi thuyền an toàn")
        #expect(defaults[2].action == .sailing(lower: 70, upper: 80))

        // Tuesday 10:00 -> Matches Rule 1 (Office Hours)
        let tue1000 = makeDate(weekday: 3, hour: 10, minute: 0, calendar: calendar)
        let active1 = engine.activeRule(at: tue1000, calendar: calendar)
        #expect(active1?.title == "Giờ làm việc văn phòng")

        // Wednesday 19:00 -> Matches Rule 2 (Evening Discharge)
        let wed1900 = makeDate(weekday: 4, hour: 19, minute: 0, calendar: calendar)
        let active2 = engine.activeRule(at: wed1900, calendar: calendar)
        #expect(active2?.title == "Buổi tối xả pin tự nhiên")

        // Saturday 15:00 -> Matches Rule 3 (Weekend Sailing)
        let sat1500 = makeDate(weekday: 7, hour: 15, minute: 0, calendar: calendar)
        let active3 = engine.activeRule(at: sat1500, calendar: calendar)
        #expect(active3?.title == "Cuối tuần đi thuyền an toàn")
    }

    @Test("Contract Test 5: Boundary and Overnight Schedule Rule Matching")
    func testBoundaryAndOvernightScheduleRuleMatching() {
        let calendar = makeCalendar()
        let isolatedDefaults = makeIsolatedDefaults()
        let engine = BatteryScheduleEngine(userDefaults: isolatedDefaults)
        engine.isEnabled = true

        // Exactly at 18:00 on Wednesday:
        // Rule 1 (08:00 - 18:00) ends at 18:00 (exclusive)
        // Rule 2 (18:00 - 22:00) starts at 18:00 (inclusive)
        let wed1800 = makeDate(weekday: 4, hour: 18, minute: 0, calendar: calendar)
        let activeAt1800 = engine.activeRule(at: wed1800, calendar: calendar)
        #expect(activeAt1800?.title == "Buổi tối xả pin tự nhiên")

        let wed1759 = makeDate(weekday: 4, hour: 17, minute: 59, calendar: calendar)
        let activeAt1759 = engine.activeRule(at: wed1759, calendar: calendar)
        #expect(activeAt1759?.title == "Giờ làm việc văn phòng")

        // Overnight Rule: Friday 22:00 to 06:00
        let fridayNightRule = BatteryScheduleRule(
            id: UUID(),
            title: "Ca đêm Thứ Sáu",
            isEnabled: true,
            daysOfWeek: [6], // Friday only (weekday 6)
            startHour: 22,
            startMinute: 0,
            endHour: 6,
            endMinute: 0,
            action: .forceDischarge(target: 50)
        )

        // Friday 23:00 -> Matches
        let fri2300 = makeDate(weekday: 6, hour: 23, minute: 0, calendar: calendar)
        #expect(fridayNightRule.matches(date: fri2300, calendar: calendar) == true)

        // Saturday 02:00 (Part of Friday night shift) -> Matches
        let sat0200 = makeDate(weekday: 7, hour: 2, minute: 0, calendar: calendar)
        #expect(fridayNightRule.matches(date: sat0200, calendar: calendar) == true)

        // Saturday 07:00 (Past 06:00 end boundary) -> Does NOT match
        let sat0700 = makeDate(weekday: 7, hour: 7, minute: 0, calendar: calendar)
        #expect(fridayNightRule.matches(date: sat0700, calendar: calendar) == false)

        // Sunday 02:00 (Previous day was Saturday, not Friday) -> Does NOT match
        let sun0200 = makeDate(weekday: 1, hour: 2, minute: 0, calendar: calendar)
        #expect(fridayNightRule.matches(date: sun0200, calendar: calendar) == false)
    }

    @Test("Contract Test 6: Disabled Rule, Empty Days, and Corrupted Defaults Fallback")
    func testScheduleRuleDisabledEmptyDaysAndCorruptedDefaultsFallback() {
        let calendar = makeCalendar()
        let isolatedDefaults = makeIsolatedDefaults()

        // Rule with isEnabled == false
        var disabledRule = BatteryScheduleRule(
            id: UUID(),
            title: "Tắt",
            isEnabled: false,
            daysOfWeek: [2, 3, 4, 5, 6],
            startHour: 8,
            startMinute: 0,
            endHour: 18,
            endMinute: 0,
            action: .chargeLimit(80)
        )
        let mon1000 = makeDate(weekday: 2, hour: 10, minute: 0, calendar: calendar)
        #expect(disabledRule.matches(date: mon1000, calendar: calendar) == false)

        // Rule with empty daysOfWeek
        disabledRule.isEnabled = true
        disabledRule.daysOfWeek = []
        #expect(disabledRule.matches(date: mon1000, calendar: calendar) == false)

        // Corrupted JSON in UserDefaults fallback
        isolatedDefaults.set("CORRUPTED_JSON_DATA_STRING".data(using: .utf8), forKey: BatteryScheduleEngine.rulesKey)
        let fallbackEngine = BatteryScheduleEngine(userDefaults: isolatedDefaults)
        #expect(fallbackEngine.rules.count == BatteryScheduleEngine.defaultRules.count)
        #expect(fallbackEngine.rules[0].title == "Giờ làm việc văn phòng")
    }

    @Test("Contract Test 7: Persistence Across Instances and Active Rule Application")
    func testSchedulePersistenceAcrossEngineInstancesAndActiveRuleApplication() async {
        let calendar = makeCalendar()
        let isolatedDefaults = makeIsolatedDefaults()

        // Engine 1: Enable schedule and add custom rule
        let engine1 = BatteryScheduleEngine(userDefaults: isolatedDefaults)
        engine1.setEnabled(true)

        let customRule = BatteryScheduleRule(
            id: UUID(),
            title: "Friday Evening Sailing",
            isEnabled: true,
            daysOfWeek: [6], // Friday
            startHour: 20,
            startMinute: 0,
            endHour: 21,
            endMinute: 0,
            action: .sailing(lower: 50, upper: 65)
        )
        engine1.rules = [customRule] + engine1.rules

        // Engine 2: Loads from same defaults
        let engine2 = BatteryScheduleEngine(userDefaults: isolatedDefaults)
        #expect(engine2.isEnabled == true)
        #expect(engine2.rules.contains { $0.title == "Friday Evening Sailing" })

        // Apply active rule at Friday 20:30 to BatteryModule
        let snapshot = PowerSourceSnapshot(percent: 80, isCharging: true, isOnAC: true)
        let reader = FakePowerSource(snapshot)
        let module = BatteryModule(reader: reader, scheduleEngine: engine2)
        let harness = RegistryHarness([module])
        await harness.registry.bootstrap()

        let fri2030 = makeDate(weekday: 6, hour: 20, minute: 30, calendar: calendar)
        let applied = engine2.applyActiveRule(at: fri2030, to: module, force: true)
        #expect(applied?.title == "Friday Evening Sailing")

        let status = module.studioStatus()
        #expect(status.chargeLimit == 65)
        #expect(status.sailingDelta == 15)
        #expect(status.isLimitToEightyEnabled == true)
    }
}
