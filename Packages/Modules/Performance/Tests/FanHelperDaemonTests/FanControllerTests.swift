import FanHelperKit
import Foundation
import Testing
@testable import FanHelperDaemon

/// All with a fake SMC, a fake clock and a fake temperature: nothing here can reach a real SMC.
@Suite struct FanControllerTests {
    // MARK: Forcing

    @Test func aSpeedAboveAppleIsWrittenAsManualThenTargetAndLeasedForFifteenSeconds() {
        let rig = Rig(actual: 2000)
        let result = rig.controller.setForced(fan: 0, rpm: 3200)
        #expect(result.ok && result.state == .forced && result.appliedRPM == 3200)
        #expect(result.leaseSeconds == FanController.leaseSeconds)
        #expect(FanController.leaseSeconds == 15)
        #expect(rig.writes == [.mode(0, 1), .target(0, 3200)])
        #expect(rig.controller.isHoldingFans)
    }

    @Test func aSecondCommandForAHeldFanWritesOnlyTheTarget() {
        let rig = Rig(actual: 2000)
        _ = rig.controller.setForced(fan: 0, rpm: 3200)
        rig.smc.clearWrites()
        let result = rig.controller.setForced(fan: 0, rpm: 3600)
        #expect(result.ok && result.appliedRPM == 3600)
        #expect(rig.writes == [.target(0, 3600)])
    }

    @Test func everySpeedIsHeldToTheFansOwnRange() {
        let rig = Rig(actual: 1000)
        let high = rig.controller.setForced(fan: 0, rpm: 9000)
        #expect(high.appliedRPM == 5779 && high.detail.contains("clamped"))
        let other = rig.controller.setForced(fan: 1, rpm: 9000)
        #expect(other.appliedRPM == 6241, "the second fan has its own maximum")
        let low = rig.controller.setForced(fan: 0, rpm: 100)
        #expect(low.appliedRPM == 1200 && low.detail.contains("clamped"))
        #expect(rig.writes.compactMap { write -> Double? in
            guard write.key.hasSuffix("Tg") else { return nil }
            return SMCValueForTests.float(write.bytes)
        }.allSatisfy { $0 >= 1200 && $0 <= 6241 })
    }

    @Test func aFanThatDoesNotExistAndASpeedThatIsNotANumberAreRefusedWithoutAWrite() {
        let rig = Rig()
        for fan in [-1, 2, 9] { #expect(rig.controller.setForced(fan: fan, rpm: 3000).ok == false, "\(fan)") }
        for rpm in [Double.nan, .infinity, -5] { #expect(rig.controller.setForced(fan: 0, rpm: rpm).ok == false, "\(rpm)") }
        #expect(rig.controller.setFloor(fan: 7, rpm: 3000).ok == false)
        #expect(rig.writes.isEmpty)
    }

    // MARK: Never below Apple

    @Test func aSpeedBelowWhatAppleIsDoingLeavesTheFanAutomatic() {
        let rig = Rig(actual: 4000)
        let result = rig.controller.setForced(fan: 0, rpm: 3000)
        #expect(result.ok && result.state == .automatic && result.appliedRPM == -1)
        #expect(result.detail.contains("Apple's own speed is higher"))
        #expect(rig.writes.isEmpty, "nothing was written: Apple is already doing more")
        #expect(rig.controller.isHoldingFans == false)
    }

    @Test func aHeldFanWhoseRequestFallsBelowAppleGoesBackToAutomatic() {
        let rig = Rig(actual: 4000)
        _ = rig.controller.setForced(fan: 0, rpm: 5000)
        rig.smc.clearWrites()
        let result = rig.controller.setForced(fan: 0, rpm: 3500)
        #expect(result.state == .automatic)
        #expect(rig.writes == [.mode(0, 0)])
    }

    @Test func whenTheDieIsHotterThanWhenAppleWasReadTheFanGoesBackToAutomaticToBeLookedAtAgain() {
        let rig = Rig(actual: 2000, temperature: 60)
        _ = rig.controller.setForced(fan: 0, rpm: 3000)
        rig.temperature.current = 65
        rig.smc.clearWrites()
        let result = rig.controller.setForced(fan: 0, rpm: 3500)
        #expect(result.state == .automatic && result.detail.contains("hotter"))
        #expect(rig.writes == [.mode(0, 0)])
        rig.smc.setActual(3400, fan: 0)
        let again = rig.controller.setForced(fan: 0, rpm: 3600)
        #expect(again.state == .forced, "Apple's speed was read afresh and 3600 is above it")
    }

    // MARK: The lease

    @Test func withoutARenewalTheFanGoesBackToAutomaticAfterFifteenSeconds() {
        let rig = Rig(actual: 2000)
        _ = rig.controller.setForced(fan: 0, rpm: 3200)
        rig.smc.clearWrites()
        rig.clock.advance(14.9)
        rig.controller.tick()
        #expect(rig.writes.isEmpty && rig.controller.isHoldingFans)
        rig.clock.advance(0.2)
        rig.controller.tick()
        #expect(rig.writes == [.mode(0, 0)])
        #expect(rig.controller.isHoldingFans == false)
    }

    @Test func sendingTheSameCommandAgainRenewsTheLease() {
        let rig = Rig(actual: 2000)
        _ = rig.controller.setForced(fan: 0, rpm: 3200)
        rig.clock.advance(10)
        let renewed = rig.controller.setForced(fan: 0, rpm: 3200)
        #expect(renewed.leaseSeconds == 15)
        rig.smc.clearWrites()
        rig.clock.advance(6)
        rig.controller.tick()
        #expect(rig.writes.isEmpty, "16 s after the first command, 6 s after the renewal")
        rig.clock.advance(9.5)
        rig.controller.tick()
        #expect(rig.writes == [.mode(0, 0)])
    }

    @Test func eachFanHasItsOwnLease() {
        let rig = Rig(actual: 2000)
        _ = rig.controller.setForced(fan: 0, rpm: 3200)
        rig.clock.advance(10)
        _ = rig.controller.setForced(fan: 1, rpm: 3300)
        rig.smc.clearWrites()
        rig.clock.advance(6)
        rig.controller.tick()
        #expect(rig.writes == [.mode(0, 0)], "fan 0 ran out, fan 1 has 9 s left")
    }

    // MARK: The heat guard

    @Test func atNinetyFiveDegreesAHeldFanGoesToTheMaximumWhateverWasAsked() {
        let rig = Rig(actual: 2000, temperature: 60)
        _ = rig.controller.setForced(fan: 0, rpm: 3000)
        rig.temperature.current = 96
        rig.smc.clearWrites()
        rig.controller.tick()
        #expect(rig.writes == [.target(0, 5779)])
        rig.smc.clearWrites()
        let asked = rig.controller.setForced(fan: 0, rpm: 2000)
        #expect(asked.state == .forced && asked.detail.contains("heat guard"))
        #expect(rig.smc.target(fan: 0) == 5779, "the request for less was not obeyed")
    }

    @Test func theGuardLetsGoBelowNinetyAndNotBefore() {
        let rig = Rig(actual: 2000, temperature: 60)
        _ = rig.controller.setForced(fan: 0, rpm: 3000)
        rig.temperature.current = 96
        rig.controller.tick()
        rig.temperature.current = 92
        let during = rig.controller.setForced(fan: 0, rpm: 3000)
        #expect(during.detail.contains("heat guard"), "92 is between the two: still guarded")
        rig.temperature.current = 59
        rig.controller.tick()
        let after = rig.controller.setForced(fan: 0, rpm: 3000)
        #expect(after.detail.contains("heat guard") == false && after.appliedRPM == 3000)
    }

    @Test func afterAGuardedSpellTheBaselineIsNotTrustedAtTheHotterTemperature() {
        let rig = Rig(actual: 2000, temperature: 60)
        _ = rig.controller.setForced(fan: 0, rpm: 3000)
        rig.temperature.current = 96
        rig.controller.tick()
        rig.temperature.current = 89
        rig.controller.tick()
        let result = rig.controller.setForced(fan: 0, rpm: 3000)
        #expect(result.state == .automatic && result.detail.contains("hotter"), "Apple's speed is looked at again before going on")
    }

    @Test func theGuardIsOnlyForFansTheHelperHoldsNotAMacThatIsJustHot() {
        let rig = Rig(actual: 2000, temperature: 99)
        rig.controller.tick()
        rig.controller.tick()
        #expect(rig.writes.isEmpty, "nothing is held, so the helper takes no manual control of its own")
    }

    @Test func aGuardedCommandStillCannotLowerTheFanAndGivesTheFanBackWhenTheLeaseRunsOut() {
        let rig = Rig(actual: 2000, temperature: 97)
        let result = rig.controller.setForced(fan: 0, rpm: 3000)
        #expect(result.detail.contains("heat guard") && rig.smc.target(fan: 0) == 5779)
        rig.clock.advance(16)
        rig.temperature.current = 97
        rig.controller.tick()
        #expect(rig.smc.mode(fan: 0) == 0, "after the lease Apple's own control has the hot Mac")
    }

    @Test func ifTheGuardCannotWriteTheModeItAsksForTheTargetAlone() {
        let rig = Rig(actual: 2000, temperature: 60)
        _ = rig.controller.setFloor(fan: 0, rpm: 3000)
        rig.temperature.current = 96
        rig.smc.refuse("F0Md")
        rig.controller.tick()
        #expect(rig.smc.target(fan: 0) == 5779, "the target alone, since the mode could not be written")
        #expect(rig.controller.isHoldingFans)
    }

    @Test func ifTheGuardCannotWriteAnythingTheFanIsGivenBack() {
        let rig = Rig(actual: 2000, temperature: 60)
        _ = rig.controller.setFloor(fan: 0, rpm: 3000)
        rig.temperature.current = 96
        rig.smc.refuse("F0Md")
        rig.smc.refuse("F0Tg")
        rig.controller.tick()
        #expect(rig.controller.isHoldingFans == false)
        #expect(rig.smc.mode(fan: 0) == 0)
    }

    @Test func aDieTemperatureThatCannotBeReadWhileAFanIsHeldGivesItBack() {
        let rig = Rig(actual: 2000, temperature: 60)
        _ = rig.controller.setForced(fan: 0, rpm: 3000)
        rig.temperature.current = nil
        rig.smc.clearWrites()
        rig.controller.tick()
        #expect(rig.writes == [.mode(0, 0)])
    }

    @Test func withNoDieTemperatureNothingIsHeldInTheFirstPlace() {
        let rig = Rig(actual: 2000, temperature: nil)
        let result = rig.controller.setForced(fan: 0, rpm: 3000)
        #expect(result.ok == false && result.detail.contains("die temperature"))
        #expect(rig.writes.isEmpty)
    }

    // MARK: Errors and giving back

    @Test func anSMCErrorGivesEveryFanBackToAutomatic() {
        let rig = Rig(actual: 2000)
        _ = rig.controller.setForced(fan: 0, rpm: 3000)
        rig.smc.refuse("F1Tg")
        rig.smc.clearWrites()
        let result = rig.controller.setForced(fan: 1, rpm: 3000)
        #expect(result.ok == false && result.state == .automatic)
        #expect(rig.smc.mode(fan: 0) == 0 && rig.smc.mode(fan: 1) == 0)
        #expect(rig.controller.isHoldingFans == false || rig.writes.contains(.mode(0, 0)))
    }

    @Test func aReturnToAutomaticThatCouldNotBeWrittenIsRetriedAtEachTick() {
        let rig = Rig(actual: 2000)
        _ = rig.controller.setForced(fan: 0, rpm: 3000)
        rig.smc.refuse("F0Md")
        _ = rig.controller.setAuto(fan: 0)
        #expect(rig.controller.isHoldingFans, "it still has something to give back")
        rig.smc.clearWrites()
        rig.controller.tick()
        #expect(rig.writes == [.mode(0, 0)])
        rig.smc.allow("F0Md")
        rig.controller.tick()
        #expect(rig.smc.mode(fan: 0) == 0)
        #expect(rig.controller.isHoldingFans == false)
    }

    @Test func autoOneFanAutoAllFansAndAlreadyAutomaticWritesNothing() {
        let rig = Rig(actual: 2000)
        _ = rig.controller.setForced(fan: 0, rpm: 3000)
        _ = rig.controller.setForced(fan: 1, rpm: 3000)
        rig.smc.clearWrites()
        _ = rig.controller.setAuto(fan: 0)
        #expect(rig.writes == [.mode(0, 0)])
        rig.smc.clearWrites()
        _ = rig.controller.setAuto(fan: FanHelperResult.allFans)
        #expect(rig.writes == [.mode(1, 0)])
        rig.smc.clearWrites()
        let again = rig.controller.setAuto(fan: FanHelperResult.allFans)
        #expect(again.ok && rig.writes.isEmpty)
        #expect(rig.controller.setAuto(fan: 5).ok == false)
    }

    @Test func goingToSleepAndWakingGiveTheFansBack() {
        let rig = Rig(actual: 2000)
        _ = rig.controller.setForced(fan: 0, rpm: 3000)
        rig.smc.clearWrites()
        rig.controller.systemWillSleep()
        #expect(rig.writes == [.mode(0, 0)])
        _ = rig.controller.setForced(fan: 1, rpm: 3000)
        rig.smc.clearWrites()
        rig.controller.systemDidWake()
        #expect(rig.writes == [.mode(1, 0)])
        #expect(rig.controller.isHoldingFans == false)
    }

    // MARK: Macs Fan Control

    @Test func whileMacsFanControlRunsNothingIsSetButAutoIsStillAllowed() {
        let rig = Rig(actual: 2000)
        _ = rig.controller.setForced(fan: 0, rpm: 3000)
        rig.otherTool.current = true
        rig.smc.clearWrites()
        #expect(rig.controller.setForced(fan: 0, rpm: 3500).detail == "Macs Fan Control is running")
        #expect(rig.controller.setFloor(fan: 1, rpm: 3500).ok == false)
        #expect(rig.writes.isEmpty)
        #expect(rig.controller.setAuto(fan: 0).ok)
        #expect(rig.writes == [.mode(0, 0)])
    }

    @Test func atStartAFanThatReadsManualGoesBackToAutomaticAndTheOthersAreLeftAlone() {
        let rig = Rig(actual: 2000)
        rig.smc.setMode(1, fan: 1)
        rig.controller.startUp()
        #expect(rig.writes == [.mode(1, 0)])
    }

    @Test func atStartNothingIsWrittenWhenAllFansAreAutomatic() {
        let rig = Rig(actual: 2000)
        rig.controller.startUp()
        #expect(rig.writes.isEmpty)
    }

    @Test func atStartANotherToolsManualFansAreLeftAlone() {
        let rig = Rig(actual: 2000)
        rig.smc.setMode(1, fan: 0)
        rig.otherTool.current = true
        rig.controller.startUp()
        #expect(rig.writes.isEmpty)
    }

    // MARK: The floor

    @Test func aFloorWritesTheTargetAloneAndNeverTheMode() {
        let rig = Rig(actual: 2000)
        let result = rig.controller.setFloor(fan: 0, rpm: 3500)
        #expect(result.ok && result.state == .floor && result.appliedRPM == 3500)
        #expect(rig.writes == [.target(0, 3500)])
        #expect(rig.writes.contains { $0.key == "F0Md" } == false)
    }

    @Test func aFloorIsNeverBelowWhatAppleWasDoingWhenItWasAskedFor() {
        let rig = Rig(actual: 4000)
        let result = rig.controller.setFloor(fan: 0, rpm: 3000)
        #expect(result.appliedRPM == 4000)
    }

    @Test func aFloorKeepsItsBaselineWhenRenewedSoItCanComeDown() {
        let rig = Rig(actual: 2000)
        _ = rig.controller.setFloor(fan: 0, rpm: 4000)
        rig.smc.setActual(4000, fan: 0)
        let lower = rig.controller.setFloor(fan: 0, rpm: 2500)
        #expect(lower.appliedRPM == 2500, "the fan running at the floor does not hold the floor up")
    }

    @Test func aFloorExpiresToAutomaticLikeAnythingElse() {
        let rig = Rig(actual: 2000)
        _ = rig.controller.setFloor(fan: 0, rpm: 3500)
        rig.smc.clearWrites()
        rig.clock.advance(15.1)
        rig.controller.tick()
        #expect(rig.writes == [.mode(0, 0)])
    }

    @Test func goingFromAHeldFanToAFloorGivesTheModeBackFirst() {
        let rig = Rig(actual: 2000)
        _ = rig.controller.setForced(fan: 0, rpm: 3000)
        rig.smc.setActual(3000, fan: 0)
        rig.smc.clearWrites()
        let result = rig.controller.setFloor(fan: 0, rpm: 3500)
        #expect(result.state == .floor)
        #expect(rig.writes == [.mode(0, 0), .target(0, 3500)])
    }

    // MARK: Leaving

    @Test func beforeExitEveryFanIsGivenBack() {
        let rig = Rig(actual: 2000)
        _ = rig.controller.setForced(fan: 0, rpm: 3000)
        _ = rig.controller.setForced(fan: 1, rpm: 3000)
        rig.smc.clearWrites()
        rig.controller.restoreAutoForExit()
        #expect(rig.writes == [.mode(0, 0), .mode(1, 0)])
        rig.smc.clearWrites()
        rig.controller.restoreAutoForExit()
        #expect(rig.writes.isEmpty, "restoring twice (a signal and then atexit) writes nothing the second time")
    }

    @Test func restoringFromTheQueueItselfDoesNotDeadlock() async {
        let rig = Rig(actual: 2000)
        _ = rig.controller.setForced(fan: 0, rpm: 3000)
        await withCheckedContinuation { continuation in
            rig.controller.queue.async {
                rig.controller.restoreAutoForExit(timeout: 0.5)
                continuation.resume()
            }
        }
        #expect(rig.smc.mode(fan: 0) == 0)
    }

    @Test func restoringFromAnotherThreadWhileTheQueueIsBusyWaitsAtMostTheTimeout() async {
        let rig = Rig(actual: 2000)
        _ = rig.controller.setForced(fan: 0, rpm: 3000)
        let started = Date()
        rig.controller.queue.async { Thread.sleep(forTimeInterval: 1.5) }
        rig.controller.restoreAutoForExit(timeout: 0.3)
        #expect(Date().timeIntervalSince(started) < 1.0, "it did not wait for the stuck queue")
        try? await Task.sleep(for: .seconds(1.6))
        #expect(rig.smc.mode(fan: 0) == 0, "and it did restore, as soon as the queue was free")
    }

    @Test func theLogHasWritesAndDecisionsButNoTemperaturesOrAnythingElse() {
        let rig = Rig(actual: 2000, temperature: 61.5)
        _ = rig.controller.setForced(fan: 0, rpm: 3200)
        rig.clock.advance(16)
        rig.controller.tick()
        let lines = rig.logs.all
        #expect(lines.contains("write fan 0 mode 1") && lines.contains("write fan 0 target 3200") && lines.contains("write fan 0 mode 0"))
        #expect(lines.allSatisfy { !$0.contains("61") }, "no temperature in the log")
    }
}

enum SMCValueForTests {
    static func float(_ bytes: [UInt8]) -> Double? {
        guard bytes.count == 4 else { return nil }
        return Double(Float(bitPattern: UInt32(bytes[3]) << 24 | UInt32(bytes[2]) << 16 | UInt32(bytes[1]) << 8 | UInt32(bytes[0])))
    }
}
