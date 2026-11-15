import FanHelperKit
import Foundation
import Testing
@testable import FanHelperDaemon

/// The command for every fan at once, over fake SMCs that behave the ways a firmware may: the mode applied after a while or never,
/// only once every fan's is set, a target rewritten while a fan is automatic, an error from a write. Nothing here reaches a real SMC.
@Suite struct FanControllerEveryFanTests {
    static let all = FanHelperResult.allFans

    // MARK: What is written, and in what order

    @Test func everyFansModeIsWrittenFirstAndThenEveryFansTarget() {
        let rig = Rig(actual: 2000)
        let result = rig.controller.setForced(fan: Self.all, rpm: 3500)
        #expect(result.ok && result.state == .forced && result.appliedRPM == 3500)
        #expect(result.leaseSeconds == FanController.leaseSeconds)
        #expect(rig.writes == [.mode(0, 1), .mode(1, 1), .target(0, 3500), .target(1, 3500)])
        #expect(rig.controller.isHoldingFans)
    }

    @Test func theSameSpeedGoesToEveryFanHeldToItsOwnRange() {
        let rig = Rig(actual: 1000)
        let high = rig.controller.setForced(fan: Self.all, rpm: 6000)
        #expect(rig.smc.target(fan: 0) == 5779 && rig.smc.target(fan: 1) == 6000, "fan 0's maximum is 5779, fan 1's is 6241")
        #expect(high.detail.contains("clamped") && high.appliedRPM == 5889.5)
        _ = rig.controller.setForced(fan: Self.all, rpm: 9000)
        #expect(rig.smc.target(fan: 0) == 5779 && rig.smc.target(fan: 1) == 6241)
        _ = rig.controller.setForced(fan: Self.all, rpm: 100)
        #expect(rig.smc.target(fan: 0) == 1200 && rig.smc.target(fan: 1) == 1200, "and not below the minimum")
        #expect(rig.writes.filter { $0.key.hasSuffix("Tg") }.allSatisfy { write in
            (SMCValueForTests.float(write.bytes) ?? 0) >= 1200 && (SMCValueForTests.float(write.bytes) ?? 0) <= 6241
        })
    }

    @Test func eachFanHasItsOwnNeverBelowAppleBaselineAndAFanAppleDrivesFasterIsHeldAtAppleSpeed() {
        let rig = Rig(actual: 2000)
        rig.smc.setActual(4000, fan: 1)
        let result = rig.controller.setForced(fan: Self.all, rpm: 3500)
        #expect(rig.writes == [.mode(0, 1), .mode(1, 1), .target(0, 3500), .target(1, 4000)], "every mode is set, fan 1 at what Apple was doing")
        #expect(result.ok && result.state == .forced && result.appliedRPM == 3750)
    }

    @Test func whenAppleIsFasterOnEveryFanNothingIsWrittenAndTheFansStayAutomatic() {
        let rig = Rig(actual: 4000)
        let result = rig.controller.setForced(fan: Self.all, rpm: 3000)
        #expect(result.ok && result.state == .automatic && result.appliedRPM == -1)
        #expect(result.detail == "fan 0: Apple's own speed is higher, fan 1: Apple's own speed is higher")
        #expect(rig.writes.isEmpty && rig.controller.isHoldingFans == false)
    }

    @Test func aFloorForEveryFanIsRefusedAndNothingIsWritten() {
        let rig = Rig()
        let result = rig.controller.setFloor(fan: Self.all, rpm: 3000)
        #expect(result.ok == false && result.detail == "no such fan")
        #expect(rig.writes.isEmpty)
    }

    @Test func theOneFanFormKeepsWorking() {
        let rig = Rig(actual: 2000)
        let result = rig.controller.setForced(fan: 1, rpm: 3200)
        #expect(result.ok && result.state == .forced && result.appliedRPM == 3200)
        #expect(rig.writes == [.mode(1, 1), .target(1, 3200)])
    }

    // MARK: Renewals

    @Test func aRenewalDoesNotWriteTheModesAgainAndRenewsTheLease() {
        let rig = Rig(actual: 2000)
        _ = rig.controller.setForced(fan: Self.all, rpm: 3500)
        rig.clock.advance(10)
        rig.smc.clearWrites()
        let again = rig.controller.setForced(fan: Self.all, rpm: 3500)
        #expect(rig.writes.isEmpty, "the modes read 1 and the targets are what was asked: nothing to write")
        #expect(again.ok && again.state == .forced && again.leaseSeconds == 15 && again.modeReadBackMS == -1)
        rig.clock.advance(6)
        rig.controller.tick()
        #expect(rig.writes.isEmpty && rig.controller.isHoldingFans, "16 s after the first command, 6 s after the renewal")
    }

    @Test func aRenewalWritesATargetOnlyWhenItDiffers() {
        let rig = Rig(actual: 2000)
        _ = rig.controller.setForced(fan: Self.all, rpm: 3500)
        rig.smc.clearWrites()
        _ = rig.controller.setForced(fan: Self.all, rpm: 3800)
        #expect(rig.writes == [.target(0, 3800), .target(1, 3800)])
    }

    @Test func aModeThatNoLongerReadsOneIsWrittenAgainAndOnlyThatOne() {
        let rig = Rig(actual: 2000)
        _ = rig.controller.setForced(fan: Self.all, rpm: 3500)
        rig.smc.setMode(0, fan: 1)
        rig.smc.clearWrites()
        let result = rig.controller.setForced(fan: Self.all, rpm: 3500)
        #expect(result.ok)
        #expect(rig.writes == [.mode(1, 1)])
    }

    // MARK: (a) A mode the firmware applies after a while

    @Test func aModeAppliedAfterAWhileIsWaitedForAndTheTargetsComeAfterIt() {
        let rig = Rig(actual: 2000) { $0.applyModeOn(after: 0.15) }
        let result = rig.controller.setForced(fan: Self.all, rpm: 3500)
        #expect(result.ok && result.state == .forced && result.modeReadBackMS == 150)
        #expect(rig.writes == [.mode(0, 1), .mode(1, 1), .target(0, 3500), .target(1, 3500)])
        #expect(rig.logs.all.contains("F0Md=1 read back after 150 ms (0,0,0,1)") && rig.logs.all.contains("F1Md=1 read back after 150 ms (0,0,0,1)"))
        #expect(rig.sleeps.durations == [0.05, 0.05, 0.05], "the modes were waited for together, once")
        #expect(rig.smc.target(fan: 0) == 3500 && rig.smc.target(fan: 1) == 3500)
    }

    // MARK: (b) A mode that is never applied

    @Test func aModeThatIsNeverAppliedGivesEveryFanBackAndNoTargetIsWritten() {
        let rig = Rig(actual: 2000) { $0.neverApply("F0Md", "F1Md") }
        let result = rig.controller.setForced(fan: Self.all, rpm: 3500)
        #expect(result.ok == false && result.state == .automatic && result.detail == "F0Md does not read back as written")
        #expect(rig.writes == [.mode(0, 1), .mode(1, 1), .mode(0, 0), .mode(1, 0)], "each key once, no target, then back to automatic")
        #expect(rig.logs.all.contains("F0Md=1 never read back in 1000 ms (0×20)") && rig.logs.all.contains("F1Md=1 never read back in 1000 ms (0×20)"))
        #expect(rig.smc.mode(fan: 0) == 0 && rig.smc.mode(fan: 1) == 0)
    }

    // MARK: (c) Modes that stick only once every fan's is set

    @Test func modesThatStickOnlyOnceEveryFansIsSetWorkForEveryFanAtOnce() {
        let rig = Rig(actual: 2000) { $0.modesStickOnlyWhenEveryFanIsSet() }
        let result = rig.controller.setForced(fan: Self.all, rpm: 3500)
        #expect(result.ok && result.state == .forced && result.modeReadBackMS == 0)
        #expect(rig.writes == [.mode(0, 1), .mode(1, 1), .target(0, 3500), .target(1, 3500)])
        #expect(rig.smc.mode(fan: 0) == 1 && rig.smc.mode(fan: 1) == 1)
    }

    @Test func onOneFanAloneSuchAChipDoesNotTakeTheModeAndTheFanIsGivenBack() {
        let rig = Rig(actual: 2000) { $0.modesStickOnlyWhenEveryFanIsSet() }
        let result = rig.controller.setForced(fan: 0, rpm: 3500)
        #expect(result.ok == false && result.state == .automatic)
        #expect(rig.smc.mode(fan: 0) == 0)
    }

    // MARK: (d) A target the firmware rewrites while a fan is automatic

    @Test func aTargetThatTheFirmwareRewritesWhileAutomaticSticksOnceTheModesAreSetFirst() {
        let rig = Rig(actual: 2000) { $0.firmwareRewritesTheTargetWhileAutomatic() }
        let result = rig.controller.setForced(fan: Self.all, rpm: 3500)
        #expect(result.ok && result.state == .forced)
        #expect(rig.smc.target(fan: 0) == 3500 && rig.smc.target(fan: 1) == 3500)
    }

    @Test func aFloorOnSuchAFirmwareIsRewrittenAndReportedNotHonoured() {
        let rig = Rig(actual: 2000) { $0.firmwareRewritesTheTargetWhileAutomatic() }
        let result = rig.controller.setFloor(fan: 0, rpm: 3500)
        #expect(result.ok == false && result.detail == "F0Tg does not read back as written")
        #expect(rig.logs.all.contains("F0Tg=3500 never read back in 1000 ms (2000×20)"))
    }

    // MARK: (e) A write that returns an SMC error

    @Test func aModeTheSMCRefusesGivesEveryFanBackAndNoTargetIsWritten() {
        let rig = Rig(actual: 2000) { $0.refuse("F1Md") }
        let result = rig.controller.setForced(fan: Self.all, rpm: 3500)
        #expect(result.ok == false && result.state == .automatic && result.detail == "the SMC refused F1Md (0x82)")
        #expect(rig.writes == [.mode(0, 1), .mode(1, 1), .mode(0, 0), .mode(1, 0)])
        #expect(rig.smc.mode(fan: 0) == 0 && rig.smc.mode(fan: 1) == 0, "fan 0's mode, which did take, was undone")
    }

    @Test func aTargetTheSMCRefusesGivesEveryFanBack() {
        let rig = Rig(actual: 2000) { $0.refuse("F1Tg") }
        let result = rig.controller.setForced(fan: Self.all, rpm: 3500)
        #expect(result.ok == false && result.detail == "the SMC refused F1Tg (0x82)")
        #expect(rig.smc.mode(fan: 0) == 0 && rig.smc.mode(fan: 1) == 0)
    }

    // MARK: (f) A mode that reads 1 only after the helper gave up

    @Test func everyFanThatMayHaveBeenWrittenIsGivenBackEvenOneTheHelperNeverSawTake() {
        // F0Md is refused, but the batch goes on: F1Md was written, so F1's mode is to be given back as well.
        let rig = Rig(actual: 2000) { $0.refuse("F0Md") }
        _ = rig.controller.setForced(fan: Self.all, rpm: 3500)
        #expect(rig.writes.contains(.mode(1, 1)) && rig.writes.contains(.mode(1, 0)))
        #expect(rig.smc.mode(fan: 1) == 0)
    }

    @Test func aModeThatComesOnAfterTheHelperGaveUpIsGivenBackAtTheNextTick() {
        // Applied 1.5 s after the write, while the helper waits 1 s and gives up; the restore's own write of 0 is at once, so a late 1
        // lands after it and leaves the fan manual with nobody holding it unless the helper looks again.
        let rig = Rig(actual: 2000) { $0.applyModeOn(after: 1.5) }
        let result = rig.controller.setForced(fan: Self.all, rpm: 3500)
        #expect(result.ok == false)
        #expect(rig.writes == [.mode(0, 1), .mode(1, 1), .mode(0, 0), .mode(1, 0)], "the restore wrote 0 for every fan that was written")
        #expect(rig.smc.mode(fan: 0) == 0, "for now")
        #expect(rig.controller.isHoldingFans, "it is still watching them")

        rig.clock.advance(0.6)
        #expect(rig.smc.mode(fan: 0) == 1 && rig.smc.mode(fan: 1) == 1, "the late modes landed")
        rig.smc.clearWrites()
        rig.controller.tick()
        #expect(rig.writes == [.mode(0, 0), .mode(1, 0)])
        #expect(rig.smc.mode(fan: 0) == 0 && rig.smc.mode(fan: 1) == 0)
        #expect(rig.logs.all.contains("fan 0 back to automatic: its mode came on late"))
    }

    @Test func theWatchForALateModeEndsWithTheLeaseAndTheHelperMayLeaveThen() {
        let rig = Rig(actual: 2000) { $0.neverApply("F0Md", "F1Md") }
        _ = rig.controller.setForced(fan: Self.all, rpm: 3500)
        #expect(rig.controller.isHoldingFans)
        rig.clock.advance(FanController.leaseSeconds + 1)
        rig.controller.tick()
        #expect(rig.controller.isHoldingFans == false)
    }

    @Test func aFanTheWatchSeesInAnotherToolsHandsIsLeftAlone() {
        let rig = Rig(actual: 2000) { $0.applyModeOn(after: 1.5) }
        _ = rig.controller.setForced(fan: Self.all, rpm: 3500)
        rig.otherTool.current = true
        rig.clock.advance(0.6)
        rig.smc.clearWrites()
        rig.controller.tick()
        #expect(rig.writes.isEmpty)
    }

    // MARK: The lease, the guard and giving back, for every fan

    @Test func withoutARenewalEveryFanGoesBackToAutomaticAfterFifteenSeconds() {
        let rig = Rig(actual: 2000)
        _ = rig.controller.setForced(fan: Self.all, rpm: 3500)
        rig.smc.clearWrites()
        rig.clock.advance(14.9)
        rig.controller.tick()
        #expect(rig.writes.isEmpty)
        rig.clock.advance(0.2)
        rig.controller.tick()
        #expect(rig.writes == [.mode(0, 0), .mode(1, 0)])
        #expect(rig.controller.isHoldingFans == false)
    }

    @Test func atNinetyFiveDegreesEveryFanGoesToItsOwnMaximumWhateverWasAsked() {
        let rig = Rig(actual: 2000, temperature: 97)
        let result = rig.controller.setForced(fan: Self.all, rpm: 3000)
        #expect(result.ok && result.state == .forced && result.detail.contains("heat guard"))
        #expect(rig.writes == [.mode(0, 1), .mode(1, 1), .target(0, 5779), .target(1, 6241)])
        #expect(result.appliedRPM == 6010)
    }

    @Test func theGuardRaisingHeldFansWritesTheirTargetsAndNotTheModesAgain() {
        let rig = Rig(actual: 2000, temperature: 60)
        _ = rig.controller.setForced(fan: Self.all, rpm: 3000)
        rig.temperature.current = 96
        rig.smc.clearWrites()
        rig.controller.tick()
        #expect(rig.writes == [.target(0, 5779), .target(1, 6241)])
    }

    @Test func theGuardHoldsEveryFanModeFirstOnAChipThatTakesTheModesOnlyTogether() {
        let rig = Rig(actual: 2000, temperature: 60) { $0.modesStickOnlyWhenEveryFanIsSet() }
        _ = rig.controller.setForced(fan: Self.all, rpm: 3000)
        rig.clock.advance(1)
        rig.temperature.current = 96
        rig.controller.tick()
        #expect(rig.smc.target(fan: 0) == 5779 && rig.smc.target(fan: 1) == 6241)
        #expect(rig.smc.mode(fan: 0) == 1 && rig.smc.mode(fan: 1) == 1)
    }

    @Test func askedToGoAutomaticEveryFanIsGivenBackInOneBatch() {
        let rig = Rig(actual: 2000)
        _ = rig.controller.setForced(fan: Self.all, rpm: 3500)
        rig.smc.clearWrites()
        let result = rig.controller.setAuto(fan: Self.all)
        #expect(result.ok && result.state == .automatic)
        #expect(rig.writes == [.mode(0, 0), .mode(1, 0)])
        #expect(rig.logs.all.contains("fan 0 back to automatic: asked") && rig.logs.all.contains("fan 1 back to automatic: asked"))
    }

    // MARK: The log

    @Test func theLogOfACommandForEveryFanHasOnlyTheWritesAndNoTemperature() {
        let rig = Rig(actual: 2000, temperature: 61.5) { $0.applyModeOn(after: 0.1) }
        _ = rig.controller.setForced(fan: Self.all, rpm: 3200.4)
        rig.clock.advance(16)
        rig.controller.tick()
        let shape = /^F[0-7](Md|Tg)=\d+ read back after \d+ ms \(-?\d+(×\d+)?(,-?\d+(×\d+)?)*\)$/
        let writes = rig.logs.all.filter { !$0.hasPrefix("fan ") }
        #expect(writes.count == 6, "two modes and two targets, then the two modes back to automatic, each logged once")
        for line in writes { #expect(line.wholeMatch(of: shape) != nil, "\(line)") }
        #expect(rig.logs.all.allSatisfy { !$0.contains("61") }, "no temperature in the log")
    }
}
