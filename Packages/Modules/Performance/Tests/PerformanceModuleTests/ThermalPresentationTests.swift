import Testing
@testable import PerformanceModule

@Suite struct ThermalPresentationTests {
    @Test func theToneFollowsTheTemperature() {
        #expect(Tone(celsius: 45) == .normal)
        #expect(Tone(celsius: 69.9) == .normal)
        #expect(Tone(celsius: 70) == .caution)
        #expect(Tone(celsius: 89.9) == .caution)
        #expect(Tone(celsius: 90) == .critical)
        #expect(Tone(celsius: 104) == .critical)
    }

    @Test func degreesAreWholeNumbersWithoutTheLetter() {
        #expect(ThermalFormat.degrees(84.4) == "84°")
        #expect(ThermalFormat.degrees(84.5) == "85°")
        #expect(ThermalFormat.degrees(nil) == "—")
    }

    @Test func rpmIsAWholeNumber() {
        #expect(ThermalFormat.rpm(5230.2017) == "5230")
        #expect(ThermalFormat.rpm(0) == "0")
    }

    @Test func thisMacShowsTheDieTemperaturesAndBothFans() {
        let snapshot = ThermalSnapshot(
            cpu: 80.4, gpu: 69.1,
            fans: [
                FanReading(index: 0, rpm: 5230.2, minRPM: 1200, maxRPM: 5779),
                FanReading(index: 1, rpm: 5656.2, minRPM: 1200, maxRPM: 6241),
            ]
        )
        let presentation = ThermalPresentation(snapshot)
        #expect(presentation.soc == "80°")
        #expect(presentation.cpu == "80°")
        #expect(presentation.gpu == "69°")
        #expect(presentation.tone == .caution)
        #expect(presentation.fans.map(\.title) == ["Quạt 1", "Quạt 2"])
        #expect(presentation.fans.map(\.rpm) == ["5230", "5656"])
        #expect(presentation.fans.map(\.range) == ["1200–5779", "1200–6241"])
        #expect(abs(presentation.fans[0].fraction - (5230.2 - 1200) / (5779 - 1200)) < 1e-9)
    }

    @Test func theToneIsThatOfTheSoC() {
        #expect(ThermalPresentation(ThermalSnapshot(cpu: 60, gpu: 92, fans: [])).tone == .critical)
    }

    @Test func nothingReadYetShowsDashesAndNoTone() {
        let presentation = ThermalPresentation(nil)
        #expect(presentation.soc == "—" && presentation.cpu == "—" && presentation.gpu == "—")
        #expect(presentation.tone == nil)
        #expect(presentation.fans.isEmpty)
        #expect(presentation.accessibilityLabel == "Chưa đọc được nhiệt độ")
    }

    @Test func aDieThatIsUnknownShowsADash() {
        let presentation = ThermalPresentation(ThermalSnapshot(cpu: 71, gpu: nil, fans: []))
        #expect(presentation.gpu == "—")
        #expect(presentation.soc == "71°")
    }

    @Test func theLabelsReadAsSentences() {
        let snapshot = ThermalSnapshot(cpu: 80.4, gpu: 69.1, fans: [FanReading(index: 0, rpm: 5230, minRPM: 1200, maxRPM: 5779)])
        let presentation = ThermalPresentation(snapshot)
        #expect(presentation.accessibilityLabel == "Nhiệt độ SoC 80 độ, CPU 80 độ, GPU 69 độ")
        #expect(presentation.fans[0].accessibilityLabel == "Quạt 1: 5230 vòng/phút, từ 1200 đến 5779")
    }

    @Test func aLabelLeavesOutADieThatIsUnknown() {
        let presentation = ThermalPresentation(ThermalSnapshot(cpu: 71, gpu: nil, fans: []))
        #expect(presentation.accessibilityLabel == "Nhiệt độ SoC 71 độ, CPU 71 độ")
    }
}
