import Foundation
import Testing
@testable import PerformanceModule

@MainActor final class FakeActivity: ActivityAssertion {
    private(set) var begins = 0
    private(set) var ends = 0
    var isHeld: Bool { begins > ends }
    func begin() { begins += 1 }
    func end() { ends += 1 }
}

@MainActor final class StepClock {
    var date = Date(timeIntervalSinceReferenceDate: 50_000)
    func tick(_ seconds: TimeInterval = 2) { date = date.addingTimeInterval(seconds) }
}

/// The curve over a helper that is a fake: what it asks the helper for, and when it gives the fans back.
@MainActor @Suite struct FanCurveRunnerTests {
    let fans = [
        FanReading(index: 0, rpm: 2000, minRPM: 1200, maxRPM: 5779),
        FanReading(index: 1, rpm: 2000, minRPM: 1200, maxRPM: 6241),
    ]

    func snapshot(_ temperature: Double?, fans: [FanReading]? = nil) -> ThermalSnapshot {
        ThermalSnapshot(cpu: temperature, gpu: temperature.map { $0 - 10 }, fans: fans ?? self.fans)
    }

    struct Setup {
        let rig: HelperRig
        let clock = StepClock()
        let activity = FakeActivity()
        let runner: FanCurveRunner

        init(status: FanHelperRegistrationStatus = .enabled, runningApps: Set<String> = []) async {
            rig = HelperRig(status: status, runningApps: runningApps)
            await rig.manager.refresh()
            let clock = clock
            runner = FanCurveRunner(helper: rig.manager, now: { clock.date }, activity: activity)
        }
    }

    // MARK: When it does nothing

    @Test func inAppleModeNothingIsAskedOfTheHelper() async {
        let setup = await Setup()
        await setup.runner.configure(mode: .apple, curve: .standard, mechanism: .forced)
        await setup.runner.step(snapshot(90))
        #expect(setup.rig.client.commands.isEmpty)
        #expect(setup.runner.status == .off && setup.runner.activeText == nil && setup.runner.isOn == false)
        #expect(setup.activity.isHeld == false)
    }

    @Test func withoutARunningHelperItWaitsAndAsksForNothing() async {
        for status in [FanHelperRegistrationStatus.notRegistered, .requiresApproval, .notFound] {
            let setup = await Setup(status: status)
            await setup.runner.configure(mode: .curve, curve: .standard, mechanism: .forced)
            await setup.runner.step(snapshot(90))
            #expect(setup.runner.status == .waitingForHelper, "\(status)")
            #expect(setup.rig.client.commands.isEmpty)
        }
    }

    @Test func withoutAProbeResultItAsksForTheProbeAndSetsNothing() async {
        let setup = await Setup()
        await setup.runner.configure(mode: .curve, curve: .standard, mechanism: nil)
        await setup.runner.step(snapshot(90))
        #expect(setup.runner.status == .needsProbe)
        #expect(setup.rig.client.commands.isEmpty)
    }

    @Test func whileMacsFanControlRunsItStaysOutAndGivesBackWhatItHeld() async {
        let apps = AppsBox()
        let registration = FakeFanHelperRegistration(status: .enabled)
        let client = FakeFanHelperClient()
        let manager = FanHelperManager(registration: registration, client: client, bundled: { .matching }, runningApps: { apps.value }, pause: { _ in })
        await manager.refresh()
        let clock = StepClock()
        let runner = FanCurveRunner(helper: manager, now: { clock.date }, activity: FakeActivity())
        await runner.configure(mode: .curve, curve: .standard, mechanism: .forced)
        await runner.step(snapshot(80))
        #expect(client.commands.isEmpty == false)
        client.answerCommands { _ in .success(FanCommandResult(ok: true, state: .automatic)) }
        apps.value = [FanHelperManager.macsFanControlBundleID]
        clock.tick()
        await runner.step(snapshot(80))
        #expect(runner.status == .blockedByMacsFanControl)
        #expect(client.commands.last == .auto(-1))
    }

    final class AppsBox {
        var value: Set<String> = []
    }

    @Test func aTemperatureThatCannotBeReadPausesTheCurve() async {
        let setup = await Setup()
        await setup.runner.configure(mode: .curve, curve: .standard, mechanism: .forced)
        await setup.runner.step(snapshot(nil))
        #expect(setup.runner.status == .error("Không đọc được nhiệt độ hoặc quạt"))
        #expect(setup.rig.client.commands.isEmpty)
        await setup.runner.step(snapshot(70, fans: []))
        #expect(setup.runner.status == .error("Không đọc được nhiệt độ hoặc quạt"))
    }

    @Test func belowTheStartTemperatureAppleIsLeftInChargeAndNothingIsSent() async {
        let setup = await Setup()
        await setup.runner.configure(mode: .curve, curve: .standard, mechanism: .forced)
        for _ in 0..<5 {
            await setup.runner.step(snapshot(48))
            setup.clock.tick()
        }
        #expect(setup.runner.status == .active(rpm: nil))
        #expect(setup.runner.activeText == "Đường cong · đang để Apple")
        #expect(setup.rig.client.commands.isEmpty)
    }

    // MARK: Setting the fans

    @Test func aHotMacHasEachFanAskedForItsOwnSpeedThroughTheWayTheProbeFound() async {
        let forced = await Setup()
        await forced.runner.configure(mode: .curve, curve: .standard, mechanism: .forced)
        await forced.runner.step(snapshot(95))
        guard case let .forced(0, first)? = forced.rig.client.commands.first, case let .forced(1, second)? = forced.rig.client.commands.last else {
            Issue.record("expected a forced command for each fan: \(forced.rig.client.commands)")
            return
        }
        #expect(first == 2800 && second == 2800, "from the fans' own 2000, 800 in the first two-second step")

        let floor = await Setup()
        await floor.runner.configure(mode: .curve, curve: .standard, mechanism: .floor)
        await floor.runner.step(snapshot(95))
        #expect(floor.rig.client.commands.allSatisfy { if case .floor = $0 { true } else { false } })
        #expect(floor.rig.client.commands.count == 2)
    }

    @Test func everyStepRenewsTheLeaseEvenWhenTheSpeedHasNotChanged() async {
        let setup = await Setup()
        await setup.runner.configure(mode: .curve, curve: FanCurve(start: 30, full: 40), mechanism: .forced)
        var fans = self.fans
        for _ in 0..<12 {
            await setup.runner.step(snapshot(80, fans: fans))
            setup.clock.tick()
            fans = fans.map { FanReading(index: $0.index, rpm: $0.maxRPM, minRPM: $0.minRPM, maxRPM: $0.maxRPM) }
        }
        let commands = setup.rig.client.commands
        #expect(commands.count == 24, "two fans at every step, the speed settled at the maximum or not")
        #expect(commands.suffix(4).map { if case let .forced(_, rpm) = $0 { rpm } else { -1 } }.allSatisfy { $0 > 0 })
    }

    @Test func theStatusTellsTheAverageSpeedItWasGiven() async {
        let setup = await Setup()
        setup.rig.client.answerCommands { command in
            if case let .forced(_, rpm) = command { return .success(FanCommandResult(ok: true, state: .forced, appliedRPM: rpm, leaseSeconds: 15)) }
            return .success(FanCommandResult(ok: true, state: .automatic))
        }
        await setup.runner.configure(mode: .curve, curve: .standard, mechanism: .forced)
        await setup.runner.step(snapshot(95))
        #expect(setup.runner.status == .active(rpm: 2800))
        #expect(setup.runner.activeText == "Đường cong · 2800 vòng/phút")
    }

    @Test func aHelperThatKeepsTheFansAutomaticBecauseAppleIsHigherIsNotAnError() async {
        let setup = await Setup()
        setup.rig.client.answerCommands { _ in .success(FanCommandResult(ok: true, state: .automatic, detail: "Apple's own speed is higher")) }
        await setup.runner.configure(mode: .curve, curve: .standard, mechanism: .forced)
        await setup.runner.step(snapshot(95))
        #expect(setup.runner.status == .active(rpm: nil))
    }

    @Test func whenTheTemperatureFallsBelowTheStartTheFansAreGivenBackOnceAndNotAgain() async {
        let setup = await Setup()
        await setup.runner.configure(mode: .curve, curve: .standard, mechanism: .forced)
        for _ in 0..<5 {
            await setup.runner.step(snapshot(80))
            setup.clock.tick()
        }
        setup.rig.client.answerCommands { _ in .success(FanCommandResult(ok: true, state: .automatic)) }
        var before = setup.rig.client.commands.count
        for _ in 0..<80 {
            await setup.runner.step(snapshot(40))
            setup.clock.tick()
        }
        let autos = setup.rig.client.commands.dropFirst(before).filter { $0 == .auto(-1) }
        #expect(autos.count == 1, "given back once, then nothing to send")
        before = setup.rig.client.commands.count
        await setup.runner.step(snapshot(40))
        #expect(setup.rig.client.commands.count == before)
    }

    // MARK: Failing

    @Test func aHelperThatRefusesStopsTheCurveWithItsReasonAndGivesTheFansBack() async {
        let setup = await Setup()
        setup.rig.client.answerCommands { command in
            if case .auto = command { return .success(FanCommandResult(ok: true, state: .automatic)) }
            return .success(FanCommandResult(ok: false, state: .automatic, detail: "the SMC refused F0Md (0x82)"))
        }
        await setup.runner.configure(mode: .curve, curve: .standard, mechanism: .forced)
        await setup.runner.step(snapshot(90))
        #expect(setup.runner.status == .error("the SMC refused F0Md (0x82)"))
        #expect(setup.rig.client.commands.last == .auto(-1))
    }

    @Test func aHelperThatCannotBeReachedIsAnErrorAndTheNextStepTriesAgain() async {
        let setup = await Setup()
        setup.rig.client.answerCommands { _ in .failure(.timeout) }
        await setup.runner.configure(mode: .curve, curve: .standard, mechanism: .forced)
        await setup.runner.step(snapshot(90))
        #expect(setup.runner.status == .error("helper không trả lời"))
        setup.rig.client.answerCommands { command in .success(FanCommandResult(ok: true, state: .forced, appliedRPM: { if case let .forced(_, rpm) = command { rpm } else { nil } }())) }
        setup.clock.tick()
        await setup.runner.step(snapshot(90))
        if case .active = setup.runner.status {} else { Issue.record("expected the curve to run again, got \(setup.runner.status)") }
    }

    // MARK: Leaving

    @Test func stoppingGivesTheFansBackLetsTheAppBeSlowedAgainAndTurnsTheCurveOff() async {
        let setup = await Setup()
        await setup.runner.configure(mode: .curve, curve: .standard, mechanism: .forced)
        await setup.runner.step(snapshot(90))
        #expect(setup.activity.isHeld)
        await setup.runner.stop()
        #expect(setup.rig.client.commands.last == .auto(-1))
        #expect(setup.activity.isHeld == false)
        #expect(setup.runner.status == .off)
    }

    @Test func stoppingWithNothingHeldSendsNothing() async {
        let setup = await Setup()
        await setup.runner.configure(mode: .curve, curve: .standard, mechanism: .forced)
        await setup.runner.step(snapshot(40))
        await setup.runner.stop()
        #expect(setup.rig.client.commands.isEmpty)
    }

    @Test func switchingBackToAppleGivesTheFansBackAtOnce() async {
        let setup = await Setup()
        await setup.runner.configure(mode: .curve, curve: .standard, mechanism: .forced)
        await setup.runner.step(snapshot(90))
        await setup.runner.configure(mode: .apple, curve: .standard, mechanism: .forced)
        #expect(setup.rig.client.commands.last == .auto(-1))
        #expect(setup.runner.status == .off)
    }

    @Test func theAppIsKeptAwakeExactlyWhileTheCurveIsTheMode() async {
        let setup = await Setup()
        await setup.runner.configure(mode: .curve, curve: .standard, mechanism: .forced)
        await setup.runner.configure(mode: .curve, curve: FanCurve(start: 50, full: 80), mechanism: .forced)
        #expect(setup.activity.isHeld)
        await setup.runner.configure(mode: .apple, curve: .standard, mechanism: .forced)
        #expect(setup.activity.isHeld == false)
        #expect(setup.activity.begins == 1 && setup.activity.ends == 1, "begun once, ended once, however often it was configured")
    }

    // MARK: The words

    @Test func eachStatusHasItsSentence() {
        let curve = FanCurve.standard
        func say(_ status: FanCurveRunner.Status, mode: FanMode = .curve) -> String { FanCurvePresentation.status(status, mode: mode, curve: curve) }
        #expect(say(.off, mode: .apple) == "Quạt đang theo chế độ tự động của Apple.")
        #expect(say(.off) == "Đường cong đang chờ lần đọc nhiệt độ đầu tiên.")
        #expect(say(.waitingForHelper).contains("cài và cho phép helper"))
        #expect(say(.needsProbe).contains("Thử điều khiển quạt"))
        #expect(say(.blockedByMacsFanControl).contains("thoát Macs Fan Control"))
        #expect(say(.active(rpm: 3200.4)) == "Đang điều khiển: quạt khoảng 3200 vòng/phút.")
        #expect(say(.active(rpm: nil)) == "Chưa cần: Apple đang lo, đường cong sẽ vào từ 55 °C.")
        #expect(say(.error("x")) == "Lỗi: x")
    }

    @Test func theTabLineIsShortWhenTheCurveIsPausedAndNothingWhenItIsOff() async {
        let setup = await Setup()
        await setup.runner.configure(mode: .curve, curve: .standard, mechanism: nil)
        await setup.runner.step(snapshot(90))
        #expect(setup.runner.activeText == "Đường cong · tạm dừng")
    }
}
