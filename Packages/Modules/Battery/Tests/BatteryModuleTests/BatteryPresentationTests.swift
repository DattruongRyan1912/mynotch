import Testing
@testable import BatteryModule

/// Every combination of: charging, on AC, Low Power Mode, level at or below the threshold; and the colour it gives.
private nonisolated let toneCases: [(Bool, Bool, Bool, Bool, BatteryFillTone)] = [
    (false, false, false, false, .normal),
    (false, false, false, true, .low),
    (false, false, true, false, .lowPower),
    (false, false, true, true, .low),        // red wins over yellow
    (false, true, false, false, .normal),
    (false, true, false, true, .normal),     // on AC the level is no alarm
    (false, true, true, false, .lowPower),
    (false, true, true, true, .lowPower),
    (true, true, false, false, .charging),
    (true, true, false, true, .charging),
    (true, true, true, false, .charging),    // charging wins over Low Power Mode
    (true, true, true, true, .charging),
    // Not a state macOS reports (charging needs a charger), but the colour is still defined: charging.
    (true, false, false, false, .charging),
    (true, false, false, true, .charging),
    (true, false, true, false, .charging),
    (true, false, true, true, .charging),
]

@Suite struct BatteryPresentationTests {
    private func snapshot(
        _ percent: Int = 80, charging: Bool = false, onAC: Bool = false, toEmpty: Int? = nil, toFull: Int? = nil
    ) -> PowerSourceSnapshot {
        PowerSourceSnapshot(percent: percent, isCharging: charging, isOnAC: onAC, minutesToEmpty: toEmpty, minutesToFull: toFull)
    }

    private func presentation(
        _ snapshot: PowerSourceSnapshot, details: BatteryDetails? = nil, lowPowerMode: Bool = false, threshold: Int = 20
    ) -> BatteryPresentation {
        BatteryPresentation(snapshot: snapshot, details: details, isLowPowerMode: lowPowerMode, lowThreshold: threshold)
    }

    private let fullDetails = BatteryDetails(cycleCount: 312, healthPercent: 92, batteryWatts: 12, adapterWatts: 96)

    // MARK: Fill colour

    @Test(arguments: toneCases)
    func fillColourFollowsTheBatteryState(charging: Bool, onAC: Bool, lowPowerMode: Bool, low: Bool, expected: BatteryFillTone) {
        let percent = low ? 15 : 50
        let tone = presentation(snapshot(percent, charging: charging, onAC: onAC), lowPowerMode: lowPowerMode, threshold: 20).tone
        #expect(tone == expected)
    }

    @Test func theLowThresholdIsInclusive() {
        #expect(presentation(snapshot(20), threshold: 20).tone == .low)
        #expect(presentation(snapshot(21), threshold: 20).tone == .normal)
        #expect(presentation(snapshot(21), threshold: 25).tone == .low)
    }

    // MARK: Time column

    @Test func chargingShowsTimeToFull() {
        let time = presentation(snapshot(charging: true, onAC: true, toFull: 80)).facts[0]
        #expect(time == BatteryFact(kind: .time, value: "Đầy sau 1 giờ 20 phút", label: "Đang sạc"))
    }

    @Test func chargingWithoutAnEstimateSaysItIsEstimating() {
        let time = presentation(snapshot(charging: true, onAC: true)).facts[0]
        #expect(time == BatteryFact(kind: .time, value: "Đang ước tính…", label: "Đang sạc"))
    }

    @Test func pluggedInButNotChargingStopsCharging() {
        let time = presentation(snapshot(onAC: true)).facts[0]
        #expect(time == BatteryFact(kind: .time, value: "Không sạc thêm", label: "Đã cắm sạc"))
    }

    @Test func onBatteryShowsTimeRemaining() {
        let time = presentation(snapshot(55, toEmpty: 190)).facts[0]
        #expect(time == BatteryFact(kind: .time, value: "Còn khoảng 3 giờ 10 phút", label: "Dùng pin"))
    }

    @Test func onBatteryWithoutAnEstimateSaysItIsEstimating() {
        let time = presentation(snapshot(55)).facts[0]
        #expect(time == BatteryFact(kind: .time, value: "Đang ước tính…", label: "Dùng pin"))
    }

    @Test func durationsAreWrittenInHoursAndMinutes() {
        #expect(BatteryPresentation.duration(0) == "0 phút")
        #expect(BatteryPresentation.duration(45) == "45 phút")
        #expect(BatteryPresentation.duration(60) == "1 giờ")
        #expect(BatteryPresentation.duration(135) == "2 giờ 15 phút")
    }

    // MARK: Source column

    @Test func sourceNamesTheAdapterWithItsWattage() {
        let facts = presentation(snapshot(charging: true, onAC: true, toFull: 30), details: fullDetails).facts
        #expect(facts[1] == BatteryFact(kind: .source, value: "Bộ sạc 96 W", label: "Nguồn"))
    }

    @Test func sourceWithoutAWattageIsJustTheCharger() {
        let details = BatteryDetails(cycleCount: 10)
        #expect(presentation(snapshot(onAC: true), details: details).facts[1].value == "Bộ sạc")
        #expect(presentation(snapshot(onAC: true), details: nil).facts[1].value == "Bộ sạc")
    }

    @Test func onBatterySourceIsTheBatteryEvenIfTheRegistryStillListsAnAdapter() {
        let facts = presentation(snapshot(toEmpty: 200), details: fullDetails).facts
        #expect(facts[1] == BatteryFact(kind: .source, value: "Pin", label: "Nguồn"))
    }

    // MARK: Power column

    @Test func powerIntoTheBatteryIsCharging() {
        let power = presentation(snapshot(charging: true, onAC: true), details: BatteryDetails(batteryWatts: 12.4)).fact(.power)
        #expect(power == BatteryFact(kind: .power, value: "12 W", label: "Đang nạp"))
    }

    @Test func powerOutOfTheBatteryIsConsumption() {
        let power = presentation(snapshot(toEmpty: 100), details: BatteryDetails(batteryWatts: -12.6)).fact(.power)
        #expect(power == BatteryFact(kind: .power, value: "13 W", label: "Đang tiêu thụ"))
    }

    @Test func powerBelowOneWattIsLeftOut() {
        #expect(presentation(snapshot(), details: BatteryDetails(batteryWatts: 0.99)).fact(.power) == nil)
        #expect(presentation(snapshot(), details: BatteryDetails(batteryWatts: -0.4)).fact(.power) == nil)
        #expect(presentation(snapshot(), details: BatteryDetails(batteryWatts: 0)).fact(.power) == nil)
        #expect(presentation(snapshot(), details: BatteryDetails(batteryWatts: 1)).fact(.power)?.value == "1 W")
        #expect(presentation(snapshot(), details: BatteryDetails(batteryWatts: nil)).fact(.power) == nil)
    }

    // MARK: Capacity, cycles, Low Power Mode

    @Test func capacityAndCyclesComeFromTheDetails() {
        let facts = presentation(snapshot(), details: fullDetails)
        #expect(facts.fact(.capacity) == BatteryFact(kind: .capacity, value: "92%", label: "Dung lượng tối đa"))
        #expect(facts.fact(.cycles) == BatteryFact(kind: .cycles, value: "312", label: "Chu kỳ sạc"))
    }

    @Test func aBrandNewBatteryHasZeroCycles() {
        #expect(presentation(snapshot(), details: BatteryDetails(cycleCount: 0)).fact(.cycles)?.value == "0")
    }

    @Test func lowPowerModeAddsASixthColumnAtTheEnd() {
        let facts = presentation(snapshot(charging: true, onAC: true, toFull: 30), details: fullDetails, lowPowerMode: true).facts
        #expect(facts.map(\.kind) == [.time, .source, .power, .capacity, .cycles, .lowPowerMode])
        #expect(facts.last == BatteryFact(kind: .lowPowerMode, value: "Đang bật", label: "Nguồn điện thấp"))
    }

    // MARK: Which columns appear

    @Test func columnsAppearInOrderAndOnlyWhenKnown() {
        let all = presentation(snapshot(charging: true, onAC: true, toFull: 30), details: fullDetails).facts.map(\.kind)
        #expect(all == [.time, .source, .power, .capacity, .cycles])

        let withoutDetails = presentation(snapshot(charging: true, onAC: true, toFull: 30)).facts.map(\.kind)
        #expect(withoutDetails == [.time, .source])

        let partial = BatteryDetails(cycleCount: 5, batteryWatts: 0.2)
        #expect(presentation(snapshot(), details: partial).facts.map(\.kind) == [.time, .source, .cycles])
        #expect(presentation(snapshot(), details: BatteryDetails(healthPercent: 88)).facts.map(\.kind) == [.time, .source, .capacity])
    }

    // MARK: Accessibility

    @Test func theBatteryReadsOutTheLevelStateAndTime() {
        #expect(presentation(snapshot(80, charging: true, onAC: true, toFull: 80)).accessibilityLabel
            == "Pin 80 phần trăm, đang sạc, đầy sau 1 giờ 20 phút")
        #expect(presentation(snapshot(80, charging: true, onAC: true)).accessibilityLabel
            == "Pin 80 phần trăm, đang sạc")
        #expect(presentation(snapshot(80, onAC: true)).accessibilityLabel
            == "Pin 80 phần trăm, đã cắm sạc, không sạc thêm")
        #expect(presentation(snapshot(55, toEmpty: 190)).accessibilityLabel
            == "Pin 55 phần trăm, dùng pin, còn khoảng 3 giờ 10 phút")
        #expect(presentation(snapshot(55)).accessibilityLabel
            == "Pin 55 phần trăm, dùng pin")
    }

    @Test func eachColumnReadsAsLabelAndValue() {
        let details = BatteryDetails(cycleCount: 312, healthPercent: 92, batteryWatts: -12, adapterWatts: 96)
        let facts = presentation(snapshot(55, toEmpty: 190), details: details).facts
        #expect(facts.map(\.accessibilityLabel) == [
            "Dùng pin: Còn khoảng 3 giờ 10 phút", "Nguồn: Pin", "Đang tiêu thụ: 12 W", "Dung lượng tối đa: 92%", "Chu kỳ sạc: 312",
        ])
    }
}

private extension BatteryPresentation {
    func fact(_ kind: BatteryFact.Kind) -> BatteryFact? { facts.first { $0.kind == kind } }
}
