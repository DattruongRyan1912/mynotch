import EqualizerDSP
import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import EqualizerAudio

/// Everything the manager says, in order.
private final class Events {
    var all: [EqualizerEngineEvent] = []
    var failures: [String] {
        all.compactMap { event in
            if case .failed(let message) = event { message } else { nil }
        }
    }
}

@Suite(.serialized) struct PipelineManagerTests {
    let system = FakeAudioSystem()
    let scheduler = ManualScheduler()
    let manager: PipelineManager
    private let events = Events()

    init() {
        manager = PipelineManager(system: system, scheduler: scheduler)
        let events = events
        manager.onEvent = { events.all.append($0) }
        system.name("A", as: "Loa trong")
        system.name("B", as: "AirPods")
    }

    private func change(then wait: Duration = .milliseconds(300)) {
        system.fireChange()
        scheduler.advance(by: wait)
    }

    // MARK: Which devices get a pipeline

    @Test func oneActiveDeviceMakesOnePipeline() {
        system.play(on: ["A"])
        manager.start()
        #expect(system.attempts == ["A"])
        #expect(events.all == [.devices(["Loa trong"])])
    }

    @Test func noActiveDeviceMeansNoPipeline() {
        manager.start()
        #expect(system.attempts.isEmpty)
        #expect(events.all.isEmpty)
        // Nothing playing costs nothing: no timer is left running.
        #expect(scheduler.pendingCount == 0)
        // And a change that leaves it so does not make one.
        change()
        #expect(system.attempts.isEmpty)
        #expect(scheduler.pendingCount == 0)
    }

    @Test func secondDeviceAddsPipelineAfterDebounce() {
        system.play(on: ["A"])
        manager.start()
        system.play(on: ["A", "B"])
        system.fireChange()
        scheduler.advance(by: .milliseconds(299))
        #expect(system.attempts == ["A"])
        scheduler.advance(by: .milliseconds(1))
        #expect(system.attempts == ["A", "B"])
        #expect(events.all.last == .devices(["AirPods", "Loa trong"]))
    }

    @Test func aBurstOfChangesIsLookedAtOnce() {
        system.play(on: ["A"])
        manager.start()
        let before = system.queries
        for _ in 0..<5 {
            system.fireChange()
            scheduler.advance(by: .milliseconds(50))
        }
        scheduler.advance(by: .milliseconds(300))
        #expect(system.queries == before + 1)
    }

    @Test func silentDeviceIsTornDown() throws {
        system.play(on: ["A", "B"])
        manager.start()
        system.play(on: ["A"])
        change()
        #expect(try #require(system.pipeline("B")).tearDownCount == 1)
        #expect(try #require(system.pipeline("A")).tearDownCount == 0)
        #expect(events.all.last == .devices(["Loa trong"]))
    }

    @Test func defaultDeviceSwitchMovesPipeline() throws {
        system.play(on: ["A"])
        manager.start()
        system.play(on: ["B"])
        system.fireChange()
        // Sound must not stay without its EQ for long: the new device is ready one debounce later, well under a second.
        scheduler.advance(by: .milliseconds(300))
        #expect(try #require(system.pipeline("A")).tearDownCount == 1)
        #expect(system.pipeline("B") != nil)
        #expect(system.attempts == ["A", "B"])
        #expect(events.all.last == .devices(["AirPods"]))
    }

    @Test func aChangeThatChangesNothingTouchesNothing() throws {
        system.play(on: ["A"])
        manager.start()
        // Building a pipeline stirs up Core Audio itself, so echoes like this one arrive all the time.
        change()
        change()
        #expect(system.attempts == ["A"])
        #expect(try #require(system.pipeline("A")).tearDownCount == 0)
        #expect(events.all == [.devices(["Loa trong"])])
    }

    // MARK: Sample rate

    @Test func sampleRateChangeRebuildsThePipelineWithNewCoefficients() throws {
        let profile = bandBoost(band: 9, by: 12)
        system.setRateForNewPipelines(16_000)
        system.play(on: ["A"])
        manager.start()
        manager.apply(profile)
        let first = try #require(system.pipeline("A"))

        // The device goes from 16 kHz (a headset in a call, where a 16 kHz band does not fit) to 48 kHz.
        system.setRateForNewPipelines(48_000)
        first.setSampleRate(48_000)
        change()
        #expect(first.tearDownCount == 1)
        let second = try #require(system.pipeline("A"))
        #expect(second !== first)
        #expect(second.tearDownCount == 0)

        let at16 = reference(profile, sampleRate: 16_000)
        let at48 = reference(profile, sampleRate: 48_000)
        #expect(render(second.chain, frequency: 16_000) == render(at48, frequency: 16_000))
        #expect(render(second.chain, frequency: 16_000) != render(at16, frequency: 16_000))
    }

    // MARK: Profiles

    @Test func applyReachesEveryPipelineChain() throws {
        system.play(on: ["A", "B"])
        manager.start()
        var profile = EQProfile.flat(named: "Nhỏ")
        profile.preamp = -6
        manager.apply(profile)
        for uid in ["A", "B"] {
            let chain = try #require(system.pipeline(uid)).chain
            let peak = try #require(render(chain).map(abs).max())
            #expect(abs(peak - 0.25) < 0.01)
        }
    }

    @Test func aPipelineMadeLaterGetsTheProfileToo() throws {
        var profile = EQProfile.flat(named: "Nhỏ")
        profile.preamp = -6
        manager.apply(profile)
        system.play(on: ["A"])
        manager.start()
        let chain = try #require(system.pipeline("A")).chain
        let peak = try #require(render(chain).map(abs).max())
        #expect(abs(peak - 0.25) < 0.01)
    }

    @Test func wrongProfilesAreClampedBeforeTheyReachTheFilters() throws {
        system.play(on: ["A"])
        manager.start()
        var profile = EQProfile.flat(named: "Lạ")
        profile.gains = [Double.nan, 99]
        profile.preamp = .infinity
        manager.apply(profile)
        let chain = try #require(system.pipeline("A")).chain
        let out = render(chain)
        #expect(out.allSatisfy { $0.isFinite && abs($0) <= 1 })
    }

    @Test func chainAndProfileUseTheSameBands() {
        #expect(EQChain.frequencies == EQProfile.frequencies)
        #expect(EQChain.gainRange == EQProfile.gainRange)
    }

    // MARK: Stopping

    @Test func stopTearsDownEverything() throws {
        system.play(on: ["A", "B"])
        manager.start()
        manager.stop()
        for uid in ["A", "B"] { #expect(try #require(system.pipeline(uid)).tearDownCount == 1) }
        #expect(events.all.last == .devices([]))
        // Nothing is left behind: no timer, no listener.
        #expect(scheduler.pendingCount == 0)
        #expect(!system.isObserved)
        system.fireChange()
        scheduler.advance(by: .seconds(30))
        #expect(system.attempts == ["A", "B"])
        // A second stop is harmless.
        manager.stop()
        for uid in ["A", "B"] { #expect(try #require(system.pipeline(uid)).tearDownCount == 1) }
    }

    @Test func stopCancelsAPendingLookAtChanges() {
        system.play(on: ["A"])
        manager.start()
        system.play(on: ["A", "B"])
        system.fireChange()
        manager.stop()
        scheduler.advance(by: .seconds(1))
        #expect(system.attempts == ["A"])
    }

    @Test func startsAgainAfterStop() throws {
        system.play(on: ["A"])
        manager.start()
        manager.stop()
        manager.start()
        #expect(system.attempts == ["A", "A"])
        #expect(try #require(system.pipelines.last).tearDownCount == 0)
        #expect(system.isObserved)
    }

    @Test func startingTwiceMakesNothingTwice() {
        system.play(on: ["A"])
        manager.start()
        manager.start()
        #expect(system.attempts == ["A"])
    }

    // MARK: Failing

    @Test func failedMakeRetriesAt1sThen3s() throws {
        system.play(on: ["A"])
        system.failBuilds(of: "A", [.immediately, .immediately])
        manager.start()
        #expect(system.attempts == ["A"])
        scheduler.advance(by: .milliseconds(999))
        #expect(system.attempts == ["A"])
        scheduler.advance(by: .milliseconds(1))
        #expect(system.attempts == ["A", "A"])
        // The second wait runs from the second failure, not from the start.
        scheduler.advance(by: .milliseconds(2_999))
        #expect(system.attempts == ["A", "A"])
        scheduler.advance(by: .milliseconds(1))
        #expect(system.attempts == ["A", "A", "A"])
        #expect(system.pipeline("A") != nil)
        #expect(events.failures.isEmpty)
        #expect(events.all == [.devices(["Loa trong"])])
        // And that was the last retry that was needed: nothing else is waiting but the silence check.
        scheduler.advance(by: .seconds(60))
        #expect(system.attempts == ["A", "A", "A"])
    }

    @Test func givingUpTellsTheUserAndOtherDevicesKeepWorking() throws {
        system.play(on: ["A", "B"])
        system.failBuilds(of: "A", [.immediately, .immediately, .immediately])
        manager.start()
        scheduler.advance(by: .seconds(4))
        #expect(system.attempts.filter { $0 == "A" }.count == 3)
        #expect(events.failures.count == 1)
        #expect(events.failures[0].contains("Loa trong"))
        // B was never in the way.
        #expect(try #require(system.pipeline("B")).tearDownCount == 0)
        #expect(events.all.contains(.devices(["AirPods"])))
        // No more tries by itself, and a change that leaves things as they are does not give it another go...
        scheduler.advance(by: .seconds(120))
        change()
        #expect(system.attempts.filter { $0 == "A" }.count == 3)
        #expect(events.failures.count == 1)
        // ...but a device that stops playing and starts again does.
        system.play(on: ["B"])
        change()
        system.play(on: ["A", "B"])
        change()
        #expect(system.attempts.filter { $0 == "A" }.count == 4)
        #expect(events.all.last == .devices(["AirPods", "Loa trong"]))
    }

    @Test func theEchoOfAFailedBuildDoesNotStartTheCountAgain() throws {
        // Making and destroying a tap stirs Core Audio up, so every attempt is followed by change notifications.
        system.echoOnEveryMake()
        system.play(on: ["A"])
        system.failBuilds(of: "A", [.immediately, .immediately, .immediately])
        manager.start()
        #expect(system.attempts == ["A"])
        scheduler.advance(by: .milliseconds(999))
        #expect(system.attempts == ["A"])
        scheduler.advance(by: .milliseconds(1))
        #expect(system.attempts == ["A", "A"])
        scheduler.advance(by: .milliseconds(2_999))
        #expect(system.attempts == ["A", "A"])
        scheduler.advance(by: .milliseconds(1))
        #expect(system.attempts == ["A", "A", "A"])
        #expect(events.failures.count == 1)
        // Given up, and the echoes keep coming, and nothing more is tried.
        scheduler.advance(by: .seconds(60))
        #expect(system.attempts == ["A", "A", "A"])
        #expect(events.failures.count == 1)

        // The device leaves and comes back: the whole schedule again, from that moment.
        system.failBuilds(of: "A", [.immediately, .immediately, .immediately])
        system.play(on: [])
        change()
        system.play(on: ["A"])
        change()
        #expect(system.attempts.count == 4)
        scheduler.advance(by: .milliseconds(1_000))
        #expect(system.attempts.count == 5)
        scheduler.advance(by: .milliseconds(3_000))
        #expect(system.attempts.count == 6)
        #expect(events.failures.count == 2)
        scheduler.advance(by: .seconds(60))
        #expect(system.attempts.count == 6)
    }

    @Test func aDeviceWaitingForItsRetryDoesNotHoldUpAnother() throws {
        system.echoOnEveryMake()
        system.play(on: ["A", "B"])
        system.failBuilds(of: "A", [.immediately])
        manager.start()
        // B is built at once, A waits for its retry at 1 s.
        #expect(system.attempts == ["A", "B"])
        scheduler.advance(by: .milliseconds(100))
        system.play(on: ["A", "B", "C"])
        system.fireChange()
        scheduler.advance(by: .milliseconds(300))
        // C is made without waiting for A, and A is not tried before its time.
        #expect(system.attempts == ["A", "B", "C"])
        scheduler.advance(by: .milliseconds(600))
        #expect(system.attempts == ["A", "B", "C", "A"])
        #expect(system.pipeline("A") != nil)
    }

    @Test func partialSetupIsTornDown() throws {
        system.play(on: ["A"])
        system.failBuilds(of: "A", [.afterTap])
        manager.start()
        // The tap that was made before the aggregate device failed is gone, and nothing half-built is listed.
        #expect(system.liveTaps == 0)
        #expect(system.pipelines.isEmpty)
        #expect(events.all.isEmpty)
        scheduler.advance(by: .seconds(1))
        #expect(system.liveTaps == 1)
        #expect(events.all == [.devices(["Loa trong"])])
        manager.stop()
        #expect(system.liveTaps == 0)
        #expect(try #require(system.pipeline("A")).tearDownCount == 1)
    }

    // MARK: Permission

    @Test func longSilenceFromTheTapMeansPermissionIsLikelyDenied() {
        system.setPeakForNewPipelines(0)
        system.play(on: ["A"])
        manager.start()
        scheduler.advance(by: .seconds(10))
        #expect(!events.all.contains(.permissionLikelyDenied))
        scheduler.advance(by: .seconds(2))
        #expect(events.all.filter { $0 == .permissionLikelyDenied }.count == 1)
        // Said once, not on every check.
        scheduler.advance(by: .seconds(30))
        #expect(events.all.filter { $0 == .permissionLikelyDenied }.count == 1)
    }

    @Test func soundKeepsThePermissionHintAway() {
        system.setPeakForNewPipelines(0.2)
        system.play(on: ["A"])
        manager.start()
        scheduler.advance(by: .seconds(60))
        #expect(!events.all.contains(.permissionLikelyDenied))
    }

    @Test func soundAfterADenialListsTheDevicesAgain() throws {
        system.setPeakForNewPipelines(0)
        system.play(on: ["A"])
        manager.start()
        scheduler.advance(by: .seconds(12))
        #expect(events.all.last == .permissionLikelyDenied)
        try #require(system.pipeline("A")).setPeak(0.3)
        scheduler.advance(by: .seconds(1))
        #expect(events.all.last == .devices(["Loa trong"]))
    }

    @Test func silenceOnlyCountsWhileSomethingIsPlaying() {
        system.setPeakForNewPipelines(0)
        system.play(on: ["A"])
        manager.start()
        scheduler.advance(by: .seconds(8))
        system.play(on: [])
        change()
        // Nothing plays for a long while, then something does: the count starts again.
        scheduler.advance(by: .seconds(60))
        system.play(on: ["A"])
        change()
        scheduler.advance(by: .seconds(8))
        #expect(!events.all.contains(.permissionLikelyDenied))
    }

    // MARK: Helpers

    // MARK: Loudness compensation

    /// A chain set up the way the manager should for `profile` on a device at `volume`.
    private func compensated(_ profile: EQProfile, volume: Double?, sampleRate: Double = 48_000) -> (gains: [Double], preampDB: Double) {
        LoudnessCompensation.apply(volume: volume, gains: profile.gains, preampDB: profile.preamp, sampleRate: sampleRate)
    }

    @Test func compensationFollowsTheDeviceVolume() throws {
        let profile = bandBoost(band: 5, by: 3)
        system.setVolume(0.25, of: "A")
        system.play(on: ["A"])
        manager.start()
        manager.apply(profile)
        manager.setLoudnessCompensation(true)
        let pipeline = try #require(system.pipeline("A"))

        let reference = EQChain(channels: 8)
        let quiet = compensated(profile, volume: 0.25)
        reference.setParameters(gains: quiet.gains, preampDB: quiet.preampDB, sampleRate: 48_000)
        #expect(render(pipeline.chain, frequency: 40) == render(reference, frequency: 40))

        // The volume key: the filters follow at once, with no debounce and no rebuild.
        system.setVolume(0.1, of: "A")
        system.fireVolumeChange()
        let quieter = compensated(profile, volume: 0.1)
        reference.setParameters(gains: quieter.gains, preampDB: quieter.preampDB, sampleRate: 48_000)
        #expect(render(pipeline.chain, frequency: 40) == render(reference, frequency: 40))
        #expect(system.attempts == ["A"])
        #expect(pipeline.tearDownCount == 0)
        #expect(scheduler.pendingCount <= 1)
    }

    @Test func atNormalVolumeTheProfileIsAppliedAsItIs() throws {
        let profile = bandBoost(band: 0, by: 6)
        system.setVolume(0.8, of: "A")
        system.play(on: ["A"])
        manager.start()
        manager.apply(profile)
        manager.setLoudnessCompensation(true)
        let pipeline = try #require(system.pipeline("A"))
        #expect(render(pipeline.chain, frequency: 40) == render(reference(profile, sampleRate: 48_000), frequency: 40))
    }

    @Test func aDeviceWithoutVolumeGetsNoCompensation() throws {
        let profile = bandBoost(band: 0, by: 6)
        system.setVolume(nil, of: "A")
        system.play(on: ["A"])
        manager.start()
        manager.apply(profile)
        manager.setLoudnessCompensation(true)
        let pipeline = try #require(system.pipeline("A"))
        #expect(render(pipeline.chain, frequency: 40) == render(reference(profile, sampleRate: 48_000), frequency: 40))
    }

    @Test func switchedOffIgnoresTheVolume() throws {
        let profile = bandBoost(band: 0, by: 6)
        system.setVolume(0.1, of: "A")
        system.play(on: ["A"])
        manager.start()
        manager.apply(profile)
        let pipeline = try #require(system.pipeline("A"))
        let reads = system.volumeReads
        system.fireVolumeChange()
        // Off: the volume is not even read, and the chain has the plain profile.
        #expect(system.volumeReads == reads)
        #expect(render(pipeline.chain, frequency: 40) == render(reference(profile, sampleRate: 48_000), frequency: 40))
    }

    @Test func eachDeviceFollowsItsOwnVolume() throws {
        let profile = EQProfile.flat(named: "Phẳng")
        system.setVolume(0.1, of: "A")
        system.setVolume(1, of: "B")
        system.play(on: ["A", "B"])
        manager.setLoudnessCompensation(true)
        manager.start()
        manager.apply(profile)
        let quiet = try #require(system.pipeline("A"))
        let loud = try #require(system.pipeline("B"))
        // B at full volume is flat, so a sine comes out exactly as it went in; A is lifted in the bass.
        let flat = EQChain(channels: 8)
        #expect(render(loud.chain, frequency: 40) == render(flat, frequency: 40))
        #expect(render(quiet.chain, frequency: 40) != render(EQChain(channels: 8), frequency: 40))
    }

    private func bandBoost(band: Int, by gain: Double) -> EQProfile {
        var profile = EQProfile.flat(named: "Một băng")
        profile.gains[band] = gain
        return profile
    }

    /// A chain set up directly, to compare what a manager's chain does against.
    private func reference(_ profile: EQProfile, sampleRate: Double) -> EQChain {
        let chain = EQChain(channels: 8)
        chain.setParameters(gains: profile.gains, preampDB: profile.preamp, sampleRate: sampleRate)
        return chain
    }
}
