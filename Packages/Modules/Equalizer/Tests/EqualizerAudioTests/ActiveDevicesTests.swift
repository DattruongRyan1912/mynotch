import Foundation
import Testing
@testable import EqualizerAudio

@Suite struct ActiveDevicesTests {
    private let me: pid_t = 100

    private func process(_ pid: pid_t, running: Bool = true, on devices: [String]) -> ProcessOutput {
        ProcessOutput(pid: pid, isRunningOutput: running, deviceUIDs: devices)
    }

    @Test func aPlayingProcessMakesItsDeviceActive() {
        #expect(ActiveDevices.uids(in: [process(7, on: ["A"])], excludingPID: me) == ["A"])
    }

    @Test func devicesOfSeveralProcessesAreCombined() {
        let processes = [process(7, on: ["A"]), process(8, on: ["B", "A"]), process(9, on: ["C"])]
        #expect(ActiveDevices.uids(in: processes, excludingPID: me) == ["A", "B", "C"])
    }

    @Test func aProcessThatIsNotPlayingDoesNotCount() {
        #expect(ActiveDevices.uids(in: [process(7, running: false, on: ["A"])], excludingPID: me).isEmpty)
    }

    @Test func myOwnReplayDoesNotKeepADeviceActive() {
        // MyNotch plays on A as soon as its pipeline runs; if that counted, A would never go quiet.
        let processes = [process(me, on: ["A"]), process(7, on: ["B"])]
        #expect(ActiveDevices.uids(in: processes, excludingPID: me) == ["B"])
    }

    @Test func noProcessesMeansNoDevices() {
        #expect(ActiveDevices.uids(in: [], excludingPID: me).isEmpty)
    }
}
