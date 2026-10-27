import CoreAudio
import EqualizerDSP
import Foundation
import Synchronization
@testable import EqualizerAudio

struct FakeFailure: LocalizedError, Equatable {
    var errorDescription: String? { "fake failure" }
}

/// A pipeline that touches nothing: it records how often it was torn down and reports whatever the test sets.
nonisolated final class FakePipeline: PipelineHandle, @unchecked Sendable {
    private struct State {
        var rate: Double
        var peak: Float
        var tearDowns = 0
    }

    let deviceUID: String
    let chain: EQChain
    private let state: Mutex<State>
    private let undo: TeardownStack

    init(deviceUID: String, chain: EQChain, rate: Double, peak: Float, undo: TeardownStack) {
        self.deviceUID = deviceUID
        self.chain = chain
        self.undo = undo
        state = Mutex(State(rate: rate, peak: peak))
    }

    var sampleRate: Double { state.withLock { $0.rate } }
    var tearDownCount: Int { state.withLock { $0.tearDowns } }
    func setSampleRate(_ rate: Double) { state.withLock { $0.rate = rate } }
    func setPeak(_ peak: Float) { state.withLock { $0.peak = peak } }
    func takePeak() -> Float { state.withLock { $0.peak } }
    func tearDown() {
        state.withLock { $0.tearDowns += 1 }
        undo.unwind()
    }
}

/// What `observeChanges` hands back: dropping it is how the manager stops listening.
nonisolated final class FakeObservation: Sendable {
    let handler: @Sendable () -> Void
    let volumeChanged: @Sendable () -> Void
    init(handler: @escaping @Sendable () -> Void, volumeChanged: @escaping @Sendable () -> Void) {
        self.handler = handler
        self.volumeChanged = volumeChanged
    }
}

/// A scripted `AudioSystem`: the test decides which devices are playing and which builds fail. Never touches Core Audio.
nonisolated final class FakeAudioSystem: AudioSystem, @unchecked Sendable {
    enum Failure: Equatable, Sendable {
        /// Fails before anything exists, so there is nothing to undo.
        case immediately
        /// A tap was made, then the aggregate device failed: the fake undoes the tap before it throws, as the real one must.
        case afterTap
    }

    private struct State {
        var active: Set<String> = []
        var names: [String: String] = [:]
        var rate = 48_000.0
        var peak: Float = 0.5
        var echoes = false
        var failures: [String: [Failure]] = [:]
        var attempts: [String] = []
        var pipelines: [FakePipeline] = []
        var queries = 0
        var volumes: [String: Double] = [:]
        var volumeReads = 0
        weak var observation: FakeObservation?
    }

    private let state = Mutex(State())
    private let taps = Mutex(0)

    var ownProcessID: AudioObjectID? { 4242 }

    func activeOutputDeviceUIDs() -> Set<String> {
        state.withLock {
            $0.queries += 1
            return $0.active
        }
    }

    func deviceName(uid: String) -> String? { state.withLock { $0.names[uid] } }

    func outputVolume(uid: String) -> Double? {
        state.withLock {
            $0.volumeReads += 1
            return $0.volumes[uid]
        }
    }

    func makePipeline(deviceUID: String, chain: EQChain) throws -> any PipelineHandle {
        // Core Audio is stirred up by every tap, aggregate device and IO proc that is made or destroyed, whether or not it works.
        defer { if state.withLock({ $0.echoes }) { fireChange() } }
        return try state.withLock { state in
            state.attempts.append(deviceUID)
            let failure = state.failures[deviceUID]?.first
            if failure != nil { state.failures[deviceUID]?.removeFirst() }
            if failure == .immediately { throw FakeFailure() }
            // A step that succeeds registers its undo, the way the real pipeline does.
            let undo = TeardownStack()
            taps.withLock { $0 += 1 }
            undo.push { [weak self] in self?.taps.withLock { $0 -= 1 } }
            if failure == .afterTap {
                undo.unwind()
                throw FakeFailure()
            }
            let pipeline = FakePipeline(deviceUID: deviceUID, chain: chain, rate: state.rate, peak: state.peak, undo: undo)
            state.pipelines.append(pipeline)
            return pipeline
        }
    }

    func observeChanges(_ handler: @escaping @Sendable () -> Void, volumeChanged: @escaping @Sendable () -> Void) -> AnyObject {
        let observation = FakeObservation(handler: handler, volumeChanged: volumeChanged)
        state.withLock { $0.observation = observation }
        return observation
    }

    // MARK: Scripting

    func play(on devices: Set<String>) { state.withLock { $0.active = devices } }
    func name(_ uid: String, as name: String) { state.withLock { $0.names[uid] = name } }
    func setRateForNewPipelines(_ rate: Double) { state.withLock { $0.rate = rate } }
    /// Makes every `makePipeline` call end with a change notification, as the real one does.
    func echoOnEveryMake(_ echoes: Bool = true) { state.withLock { $0.echoes = echoes } }
    func setPeakForNewPipelines(_ peak: Float) { state.withLock { $0.peak = peak } }
    /// A device without an entry has no volume.
    func setVolume(_ volume: Double?, of uid: String) { state.withLock { $0.volumes[uid] = volume } }
    /// Tells the manager a volume moved, as Core Audio would.
    func fireVolumeChange() {
        let handler = state.withLock { $0.observation?.volumeChanged }
        handler?()
    }
    func failBuilds(of uid: String, _ failures: [Failure]) { state.withLock { $0.failures[uid] = failures } }

    /// Tells the manager something changed, as Core Audio would. Does nothing once the manager dropped its token.
    func fireChange() {
        let handler = state.withLock { $0.observation?.handler }
        handler?()
    }

    // MARK: Observing

    /// Taps made and not yet destroyed.
    var liveTaps: Int { taps.withLock { $0 } }
    var isObserved: Bool { state.withLock { $0.observation != nil } }
    var attempts: [String] { state.withLock { $0.attempts } }
    var pipelines: [FakePipeline] { state.withLock { $0.pipelines } }
    var queries: Int { state.withLock { $0.queries } }
    var volumeReads: Int { state.withLock { $0.volumeReads } }
    func pipeline(_ uid: String) -> FakePipeline? { pipelines.last { $0.deviceUID == uid } }
}
