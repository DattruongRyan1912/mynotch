import AudioToolbox
import AVFoundation
import CoreAudio
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

        let quiet = compensated(profile, volume: 0.25)
        let reference = configuredReference(quiet)
        #expect(render(pipeline.chain, frequency: 40) == render(reference, frequency: 40))

        // The volume key: the filters follow at once, with no debounce and no rebuild.
        system.setVolume(0.1, of: "A")
        system.fireVolumeChange()
        let quieter = compensated(profile, volume: 0.1)
        let provider = AppleEQCoefficientProvider()
        let coefficients = provider.coefficients(gains: quieter.gains, sampleRate: 48_000)
        reference.setCoefficients(coefficients, preampDB: quieter.preampDB)
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

    @Test func switchedOffIgnoresTheVolumeForDSPFilters() throws {
        let profile = bandBoost(band: 0, by: 6)
        system.setVolume(0.1, of: "A")
        system.play(on: ["A"])
        manager.start()
        manager.apply(profile)
        let pipeline = try #require(system.pipeline("A"))
        var announcedTelemetries: [EQDeviceTelemetry] = []
        manager.onDeviceTelemetries = { telemetries in
            announcedTelemetries = telemetries
        }
        system.setVolume(0.5, of: "A")
        system.fireVolumeChange()
        // Off: the chain still has the plain profile without loudness boost
        #expect(render(pipeline.chain, frequency: 40) == render(reference(profile, sampleRate: 48_000), frequency: 40))
        // But telemetry reflects the real device volume and channel count regardless of loudness setting
        #expect(announcedTelemetries.first?.volumePercent == 50)
        #expect(announcedTelemetries.first?.channelCount == 2)
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

    // MARK: Apple EQ & Parity Tests

    @Test func appleEQCoefficientProviderReturnsIdentityWhenFlat() {
        let provider = AppleEQCoefficientProvider()
        let sampleRate = 48_000.0
        let flat = Array(repeating: 0.0, count: 10)
        let coeffs = provider.coefficients(gains: flat, sampleRate: sampleRate)
        #expect(coeffs.count == 10)
        for c in coeffs {
            #expect(c == .identity)
        }
    }

    @Test func appleEQCoefficientProviderGeneratesExactParametricCoefficientsAndDecodesABI() {
        let provider = AppleEQCoefficientProvider()
        let sampleRate = 48_000.0
        let gains = [6.0, -3.0, 4.0, -2.0, 5.0, -4.0, 3.0, -1.0, 2.0, -2.0]
        let coeffs = provider.coefficients(gains: gains, sampleRate: sampleRate)
        #expect(coeffs.count == 10)
        for (i, c) in coeffs.enumerated() {
            #expect(c.b0.isFinite && c.b1.isFinite && c.b2.isFinite && c.a1.isFinite && c.a2.isFinite)
            #expect(c != .identity, "Band \(i) with gain \(gains[i]) must produce active filter")
        }
    }

    @Test func appleEQNullTestAgainstNativeAudioUnitRender() {
        let provider = AppleEQCoefficientProvider()
        let sampleRate = 48_000.0
        let gains: [Float] = [6, -4, 8, -6, 3, -2, 5, -5, 4, -3]
        let doubleGains = gains.map { Double($0) }
        let coeffs = provider.coefficients(gains: doubleGains, sampleRate: sampleRate)

        // Set up native AVAudioUnitEQ oracle
        let eq = AVAudioUnitEQ(numberOfBands: 10)
        eq.globalGain = 0
        for i in 0..<10 {
            let band = eq.bands[i]
            band.filterType = .parametric
            band.frequency = Float(EQChain.frequencies[i])
            band.bandwidth = 0.5
            band.gain = gains[i]
            band.bypass = false
        }
        let audioUnit = eq.audioUnit

        var streamDesc = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagsNativeFloatPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        AudioUnitSetProperty(audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &streamDesc, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        AudioUnitSetProperty(audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &streamDesc, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        AudioUnitInitialize(audioUnit)

        let N = 128
        let inPtr = UnsafeMutablePointer<Float>.allocate(capacity: N)
        let outPtr = UnsafeMutablePointer<Float>.allocate(capacity: N)
        inPtr.initialize(repeating: 0, count: N)
        outPtr.initialize(repeating: 0, count: N)
        inPtr[0] = 1.0 // Impulse

        var abl = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(N * 4), mData: outPtr))

        let renderCallback: AURenderCallback = { (inRefCon, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, ioData) -> OSStatus in
            guard let ioData = ioData else { return noErr }
            let buf = ioData.pointee.mBuffers
            let src = inRefCon.assumingMemoryBound(to: Float.self)
            let dst = buf.mData!.assumingMemoryBound(to: Float.self)
            for i in 0..<Int(inNumberFrames) { dst[i] = src[i] }
            return noErr
        }

        var cb = AURenderCallbackStruct(inputProc: renderCallback, inputProcRefCon: inPtr)
        AudioUnitSetProperty(audioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &cb, UInt32(MemoryLayout<AURenderCallbackStruct>.size))

        var flags: AudioUnitRenderActionFlags = []
        var ts = AudioTimeStamp()
        ts.mSampleTime = 0
        ts.mFlags = .sampleTimeValid
        AudioUnitRender(audioUnit, &flags, &ts, 0, UInt32(N), &abl)

        // Simulate our cascade with decoded Apple coefficients
        struct BiquadState { var z1: Double = 0; var z2: Double = 0 }
        var states = [BiquadState](repeating: BiquadState(), count: 10)
        var simOut = [Double](repeating: 0, count: N)
        for frame in 0..<N {
            var val: Double = (frame == 0) ? 1.0 : 0.0
            for band in 0..<10 {
                let c = coeffs[band]
                let out = c.b0 * val + states[band].z1
                states[band].z1 = c.b1 * val - c.a1 * out + states[band].z2
                states[band].z2 = c.b2 * val - c.a2 * out
                val = out
            }
            simOut[frame] = val
        }

        var sumSqResidual: Double = 0
        var sumSqRef: Double = 0
        var maxDiff: Double = 0
        for frame in 0..<N {
            let ref = Double(outPtr[frame])
            let diff = abs(simOut[frame] - ref)
            maxDiff = max(maxDiff, diff)
            sumSqResidual += diff * diff
            sumSqRef += ref * ref
        }

        let rmsResidual = sqrt(sumSqResidual / Double(N))
        let rmsRef = sqrt(sumSqRef / Double(N))
        let residualDB = 20 * log10(rmsResidual / rmsRef)

        inPtr.deallocate()
        outPtr.deallocate()
        AudioUnitUninitialize(audioUnit)

        #expect(maxDiff < 1e-5, "Maximum absolute difference should be < 1e-5, got \(maxDiff)")
        #expect(residualDB <= -80.0, "Normalized RMS residual must be <= -80 dB, got \(residualDB) dB")
    }

    @Test func appleEQNullTestAtPlusMinus24DB() {
        let provider = AppleEQCoefficientProvider()
        let sampleRate = 48_000.0
        let gains: [Float] = [24, -24, 14, -14, 24, -24, 10, -10, 20, -20]
        let doubleGains = gains.map { Double($0) }
        let coeffs = provider.coefficients(gains: doubleGains, sampleRate: sampleRate)

        let eq = AVAudioUnitEQ(numberOfBands: 10)
        eq.globalGain = 0
        for i in 0..<10 {
            let band = eq.bands[i]
            band.filterType = .parametric
            band.frequency = Float(EQChain.frequencies[i])
            band.bandwidth = 0.5
            band.gain = gains[i]
            band.bypass = false
        }
        let audioUnit = eq.audioUnit

        var streamDesc = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagsNativeFloatPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )

        AudioUnitSetProperty(audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &streamDesc, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        AudioUnitSetProperty(audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &streamDesc, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        AudioUnitInitialize(audioUnit)

        let N = 128
        let inPtr = UnsafeMutablePointer<Float>.allocate(capacity: N)
        let outPtr = UnsafeMutablePointer<Float>.allocate(capacity: N)
        inPtr.initialize(repeating: 0, count: N)
        outPtr.initialize(repeating: 0, count: N)
        inPtr[0] = 1.0

        var abl = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(N * 4), mData: outPtr))

        let renderCallback: AURenderCallback = { (inRefCon, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, ioData) -> OSStatus in
            guard let ioData = ioData else { return noErr }
            let buf = ioData.pointee.mBuffers
            let src = inRefCon.assumingMemoryBound(to: Float.self)
            let dst = buf.mData!.assumingMemoryBound(to: Float.self)
            for i in 0..<Int(inNumberFrames) { dst[i] = src[i] }
            return noErr
        }

        var cb = AURenderCallbackStruct(inputProc: renderCallback, inputProcRefCon: inPtr)
        AudioUnitSetProperty(audioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &cb, UInt32(MemoryLayout<AURenderCallbackStruct>.size))

        var flags: AudioUnitRenderActionFlags = []
        var ts = AudioTimeStamp()
        ts.mSampleTime = 0
        ts.mFlags = .sampleTimeValid
        AudioUnitRender(audioUnit, &flags, &ts, 0, UInt32(N), &abl)

        struct BiquadState { var z1: Double = 0; var z2: Double = 0 }
        var states = [BiquadState](repeating: BiquadState(), count: 10)
        var simOut = [Double](repeating: 0, count: N)
        for frame in 0..<N {
            var val: Double = (frame == 0) ? 1.0 : 0.0
            for band in 0..<10 {
                let c = coeffs[band]
                let out = c.b0 * val + states[band].z1
                states[band].z1 = c.b1 * val - c.a1 * out + states[band].z2
                states[band].z2 = c.b2 * val - c.a2 * out
                val = out
            }
            simOut[frame] = val
        }

        var sumSqResidual: Double = 0
        var sumSqRef: Double = 0
        var maxDiff: Double = 0
        for frame in 0..<N {
            let ref = Double(outPtr[frame])
            let diff = abs(simOut[frame] - ref)
            maxDiff = max(maxDiff, diff)
            sumSqResidual += diff * diff
            sumSqRef += ref * ref
        }

        let rmsResidual = sqrt(sumSqResidual / Double(N))
        let rmsRef = sqrt(sumSqRef / Double(N))
        let residualDB = 20 * log10(rmsResidual / rmsRef)

        inPtr.deallocate()
        outPtr.deallocate()
        AudioUnitUninitialize(audioUnit)

        #expect(maxDiff < 1e-5, "Maximum absolute difference at ±24 dB should be < 1e-5, got \(maxDiff)")
        #expect(residualDB <= -80.0, "Normalized RMS residual at ±24 dB must be <= -80 dB, got \(residualDB) dB")
    }

    @Test func instantaneousLimiterGuaranteesZeroOverloadWithDirectPositivePreampAndMaxBoost() throws {
        // Boost all 10 bands to +12 dB with positive preamp +12 dB
        var profile = EQProfile.flat(named: "Mega Boost Overdrive")
        profile.gains = Array(repeating: 12.0, count: 10)
        profile.preamp = 12.0

        system.play(on: ["A"])
        manager.start()
        manager.apply(profile)

        let pipeline = try #require(system.pipeline("A"))
        let chain = pipeline.chain

        // Render high-amplitude sine (0.8 amplitude, which with +24 dB total boost reaches ~12.0 without limiter)
        let frames = 480
        let buffer = TestBufferList([.init(channels: 1, frames: frames)])
        var pos = 0
        for _ in 0..<8 {
            let sine = (0..<frames).map { i in Float(0.8 * sin(2 * Double.pi * 1000 * Double(pos + i) / 48_000)) }
            pos += frames
            buffer.fill(0, with: sine)
            chain.process(buffer.list, frames: frames)
        }
        let samples = buffer.samples(0)
        #expect(samples.allSatisfy { $0.isFinite && Double(abs($0)) <= EQChain.limiterCeiling + 1e-5 }, "All output samples must be finite and within ceiling")
        let maxPeak = samples.map(abs).max() ?? 0
        #expect(Double(maxPeak) > EQChain.limiterCeiling * 0.80 && Double(maxPeak) <= EQChain.limiterCeiling + 1e-5, "Limiter must clamp right at ceiling, got \(maxPeak)")
    }

    @Test func boostedBandsDoNotAttenuateUnboostedFrequenciesOrPositivePreamp() throws {
        // Boost low frequencies (32, 64, 125 Hz) by +8, +6, +3 dB, mid/high at 0 dB, preamp at 0
        var profile = EQProfile.flat(named: "Bass Boost")
        profile.gains = [8, 6, 3, 0, 0, 0, 0, 0, 0, 0]
        profile.preamp = 0.0

        system.play(on: ["A"])
        manager.start()
        manager.apply(profile)

        let pipeline = try #require(system.pipeline("A"))
        let chain = pipeline.chain

        // Render 4000 Hz sine (where gain is 0 dB) with continuous phase and exact integer frames
        let frames = 480
        let testFreq = 4000.0
        let buffer = TestBufferList([.init(channels: 1, frames: frames)])
        var pos = 0
        for _ in 0..<8 {
            let inputSine = (0..<frames).map { i in Float(0.2 * sin(2 * Double.pi * testFreq * Double(pos + i) / 48_000)) }
            pos += frames
            buffer.fill(0, with: inputSine)
            chain.process(buffer.list, frames: frames)
        }
        let outSamples = buffer.samples(0)
        let inMax: Float = 0.2
        let outMax = outSamples.map(abs).max() ?? 0
        let gainRatio = outMax / inMax
        // Must NOT be attenuated down to ~0.5 (-6 dB), must remain transparent within [0.98, 1.02] at 4000 Hz
        #expect(gainRatio > 0.98 && gainRatio < 1.02, "4000 Hz unboosted signal should not be attenuated, got ratio \(gainRatio)")

        // Now test positive preamp (+6 dB = ~1.995x)
        profile.preamp = 6.0
        manager.apply(profile)
        for _ in 0..<8 {
            let inputSine = (0..<frames).map { i in Float(0.2 * sin(2 * Double.pi * testFreq * Double(pos + i) / 48_000)) }
            pos += frames
            buffer.fill(0, with: inputSine)
            chain.process(buffer.list, frames: frames)
        }
        let boostedOutSamples = buffer.samples(0)
        let boostedOutMax = boostedOutSamples.map(abs).max() ?? 0
        let boostedGainRatio = boostedOutMax / inMax
        #expect(boostedGainRatio > 1.90 && boostedGainRatio < 2.10, "Preamp +6 dB must increase gain to ~1.995x, got \(boostedGainRatio)")
    }

    // MARK: - Auto-Headroom Integration Tests (N1 - N6)

    @Test func n1_autoHeadroomDefaultOffDoesNotAlterOutput() throws {
        system.play(on: ["A"])
        manager.start()

        var profile = EQProfile.flat()
        profile.gains[0] = 14.0
        manager.apply(profile)

        let pipeline = try #require(system.pipeline("A"))
        let ref = configuredReference((profile.gains, profile.preamp))
        let managerOut = render(pipeline.chain)
        let refOut = render(ref)
        #expect(managerOut == refOut, "Default OFF autoHeadroom must match unmodified reference output")
    }

    @Test func n2_autoHeadroomAppliesHeadroomOffsetMatchingPeak() throws {
        system.play(on: ["A"])
        manager.start()

        var profile = EQProfile.flat()
        profile.gains[0] = 14.0
        manager.apply(profile)
        manager.setProcessingSettings(ceilingDBTP: -0.5, loudnessRefVolume: 0.75, loudnessMaxBassDB: 8.0, loudnessMaxTrebleDB: 4.0, autoHeadroom: true)

        let pipeline = try #require(system.pipeline("A"))
        let provider = AppleEQCoefficientProvider()
        let coeffs = provider.coefficients(gains: profile.gains, sampleRate: 48_000)
        let peakDB = BiquadCoefficients.cascadePeakDB(coeffs, sampleRate: 48_000)
        let expectedHeadroom = -peakDB

        let refChain = EQChain(channels: 8)
        refChain.setCoefficients(coeffs, preampDB: profile.preamp, sampleRate: 48_000, headroomDB: expectedHeadroom)

        let managerOut = render(pipeline.chain)
        let refOut = render(refChain)
        #expect(managerOut == refOut, "Chain with autoHeadroom ON must match reference with headroomDB = -cascadePeakDB")
    }

    @Test func n3_togglingAutoHeadroomReconfiguresChain() throws {
        system.play(on: ["A"])
        manager.start()

        var profile = EQProfile.flat()
        profile.gains[0] = 14.0
        manager.apply(profile)

        let pipeline = try #require(system.pipeline("A"))

        // Initial state: autoHeadroom is false
        manager.setProcessingSettings(ceilingDBTP: EQChain.limiterCeilingDB, loudnessRefVolume: 0.75, loudnessMaxBassDB: 8.0, loudnessMaxTrebleDB: 4.0, autoHeadroom: false)
        let initialOut = render(pipeline.chain)
        let initialPeak = initialOut.map(abs).max() ?? 0

        // Turn ON: headroom must attenuate the chain
        manager.setProcessingSettings(ceilingDBTP: EQChain.limiterCeilingDB, loudnessRefVolume: 0.75, loudnessMaxBassDB: 8.0, loudnessMaxTrebleDB: 4.0, autoHeadroom: true)
        let onOut = render(pipeline.chain)
        let onPeak = onOut.map(abs).max() ?? 0
        #expect(onOut != initialOut, "Toggling autoHeadroom ON must reconfigure chain output")
        #expect(onPeak < initialPeak * 0.35, "Auto-headroom ON must attenuate output by ~14 dB, got peak \(onPeak) vs initial \(initialPeak)")

        // Turn OFF: chain must restore gain back to unattenuated level
        manager.setProcessingSettings(ceilingDBTP: EQChain.limiterCeilingDB, loudnessRefVolume: 0.75, loudnessMaxBassDB: 8.0, loudnessMaxTrebleDB: 4.0, autoHeadroom: false)
        let offOut = render(pipeline.chain)
        let offPeak = offOut.map(abs).max() ?? 0
        #expect(offOut != onOut, "Toggling autoHeadroom back OFF must reconfigure chain")
        #expect(offPeak > onPeak * 2.5, "Toggling autoHeadroom OFF must restore boost gain, got peak \(offPeak) vs attenuated \(onPeak)")
    }

    @Test func n4_flatProfileWithAutoHeadroomIsBitExactWithFlatReference() throws {
        system.play(on: ["A"])
        manager.start()

        manager.apply(EQProfile.flat())
        manager.setProcessingSettings(ceilingDBTP: -0.5, loudnessRefVolume: 0.75, loudnessMaxBassDB: 8.0, loudnessMaxTrebleDB: 4.0, autoHeadroom: true)

        let pipeline = try #require(system.pipeline("A"))
        let ref = configuredReference((EQProfile.flat().gains, EQProfile.flat().preamp))
        let managerOut = render(pipeline.chain)
        let refOut = render(ref)
        #expect(managerOut == refOut, "Flat profile with autoHeadroom ON must be bit-exact with flat reference")
    }

    @Test func n5_loudnessAndAutoHeadroomTogetherDoNotDoubleCompensate() throws {
        system.play(on: ["A"])
        system.setVolume(0.25, of: "A")
        system.fireVolumeChange()
        manager.start()

        var profile = EQProfile.flat()
        profile.preamp = 0.0
        manager.apply(profile)
        manager.setLoudnessCompensation(true)
        manager.setProcessingSettings(ceilingDBTP: -0.5, loudnessRefVolume: 0.75, loudnessMaxBassDB: 8.0, loudnessMaxTrebleDB: 4.0, autoHeadroom: true)

        let pipeline = try #require(system.pipeline("A"))
        let entryVol = 0.25
        let loudnessSettings = LoudnessCompensation.apply(
            volume: entryVol,
            gains: profile.gains,
            preampDB: profile.preamp,
            sampleRate: 48_000,
            referenceVolume: 0.75,
            maxBassDB: 8.0,
            maxTrebleDB: 4.0
        )

        let provider = AppleEQCoefficientProvider()
        let coeffs = provider.coefficients(gains: loudnessSettings.gains, sampleRate: 48_000)
        let peakDB = BiquadCoefficients.cascadePeakDB(coeffs, sampleRate: 48_000)

        // Effective preamp must be profile.preamp (not loudnessSettings.preampDB which subtracted lift)
        let refChain = EQChain(channels: 8)
        refChain.setCoefficients(coeffs, preampDB: profile.preamp, sampleRate: 48_000, headroomDB: -peakDB)

        let managerOut = render(pipeline.chain)
        let refOut = render(refChain)
        #expect(managerOut == refOut, "Loudness + autoHeadroom together must use profile.preamp and headroom = -peak")
    }

    @Test func n6_cutOnlyProfileRendersIdenticallyWithAutoHeadroomOnOrOff() throws {
        system.play(on: ["A"])
        manager.start()

        var profile = EQProfile.flat()
        profile.gains = Array(repeating: -6.0, count: 10)
        manager.apply(profile)

        let pipeline = try #require(system.pipeline("A"))
        let ref = configuredReference((profile.gains, profile.preamp))

        manager.setProcessingSettings(ceilingDBTP: -0.5, loudnessRefVolume: 0.75, loudnessMaxBassDB: 8.0, loudnessMaxTrebleDB: 4.0, autoHeadroom: false)
        let offOut = render(pipeline.chain)
        #expect(offOut == render(ref), "Cut-only profile must render identically to reference with autoHeadroom OFF")

        manager.setProcessingSettings(ceilingDBTP: -0.5, loudnessRefVolume: 0.75, loudnessMaxBassDB: 8.0, loudnessMaxTrebleDB: 4.0, autoHeadroom: true)
        let onOut = render(pipeline.chain)
        let refOut = render(ref)
        #expect(onOut == refOut, "Cut-only profile must render identically to reference with autoHeadroom ON")
    }

    private func configuredReference(_ settings: (gains: [Double], preampDB: Double), sampleRate: Double = 48_000) -> EQChain {
        let provider = AppleEQCoefficientProvider()
        let chain = EQChain(channels: 8)
        let coefficients = provider.coefficients(gains: settings.gains, sampleRate: sampleRate)
        chain.setCoefficients(coefficients, preampDB: settings.preampDB)
        return chain
    }

    /// A chain set up directly, to compare what a manager's chain does against.
    private func reference(_ profile: EQProfile, sampleRate: Double) -> EQChain {
        configuredReference((profile.gains, profile.preamp), sampleRate: sampleRate)
    }
}
