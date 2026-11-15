import CoreGraphics
import Foundation
import Testing
@testable import SystemActivitiesModule

private nonisolated final class SafeRecorder: @unchecked Sendable {
    private let lock = NSLock()
    var recordedDisplays: [CGDirectDisplayID] = []
    var recordedTables: [[CGGammaValue]] = []
    var setterResult: CGError = .success

    func record(display: CGDirectDisplayID, table: [CGGammaValue]) -> CGError {
        lock.withLock {
            recordedDisplays.append(display)
            recordedTables.append(table)
            return setterResult
        }
    }
}

@Suite struct ExternalDisplayGammaBrightnessTests {
    @Test func returnsNilWhenNoExternalDisplaysActive() {
        let control = ExternalDisplayGammaBrightness(
            activeDisplays: { [] },
            setGammaTable: { _, _, _, _ in .success },
            restoreGamma: {}
        )
        #expect(control.read() == nil)
        #expect(!control.write(0.8))
    }

    @Test func readsDefaultLevelForNewExternalDisplay() {
        let control = ExternalDisplayGammaBrightness(
            activeDisplays: { [101] },
            setGammaTable: { _, _, _, _ in .success },
            restoreGamma: {}
        )
        #expect(control.read() == 1.0)
    }

    @Test func writeClampsBrightnessToMinSafeFloor() {
        let recorder = SafeRecorder()
        let control = ExternalDisplayGammaBrightness(
            activeDisplays: { [202] },
            setGammaTable: { display, red, _, _ in
                recorder.record(display: display, table: red)
            },
            restoreGamma: {}
        )

        // Write 0.0: should be clamped to 0.05
        let ok = control.write(0.0)
        #expect(ok)
        #expect(control.read() == 0.05)

        // Check the generated gamma table: table[255] should be roughly 0.05
        #expect(recorder.recordedTables.count == 1)
        let table = recorder.recordedTables[0]
        #expect(table.count == 256)
        #expect(table[0] == 0.0)
        #expect(abs(table[255] - 0.05) < 0.001)
    }

    @Test func writeClampsBrightnessToMaxSafeLevel() {
        let recorder = SafeRecorder()
        let control = ExternalDisplayGammaBrightness(
            activeDisplays: { [303] },
            setGammaTable: { display, red, _, _ in
                recorder.record(display: display, table: red)
            },
            restoreGamma: {}
        )

        let ok = control.write(1.5)
        #expect(ok)
        #expect(control.read() == 1.0)

        #expect(recorder.recordedTables.count == 1)
        let table = recorder.recordedTables[0]
        #expect(abs(table[255] - 1.0) < 0.001)
    }

    @Test func refreshClearsCachedLevels() {
        let control = ExternalDisplayGammaBrightness(
            activeDisplays: { [404] },
            setGammaTable: { _, _, _, _ in .success },
            restoreGamma: {}
        )

        #expect(control.write(0.6))
        #expect(control.read() == 0.6)

        control.refresh()
        // After refresh, the cache is cleared and defaults back to 1.0 for the active display
        #expect(control.read() == 1.0)
    }
}
