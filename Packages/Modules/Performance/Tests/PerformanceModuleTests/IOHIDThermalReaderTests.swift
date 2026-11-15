import Foundation
import Testing
@testable import PerformanceModule

@Suite struct IOHIDThermalReaderTests {
    @Test func sensorCategorizationCorrectlyMapsNames() {
        #expect(IOHIDThermalReader.categorize(sensorName: "PMU tdie1") == .cpu)
        #expect(IOHIDThermalReader.categorize(sensorName: "PMU tdie10") == .cpu)
        #expect(IOHIDThermalReader.categorize(sensorName: "pACC-Cluster") == .cpu)
        #expect(IOHIDThermalReader.categorize(sensorName: "eACC-Cluster") == .cpu)
        #expect(IOHIDThermalReader.categorize(sensorName: "P-Core 1 Temp") == .cpu)
        #expect(IOHIDThermalReader.categorize(sensorName: "Tp01") == .cpu)

        #expect(IOHIDThermalReader.categorize(sensorName: "PMU TP0s") == .gpu)
        #expect(IOHIDThermalReader.categorize(sensorName: "PMU TP1g") == .gpu)
        #expect(IOHIDThermalReader.categorize(sensorName: "PMU TP2s") == .gpu)
        #expect(IOHIDThermalReader.categorize(sensorName: "PMU TP3g") == .gpu)
        #expect(IOHIDThermalReader.categorize(sensorName: "GPU cluster 0") == .gpu)
        #expect(IOHIDThermalReader.categorize(sensorName: "Tg01") == .gpu)

        #expect(IOHIDThermalReader.categorize(sensorName: "PMU tcal") == .hotspot)
        #expect(IOHIDThermalReader.categorize(sensorName: "SoC Hotspot") == .hotspot)
        #expect(IOHIDThermalReader.categorize(sensorName: "ANE MTR") == .hotspot)
        #expect(IOHIDThermalReader.categorize(sensorName: "Neural Engine") == .hotspot)

        #expect(IOHIDThermalReader.categorize(sensorName: "NAND CH0 temp") == .ssd)
        #expect(IOHIDThermalReader.categorize(sensorName: "NVMe SSD Temp") == .ssd)

        #expect(IOHIDThermalReader.categorize(sensorName: "gas gauge battery") == .battery)
        #expect(IOHIDThermalReader.categorize(sensorName: "Battery Cell 1") == .battery)

        #expect(IOHIDThermalReader.categorize(sensorName: "PMU tdev5") == .other)
        #expect(IOHIDThermalReader.categorize(sensorName: "Power Board Sensor") == .other)
    }

    @Test func hottestPerCategoryAndSoCAreAccurate() async {
        let mockSensors: [SensorReading] = [
            SensorReading(id: "1", name: "PMU tdie1", temperature: 42.0, category: .cpu),
            SensorReading(id: "2", name: "PMU tdie2", temperature: 48.5, category: .cpu),
            SensorReading(id: "3", name: "PMU TP0s", temperature: 45.0, category: .gpu),
            SensorReading(id: "4", name: "PMU TP1s", temperature: 52.0, category: .gpu),
            SensorReading(id: "5", name: "PMU tcal", temperature: 55.0, category: .hotspot),
            SensorReading(id: "6", name: "NAND CH0 temp", temperature: 36.0, category: .ssd),
            SensorReading(id: "7", name: "gas gauge battery", temperature: 32.5, category: .battery),
        ]

        let fakeSMC = FakeThermalReader(
            ThermalSnapshot(cpu: 40.0, gpu: 41.0, fans: [FanReading(index: 0, rpm: 2500, minRPM: 1200, maxRPM: 5500)])
        )

        let reader = IOHIDThermalReader(
            sensorProvider: { mockSensors },
            smcFallback: fakeSMC
        )

        let snapshot = await reader.read()
        #expect(snapshot != nil)
        #expect(snapshot?.cpu == 48.5)
        #expect(snapshot?.gpu == 52.0)
        #expect(snapshot?.hotspot == 55.0)
        #expect(snapshot?.ssd == 36.0)
        #expect(snapshot?.battery == 32.5)
        #expect(snapshot?.soc == 55.0) // max(48.5, 52.0, 55.0)
        #expect(snapshot?.sensors.count == 7)
        #expect(snapshot?.fans.count == 1)
        #expect(snapshot?.fans[0].rpm == 2500)
    }

    @Test func hybridFallbackUsesSMCOnEmptyIOHIDSensors() async {
        let fakeSMC = FakeThermalReader(
            ThermalSnapshot(cpu: 65.0, gpu: 58.0, fans: [FanReading(index: 0, rpm: 3000, minRPM: 1200, maxRPM: 6000)])
        )

        let reader = IOHIDThermalReader(
            sensorProvider: { [] }, // Empty IOHID (e.g. Intel or unreadable)
            smcFallback: fakeSMC
        )

        let snapshot = await reader.read()
        #expect(snapshot != nil)
        #expect(snapshot?.cpu == 65.0)
        #expect(snapshot?.gpu == 58.0)
        #expect(snapshot?.soc == 65.0)
        #expect(snapshot?.fans.count == 1)
        #expect(snapshot?.sensors.isEmpty == true)
    }

    @Test func shutdownClosesReaderAndDelegatesToSMC() async {
        let fakeSMC = FakeThermalReader()
        let reader = IOHIDThermalReader(
            sensorProvider: { [SensorReading(id: "1", name: "tdie1", temperature: 45.0, category: .cpu)] },
            smcFallback: fakeSMC
        )

        #expect(await reader.isAvailable())
        await reader.shutdown()
        #expect(await reader.isAvailable() == false)
        #expect(await reader.read() == nil)
        #expect(await fakeSMC.shutdowns == 1)
    }
}
