import CoreAudio
import EqualizerAudio
import EqualizerDSP
import Foundation
import MyNotchCore
import MyNotchTestSupport
import Synchronization
import Testing
@testable import EqualizerModule

struct MiniFailure: LocalizedError {
    var errorDescription: String? { "the tap could not be made" }
}

/// What `observeChanges` hands back: the manager dropping it is how it stops listening.
nonisolated final class MiniToken: Sendable {}

nonisolated final class MiniPipeline: PipelineHandle, @unchecked Sendable {
    private let system: MiniAudioSystem
    private let torn = Mutex(false)

    init(system: MiniAudioSystem) { self.system = system }

    var sampleRate: Double { 48_000 }
    func takePeak() -> Float { system.peak }
    func tearDown() {
        let first = torn.withLock { done in
            defer { done = true }
            return !done
        }
        if first { system.pipelineWasTornDown() }
    }
}

/// The smallest `AudioSystem` that lets the real `PipelineManager` run: one device that is playing, silent or not, and builds
/// that work or fail. Touches no audio.
nonisolated final class MiniAudioSystem: AudioSystem, @unchecked Sendable {
    private struct State {
        var peak: Float = 0
        var active: Set<String> = ["speakers"]
        var failing: Set<String> = []
        var attempts = 0
        var live = 0
        weak var token: MiniToken?
    }

    private let state = Mutex(State())

    var ownProcessID: AudioObjectID? { 1 }
    func activeOutputDeviceUIDs() -> Set<String> { state.withLock { $0.active } }
    func deviceName(uid: String) -> String? { uid == "speakers" ? "Loa trong" : "Loa \(uid)" }
    func outputVolume(uid: String) -> Double? { nil }

    func makePipeline(deviceUID: String, chain: EQChain) throws -> any PipelineHandle {
        try state.withLock { state in
            state.attempts += 1
            if state.failing.contains(deviceUID) { throw MiniFailure() }
            state.live += 1
            return MiniPipeline(system: self)
        }
    }

    func observeChanges(_ handler: @escaping @Sendable () -> Void, volumeChanged: @escaping @Sendable () -> Void) -> AnyObject {
        let token = MiniToken()
        state.withLock { $0.token = token }
        return token
    }

    var peak: Float { state.withLock { $0.peak } }
    var attempts: Int { state.withLock { $0.attempts } }
    /// Pipelines built and not yet torn down.
    var livePipelines: Int { state.withLock { $0.live } }
    var isObserved: Bool { state.withLock { $0.token != nil } }
    func setPeak(_ peak: Float) { state.withLock { $0.peak = peak } }
    func setFailing(_ failing: Bool, device: String = "speakers") {
        state.withLock { state in
            if failing { state.failing.insert(device) } else { state.failing.remove(device) }
        }
    }
    func play(on devices: Set<String>) { state.withLock { $0.active = devices } }
    func pipelineWasTornDown() { state.withLock { $0.live -= 1 } }
}

/// The module on the real `PipelineManager`, whose events arrive from inside its own calls: stopping it from inside the verdict
/// and the failure must leave it stopped, quiet, and able to start again.
@Suite struct RealManagerTests {
    let defaults = makeIsolatedDefaults()
    let state: EqualizerState
    let system = MiniAudioSystem()
    let scheduler = ManualScheduler()
    let module: EqualizerModule
    let harness: RegistryHarness

    init() {
        state = EqualizerState(settings: SettingsStore(defaults: defaults))
        module = EqualizerModule(state: state, engine: PipelineManager(system: system, scheduler: scheduler), isEqMacRunning: { false })
        harness = RegistryHarness([module])
    }

    func settle(until condition: () -> Bool) async {
        for _ in 0..<100 where !condition() { await Task.yield() }
    }

    /// The EQ on, with a pipeline on the speakers.
    func startedAndOn() async {
        await harness.registry.bootstrap()
        state.isEnabled = true
        await settle { system.livePipelines == 1 }
    }

    /// Long enough for the manager to be sure the tap is silent.
    func listenForTwelveSeconds() {
        for _ in 0..<12 { scheduler.advance(by: .seconds(1)) }
    }

    @Test func aDeniedTapIsTornDownAndTheManagerLeftQuiet() async {
        await startedAndOn()
        #expect(module.status.line == .processing(["Loa trong"]))
        listenForTwelveSeconds()
        #expect(module.status.phase == .needsPermission)
        #expect(state.isEnabled)
        // The device is released: the tap is gone, so the original sound plays.
        #expect(system.livePipelines == 0)
        #expect(!system.isObserved)
        let attempts = system.attempts
        scheduler.advance(by: .seconds(60))
        #expect(system.attempts == attempts)
        #expect(system.livePipelines == 0)
        #expect(module.status.phase == .needsPermission)
    }

    @Test func retryStartsTheRealManagerAgainAndASecondDenialPausesAgain() async {
        await startedAndOn()
        listenForTwelveSeconds()
        module.retry()
        #expect(system.livePipelines == 1)
        #expect(system.isObserved)
        #expect(module.status.line == .processing(["Loa trong"]))
        listenForTwelveSeconds()
        #expect(module.status.phase == .needsPermission)
        #expect(system.livePipelines == 0)
    }

    @Test func aNewTryJustAfterTheVerdictStillWatchesForSilence() async {
        await startedAndOn()
        listenForTwelveSeconds()
        // The manager still has a check scheduled that it made after reporting the verdict; it must not confuse the new run.
        scheduler.advance(by: .milliseconds(500))
        module.retry()
        #expect(system.livePipelines == 1)
        listenForTwelveSeconds()
        #expect(module.status.phase == .needsPermission)
        #expect(system.livePipelines == 0)
    }

    @Test func openingTheTabAfterTheVerdictLeavesTheDeviceAloneAndTheHintUp() async {
        await startedAndOn()
        listenForTwelveSeconds()
        let attempts = system.attempts
        module.tabAppeared()
        scheduler.advance(by: .seconds(30))
        #expect(system.attempts == attempts)
        #expect(system.livePipelines == 0)
        #expect(!system.isObserved)
        #expect(module.status.line == .permission)
    }

    @Test func soundThatIsHeardNeverPauses() async {
        system.setPeak(0.3)
        await startedAndOn()
        listenForTwelveSeconds()
        scheduler.advance(by: .seconds(60))
        #expect(module.status.line == .processing(["Loa trong"]))
        #expect(system.livePipelines == 1)
    }

    @Test func aDeviceThatCannotBeBuiltStopsTheRealManagerAfterItsTries() async {
        system.setFailing(true)
        await harness.registry.bootstrap()
        state.isEnabled = true
        await settle { system.attempts == 1 }
        #expect(module.status.phase == .waiting)
        scheduler.advance(by: .seconds(1))
        scheduler.advance(by: .seconds(3))
        #expect(system.attempts == 3)
        #expect(module.status.phase == .failed("Loa trong: the tap could not be made"))
        #expect(!system.isObserved)
        #expect(state.isEnabled)
        scheduler.advance(by: .seconds(60))
        #expect(system.attempts == 3)
    }

    @Test func oneDeviceThatCannotBeBuiltLeavesTheOtherRunning() async {
        system.setPeak(0.3)
        system.play(on: ["speakers", "usb"])
        system.setFailing(true, device: "usb")
        await harness.registry.bootstrap()
        state.isEnabled = true
        await settle { system.livePipelines == 1 }
        scheduler.advance(by: .seconds(1))
        scheduler.advance(by: .seconds(3))
        // After its tries the one is reported, and the other keeps its pipeline and the manager keeps listening.
        #expect(module.status.phase == .processing(["Loa trong"]))
        #expect(module.status.line == .failed("Loa usb: the tap could not be made"))
        #expect(module.status.line.text == "Không chỉnh được Loa usb: the tap could not be made")
        #expect(system.livePipelines == 1)
        #expect(system.isObserved)
        let attempts = system.attempts
        scheduler.advance(by: .seconds(60))
        #expect(system.attempts == attempts)
        #expect(system.livePipelines == 1)
        // "Thử lại" rebuilds it, and the one that works with it.
        system.setFailing(false, device: "usb")
        module.retry()
        #expect(system.livePipelines == 2)
        #expect(module.status.line == .processing(["Loa trong", "Loa usb"]))
    }

    @Test func everyDeviceThatCannotBeBuiltStopsTheRealManager() async {
        system.play(on: ["speakers", "usb"])
        system.setFailing(true, device: "speakers")
        system.setFailing(true, device: "usb")
        await harness.registry.bootstrap()
        state.isEnabled = true
        await settle { system.attempts == 2 }
        scheduler.advance(by: .seconds(1))
        scheduler.advance(by: .seconds(3))
        #expect(module.status.phase == .failed("Loa trong: the tap could not be made"))
        #expect(!system.isObserved)
        #expect(system.livePipelines == 0)
        let attempts = system.attempts
        scheduler.advance(by: .seconds(60))
        #expect(system.attempts == attempts)
    }

    @Test func retryAfterAFailedDeviceGivesItAFreshSetOfTries() async {
        system.setFailing(true)
        await harness.registry.bootstrap()
        state.isEnabled = true
        await settle { system.attempts == 1 }
        scheduler.advance(by: .seconds(4))
        system.setFailing(false)
        module.retry()
        #expect(system.livePipelines == 1)
        #expect(module.status.line == .processing(["Loa trong"]))
    }

    @Test func switchingOffTearsTheRealPipelineDown() async {
        await startedAndOn()
        state.isEnabled = false
        await settle { system.livePipelines == 0 }
        #expect(system.livePipelines == 0)
        #expect(!system.isObserved)
        #expect(module.status.phase == .off)
    }
}
