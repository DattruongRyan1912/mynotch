import FanHelperKit
import Foundation
import Synchronization
import Testing
@testable import PerformanceModule

/// A helper that fails the way the stale one did after the app was replaced: the client's code-signing check of a process whose
/// executable is gone fails with NSCocoaErrorDomain 4102 (`NSXPCConnectionCodeSigningRequirementFailure`), until it is gone.
/// The first `failing` pings fail, the rest go to the fake helper behind it, which also answers every command.
nonisolated final class SigningFailureClient: FanHelperClient, Sendable {
    static let codeSigningFailure = NSError(domain: NSCocoaErrorDomain, code: 4102)

    let inner: FakeFanHelperClient
    private let failures: Mutex<Int>
    private let pings = Mutex(0)

    init(failing: Int, inner: FakeFanHelperClient = FakeFanHelperClient()) {
        failures = Mutex(failing)
        self.inner = inner
    }

    /// Every ping, the failed ones too.
    var pingCount: Int { pings.withLock { $0 } }

    /// The stale process has gone: from now on a ping reaches the new helper.
    func heal() { failures.withLock { $0 = 0 } }

    func ping() async throws -> FanHelperInfo {
        pings.withLock { $0 += 1 }
        let fails = failures.withLock { remaining -> Bool in
            guard remaining > 0 else { return false }
            remaining -= 1
            return true
        }
        if fails { throw Self.codeSigningFailure }
        return try await inner.ping()
    }

    func readFans() async throws -> [FanHelperFanInfo] { try await inner.readFans() }
    func setFloor(fan: Int, rpm: Double) async throws -> FanCommandResult { try await inner.setFloor(fan: fan, rpm: rpm) }
    func setForced(fan: Int, rpm: Double) async throws -> FanCommandResult { try await inner.setForced(fan: fan, rpm: rpm) }
    func setAuto(fan: Int) async throws -> FanCommandResult { try await inner.setAuto(fan: fan) }
}

/// A client whose second ping waits until the test lets it answer, so that a look can be in flight while the test acts. The first
/// ping fails at once, a third answers at once (it should not be made, and must not hang the test if it is).
nonisolated final class GatedPingClient: FanHelperClient, Sendable {
    private let calls = Mutex(0)
    private let waiter = Mutex<CheckedContinuation<Void, Never>?>(nil)

    var pingCount: Int { calls.withLock { $0 } }
    var isWaiting: Bool { waiter.withLock { $0 != nil } }

    func release() {
        waiter.withLock { held -> CheckedContinuation<Void, Never>? in
            let taken = held
            held = nil
            return taken
        }?.resume()
    }

    func ping() async throws -> FanHelperInfo {
        let call = calls.withLock { count -> Int in
            count += 1
            return count
        }
        if call == 1 { throw FanHelperError.timeout }
        if call > 2 { return .matching }
        await withCheckedContinuation { continuation in waiter.withLock { $0 = continuation } }
        return .matching
    }

    func readFans() async throws -> [FanHelperFanInfo] { throw FanHelperError.noProxy }
    func setFloor(fan: Int, rpm: Double) async throws -> FanCommandResult { throw FanHelperError.noProxy }
    func setForced(fan: Int, rpm: Double) async throws -> FanCommandResult { throw FanHelperError.noProxy }
    func setAuto(fan: Int) async throws -> FanCommandResult { throw FanHelperError.noProxy }
}

/// The pauses a manager asked for, instead of waiting them, and a way for a test to act in the middle of one.
@MainActor final class PauseHook {
    private(set) var durations: [Duration] = []
    var whenPaused: ((Duration) async -> Void)?

    func paused(_ duration: Duration) async {
        durations.append(duration)
        await whenPaused?(duration)
    }
}

/// The curve and the helper finding each other again after the app was replaced under a helper that is still running.
@MainActor @Suite struct FanHelperRecoveryTests {
    let fans = [
        FanReading(index: 0, rpm: 2000, minRPM: 1200, maxRPM: 5779),
        FanReading(index: 1, rpm: 2000, minRPM: 1200, maxRPM: 6241),
    ]

    func snapshot(_ temperature: Double) -> ThermalSnapshot {
        ThermalSnapshot(cpu: temperature, gpu: temperature - 10, fans: fans)
    }

    struct Recovery {
        let manager: FanHelperManager
        let registration: FakeFanHelperRegistration
        let client: SigningFailureClient
        let hook = PauseHook()
        let clock = StepClock()
        let runner: FanCurveRunner

        /// The helper registered and enabled, its first `failing` pings failing like the stale one's. `look` is whether the app has
        /// looked once already, which is what the launch check does first.
        init(failing: Int, bundled: BundledFanHelper = .matching, inner: FakeFanHelperClient = FakeFanHelperClient(), look: Bool = true) async {
            let registration = FakeFanHelperRegistration(status: .enabled)
            let client = SigningFailureClient(failing: failing, inner: inner)
            let hook = hook
            manager = FanHelperManager(
                registration: registration, client: client, bundled: { bundled }, runningApps: { [] }, pause: { await hook.paused($0) }
            )
            self.registration = registration
            self.client = client
            let clock = clock
            runner = FanCurveRunner(helper: manager, now: { clock.date }, activity: FakeActivity())
            if look { await manager.refresh() }
        }
    }

    static func isUnreachable(_ phase: FanHelperPhase) -> Bool {
        if case .unreachable = phase { true } else { false }
    }

    // MARK: The curve looks again

    @Test func aHelperThatFailedTheSigningCheckIsUnreachableAndTheCurveResumesAtTheReadingAfterTheFiveSecondLook() async {
        let r = await Recovery(failing: 1)
        #expect(Self.isUnreachable(r.manager.phase), "the app's first look got the 4102")
        await r.runner.configure(mode: .curve, curve: .standard, mechanism: .forced)
        for _ in 0..<3 {
            await r.runner.step(snapshot(95))
            r.clock.tick()
        }
        #expect(r.client.pingCount == 1, "readings at 0, 2 and 4 s: no look yet")
        #expect(r.runner.status == .waitingForHelper)
        await r.runner.step(snapshot(95))
        #expect(r.client.pingCount == 2, "the reading at 6 s is the first one past 5 s: it looks")
        #expect(r.manager.phase == .running(.matching))
        #expect(r.client.inner.commands.isEmpty, "and the curve waits for the next reading, which has a temperature read after the look")
        r.clock.tick()
        await r.runner.step(snapshot(95))
        #expect(r.client.inner.commands == [.forced(FanCommandResult.allFans, 2800)])
        if case .active = r.runner.status {} else { Issue.record("expected the curve to run, got \(r.runner.status)") }
    }

    @Test func aClientThatKeepsFailingIsLookedAtOnTheScheduleAndNeverInATightLoop() async {
        let r = await Recovery(failing: .max)
        await r.runner.configure(mode: .curve, curve: .standard, mechanism: .forced)
        var seen = r.client.pingCount
        var lookTimes: [Int] = []
        for second in stride(from: 0, to: 600, by: 2) {
            await r.runner.step(snapshot(95))
            if r.client.pingCount > seen {
                lookTimes.append(second)
                seen = r.client.pingCount
                #expect(r.client.pingCount == lookTimes.count + 1, "one ping for each look")
            }
            r.clock.tick()
        }
        // 5 s after the first reading, then 15, 30 and 60 s after the end of the look before, at the first two-second reading past each.
        #expect(Array(lookTimes.prefix(5)) == [6, 22, 52, 112, 172])
        #expect(lookTimes.count == 12, "ten minutes of readings, twelve looks: \(lookTimes)")
        #expect(zip(lookTimes, lookTimes.dropFirst()).allSatisfy { $1 - $0 >= 5 })
        #expect(r.client.inner.commands.isEmpty && r.runner.status == .waitingForHelper)
        #expect(r.registration.calls.isEmpty, "a look never registers anything")
        #expect(FanCurveRunner.lookDelays == [5, 15, 30] && FanCurveRunner.steadyLookDelay == 60)
        #expect((FanCurveRunner.lookDelays + [FanCurveRunner.steadyLookDelay]).allSatisfy { $0 >= 5 }, "no wait is shorter than five seconds")
    }

    @Test func aLookThatFindsTheHelperStartsTheScheduleAgainTheNextTimeItIsLost() async {
        let r = await Recovery(failing: 1)
        await r.runner.configure(mode: .curve, curve: .standard, mechanism: .forced)
        for _ in 0..<4 {
            await r.runner.step(snapshot(95))
            r.clock.tick()
        }
        #expect(r.manager.phase == .running(.matching))
        await r.runner.step(snapshot(95))
        r.clock.tick()
        // The helper is lost again (a failed read of the fans while Settings compares them says so).
        r.client.inner.answerFans(.failure(.timeout))
        await r.manager.compareFans(app: [])
        #expect(Self.isUnreachable(r.manager.phase))
        r.client.heal()
        let before = r.client.pingCount
        for _ in 0..<2 {
            await r.runner.step(snapshot(95))
            r.clock.tick()
        }
        #expect(r.client.pingCount == before, "the new absence waits its own five seconds")
        await r.runner.step(snapshot(95))
        r.clock.tick(2)
        await r.runner.step(snapshot(95))
        #expect(r.client.pingCount == before + 1)
        #expect(r.manager.phase == .running(.matching))
    }

    // MARK: When nothing looks

    @Test func whileTheModeIsAppleNothingLooksUnlessTheTabOrSettingsAsk() async {
        let r = await Recovery(failing: .max)
        await r.runner.configure(mode: .apple, curve: .standard, mechanism: .forced)
        for _ in 0..<300 {
            await r.runner.step(snapshot(95))
            r.clock.tick()
        }
        #expect(r.client.pingCount == 1, "only the look the app made when it opened")
        await r.manager.refresh()
        #expect(r.client.pingCount == 2, "the tab appearing or Settings opening looks as before")
    }

    @Test func switchingTheCurveOffAndOnStartsTheWaitAgain() async {
        let r = await Recovery(failing: .max)
        await r.runner.configure(mode: .curve, curve: .standard, mechanism: .forced)
        for _ in 0..<4 {
            await r.runner.step(snapshot(95))
            r.clock.tick()
        }
        #expect(r.client.pingCount == 2, "the look at 6 s")
        await r.runner.configure(mode: .apple, curve: .standard, mechanism: .forced)
        await r.runner.configure(mode: .curve, curve: .standard, mechanism: .forced)
        for _ in 0..<2 {
            await r.runner.step(snapshot(95))
            r.clock.tick()
        }
        #expect(r.client.pingCount == 2)
        await r.runner.step(snapshot(95))
        r.clock.tick(2)
        await r.runner.step(snapshot(95))
        #expect(r.client.pingCount == 3, "five seconds after the first reading of the new run")
    }

    @Test func whileAProbeRunsNothingLooks() async {
        let r = await Recovery(failing: .max)
        await r.runner.configure(mode: .curve, curve: .standard, mechanism: .forced)
        r.manager.probeStep = "Thử đặt sàn tốc độ"
        for _ in 0..<100 {
            await r.runner.step(snapshot(95))
            r.clock.tick()
        }
        #expect(r.client.pingCount == 1)
        await r.manager.lookAgain()
        #expect(r.client.pingCount == 1, "not even when asked directly")
        r.manager.probeStep = nil
        for _ in 0..<3 {
            await r.runner.step(snapshot(95))
            r.clock.tick()
        }
        #expect(r.client.pingCount == 1, "the wait is counted from the first reading after the probe")
        await r.runner.step(snapshot(95))
        #expect(r.client.pingCount == 2, "and the look comes five seconds after it")
    }

    @Test func whileAnInstallRunsNothingLooksAndWhatItSettlesIsNotOverwritten() async {
        let r = await Recovery(failing: .max)
        r.registration.registerError = NSError(domain: FanHelperManager.serviceManagementDomain, code: FanHelperManager.notPermittedCode)
        r.registration.statusAfterRegister = .notRegistered
        await r.runner.configure(mode: .curve, curve: .standard, mechanism: .forced)
        var phases: [FanHelperPhase] = []
        let (manager, runner, clock, hook) = (r.manager, r.runner, r.clock, r.hook)
        let hot = snapshot(95)
        hook.whenPaused = { _ in
            phases.append(manager.phase)
            for _ in 0..<5 {
                clock.tick(30)
                await runner.step(hot)
                await manager.lookAgain()
            }
        }
        await r.manager.install()
        #expect(phases.count == FanHelperManager.approvalLooks && phases.allSatisfy { $0 == .busy(.installing) })
        #expect(r.client.pingCount == 1, "the install pinged nothing and nothing else did")
        #expect(r.registration.calls == [.register])
    }

    @Test func aLookWhileAnotherIsInFlightDoesNothingAndAnAnswerAfterTheStateMovedOnIsDropped() async {
        let registration = FakeFanHelperRegistration(status: .enabled)
        let client = GatedPingClient()
        let manager = FanHelperManager(registration: registration, client: client, bundled: { .matching }, runningApps: { [] }, pause: { _ in })
        await manager.refresh()
        #expect(Self.isUnreachable(manager.phase))
        let look = Task { await manager.lookAgain() }
        for _ in 0..<1000 where !client.isWaiting { await Task.yield() }
        #expect(client.isWaiting)
        await manager.lookAgain()
        #expect(client.pingCount == 2, "the second look asked nobody: one in flight at a time")
        // The user removes the helper while the look is out.
        await manager.uninstall()
        #expect(manager.phase == .notInstalled)
        client.release()
        await look.value
        #expect(manager.phase == .notInstalled, "the late answer did not bring back a phase that was left")
    }

    @Test func aLookOnlyHappensWhenTheHelperDidNotAnswer() async {
        let running = await Recovery(failing: 0)
        #expect(running.manager.phase == .running(.matching))
        await running.manager.lookAgain()
        #expect(running.client.pingCount == 1)

        let removed = await Recovery(failing: .max)
        removed.registration.status = .notRegistered
        await removed.manager.lookAgain()
        #expect(removed.manager.phase == .notInstalled, "a look says what the registration says now")
        #expect(removed.client.pingCount == 1 && removed.registration.calls.isEmpty)
    }

    // MARK: The launch check

    @Test func theLaunchCheckLooksAgainAfterTwentyFiveSecondsWhichIsLongerThanTheHelpersIdleExit() async {
        #expect(FanHelperManager.launchRetryPause == .seconds(25) && FanHelperManager.launchRetryPause > .seconds(20))
        let r = await Recovery(failing: 1, look: false)
        await r.manager.checkAtLaunch()
        #expect(r.hook.durations == [.seconds(25)])
        #expect(r.client.pingCount == 2)
        #expect(r.manager.phase == .running(.matching))
        #expect(r.registration.calls.isEmpty, "the stale helper was gone: the bundled one answered and there is nothing to register")
    }

    @Test func aHelperThatStillDoesNotAnswerAfterTheExtraLookIsReportedAndNeverRegistered() async {
        let r = await Recovery(failing: .max, look: false)
        await r.manager.checkAtLaunch()
        #expect(r.hook.durations == [.seconds(25)], "one more look, not a loop")
        #expect(r.client.pingCount == 2)
        #expect(Self.isUnreachable(r.manager.phase))
        #expect(r.registration.calls.isEmpty)
    }

    @Test func aHelperThatAnswersTheExtraLookWithAnotherBuildIsRegisteredAgainByTheExistingPolicyOnce() async {
        let inner = FakeFanHelperClient(pings: [.success(.oldBuild), .success(.matching)])
        let r = await Recovery(failing: 1, inner: inner, look: false)
        await r.manager.checkAtLaunch()
        #expect(r.registration.calls == [.unregister, .register])
        #expect(r.hook.durations == [.seconds(25), .seconds(1)])
        #expect(r.manager.phase == .running(.matching))
        await r.manager.checkAtLaunch()
        #expect(r.registration.calls == [.unregister, .register], "at most once per launch")
    }

    @Test func aHelperThatAnswersTheFirstLookIsNotWaitedFor() async {
        let r = await Recovery(failing: 0, look: false)
        await r.manager.checkAtLaunch()
        #expect(r.hook.durations.isEmpty && r.client.pingCount == 1)
    }

    @Test func aProbeStartedDuringTheWaitKeepsTheLaunchCheckFromRegisteringAgain() async {
        // Meanwhile the curve's look (or the tab's) found the helper, of the same version but another build, so the gate lets the
        // probe start; the policy of the launch check would then unregister the helper in the middle of it.
        let inner = FakeFanHelperClient(pings: [.success(.oldBuild)])
        let r = await Recovery(failing: 1, inner: inner, look: false)
        let manager = r.manager
        r.hook.whenPaused = { _ in
            await manager.lookAgain()
            manager.probeStep = "Thử đặt sàn tốc độ"
        }
        await r.manager.checkAtLaunch()
        #expect(r.manager.phase == .running(.oldBuild))
        #expect(r.client.pingCount == 2 && r.registration.calls.isEmpty)
    }

    @Test func aLaunchCheckThatWasCancelledDuringTheWaitDoesNotLookOrRegister() async {
        let inner = FakeFanHelperClient(pings: [.success(.oldBuild)])
        let r = await Recovery(failing: 1, inner: inner, look: false)
        let manager = r.manager
        r.hook.whenPaused = { _ in withUnsafeCurrentTask { $0?.cancel() } }
        let task = Task { await manager.checkAtLaunch() }
        await task.value
        #expect(r.client.pingCount == 1 && r.registration.calls.isEmpty)
    }
}
