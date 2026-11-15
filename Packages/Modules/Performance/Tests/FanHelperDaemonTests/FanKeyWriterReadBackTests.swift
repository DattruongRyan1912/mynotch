import FanHelperKit
import Foundation
import Testing
@testable import FanHelperDaemon

/// What the writer does between a write that the SMC accepted and a key that reads back as written: all with a fake SMC and a fake
/// clock that the writer's own waits move.
@Suite struct FanKeyWriterReadBackTests {
    struct Setup {
        let clock = FakeClock()
        let sleeps = SleepLog()
        let log = LogLines()
        let smc: FakeFanSMC
        let writer: FanKeyWriter

        init(fans: Int = 2, configure: (FakeFanSMC) -> Void = { _ in }) {
            let clock = clock
            smc = FakeFanSMC(fans: fans, clock: { clock.seconds })
            configure(smc)
            let log = log
            writer = try! FanKeyWriter(channel: smc, log: { log.add($0) }, timing: .fake(clock, sleeps: sleeps))
        }
    }

    // MARK: Waiting for a mode that comes late

    @Test func aModeThatTheFirmwareAppliesAfterAWhileIsWaitedFor() {
        let setup = Setup { $0.applyModeOn(after: 0.15) }
        let report = setup.writer.setManual([0], true)
        #expect(report.isOK && report.readBackMS == [0: 150])
        #expect(setup.log.all == ["F0Md=1 read back after 150 ms (0,0,0,1)"])
        #expect(setup.sleeps.durations == [0.05, 0.05, 0.05], "it looked every 50 ms")
        #expect(setup.smc.writes == [.mode(0, 1)], "the key was written once")
    }

    @Test func aModeThatIsNeverAppliedIsAnErrorAfterASecondAndIsNotWrittenAgain() {
        let setup = Setup { $0.neverApply("F0Md") }
        let report = setup.writer.setManual([0], true)
        #expect(report.failures == [FanWriteFailure(fan: 0, error: .readBackDiffers("F0Md"))])
        #expect(setup.log.all == ["F0Md=1 never read back in 1000 ms (0×20)"])
        #expect(setup.smc.writes == [.mode(0, 1)], "no retry write")
        #expect(setup.sleeps.durations.count == 19 && setup.sleeps.durations.allSatisfy { $0 == 0.05 })
        #expect(setup.clock.seconds - 10_000 < 1, "it did not wait longer than the second it was given")
    }

    @Test func aTargetThatReadsBackAtOnceNeedsNoWait() {
        let setup = Setup()
        let report = setup.writer.setTargets([FanTarget(fan: 1, rpm: 4000)])
        #expect(report.isOK && report.readBackMS == [1: 0])
        #expect(setup.sleeps.durations.isEmpty)
        #expect(setup.log.all == ["F1Tg=4000 read back after 0 ms (4000)"])
    }

    // MARK: Every key is written before any is waited for

    @Test func theModesAreWrittenForEveryFanBeforeAnyOfThemIsWaitedFor() {
        // A mode that sticks only once every fan's is set could never read back if the first were waited for before the second was written.
        let setup = Setup { $0.modesStickOnlyWhenEveryFanIsSet() }
        let report = setup.writer.setManual([0, 1], true)
        #expect(report.isOK)
        #expect(setup.smc.writes == [.mode(0, 1), .mode(1, 1)])
        #expect(setup.sleeps.durations.isEmpty)
        #expect(setup.log.all == ["F0Md=1 read back after 0 ms (1)", "F1Md=1 read back after 0 ms (1)"])

        let alone = Setup { $0.modesStickOnlyWhenEveryFanIsSet() }
        #expect(alone.writer.setManual([0], true).isOK == false, "one fan's mode alone does not stick on such a chip")
    }

    @Test func severalKeysAreWaitedForTogetherSoTheWaitIsOneSecondAndNotOnePerKey() {
        let setup = Setup { $0.neverApply("F0Md", "F1Md") }
        let report = setup.writer.setManual([0, 1], true)
        #expect(report.failures.map(\.fan) == [0, 1])
        #expect(setup.log.all == ["F0Md=1 never read back in 1000 ms (0×20)", "F1Md=1 never read back in 1000 ms (0×20)"])
        #expect(setup.clock.seconds - 10_000 < 1)
    }

    @Test func aKeyThatFailsDoesNotStopTheOthersFromBeingWrittenAndRead() {
        let setup = Setup { $0.refuse("F0Md") }
        let report = setup.writer.setManual([0, 1], true)
        #expect(report.failures == [FanWriteFailure(fan: 0, error: .refused("F0Md", 0x82))])
        #expect(setup.smc.writes == [.mode(0, 1), .mode(1, 1)], "a restore must reach every fan")
        #expect(report.readBackMS == [1: 0])
    }

    @Test func aRefusalIsLookedAtOnceAndNotWaitedFor() {
        let setup = Setup { $0.refuse("F0Md", code: 0x82) }
        let report = setup.writer.setManual([0], true)
        #expect(report.failures.first?.error == .refused("F0Md", 0x82))
        #expect(setup.sleeps.durations.isEmpty)
        #expect(setup.smc.writes.count == 1)
    }

    @Test func aWriteTheSMCAnswersWithAnErrorButAppliedIsAcceptedAndLogged() {
        let setup = Setup { $0.refuse("F0Tg", code: 0x87, appliesAnyway: true) }
        #expect(setup.writer.setTargets([FanTarget(fan: 0, rpm: 3000)]).isOK)
        #expect(setup.log.all == ["F0Tg=3000 read back after 0 ms (3000), though the SMC answered result 135"])
    }

    // MARK: A target the firmware rewrites while the fan is automatic

    @Test func aTargetWrittenWhileTheFanIsAutomaticIsRewrittenByTheFirmwareAndNeverReadsBack() {
        let setup = Setup { $0.firmwareRewritesTheTargetWhileAutomatic() }
        let report = setup.writer.setTargets([FanTarget(fan: 0, rpm: 3500)])
        #expect(report.failures == [FanWriteFailure(fan: 0, error: .readBackDiffers("F0Tg"))])
        #expect(setup.log.all == ["F0Tg=3500 never read back in 1000 ms (2000×20)"])
    }

    @Test func theSameTargetWrittenOnceTheModeHasTakenStaysPut() {
        let setup = Setup { $0.firmwareRewritesTheTargetWhileAutomatic() }
        #expect(setup.writer.setManual([0], true).isOK)
        #expect(setup.writer.setTargets([FanTarget(fan: 0, rpm: 3500)]).isOK)
    }

    // MARK: Before anything is written

    @Test func aFanThatDoesNotExistOrASpeedThatIsNotANumberStopsTheWholeBatchBeforeAnyWrite() {
        let setup = Setup()
        #expect(setup.writer.setManual([0, 5], true).failures == [FanWriteFailure(fan: 5, error: .noSuchFan)])
        #expect(setup.writer.setTargets([FanTarget(fan: 0, rpm: 3000), FanTarget(fan: 1, rpm: .nan)]).failures.first?.error == .notAFiniteSpeed)
        #expect(setup.writer.setTargets([FanTarget(fan: 9, rpm: 3000)]).failures.first?.error == .noSuchFan)
        #expect(setup.smc.writes.isEmpty)
    }

    // MARK: The log

    @Test func theReadingsAreWrittenShortAndEveryLineIsNumbersOnly() {
        #expect(FanKeyWriter.describe([0, 0, 0, 1]) == "0,0,0,1")
        #expect(FanKeyWriter.describe(Array(repeating: 0, count: 20)) == "0×20")
        #expect(FanKeyWriter.describe([1, 1, 1, 1, 2, -1]) == "1×4,2,-1")
        #expect(FanKeyWriter.describe([5]) == "5")

        let lines = LogLines()
        let setups = [
            Setup { $0.applyModeOn(after: 0.15) }, Setup { $0.neverApply("F0Md", "F1Md") }, Setup { $0.firmwareRewritesTheTargetWhileAutomatic() },
        ]
        for setup in setups {
            _ = setup.writer.setManual([0, 1], true)
            _ = setup.writer.setTargets([FanTarget(fan: 0, rpm: 3000.4), FanTarget(fan: 1, rpm: 3100)])
            _ = setup.writer.setManual([0, 1], false)
            for line in setup.log.all { lines.add(line) }
        }
        let shape = /^F[0-7](Md|md|Tg)=\d+ (read back after \d+ ms|never read back in \d+ ms) \(-?\d+(×\d+)?(,-?\d+(×\d+)?)*\)$/
        #expect(lines.all.count >= 9)
        for line in lines.all { #expect(line.wholeMatch(of: shape) != nil, "\(line)") }
    }
}
