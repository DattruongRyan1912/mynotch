import EqualizerAudio
import MyNotchCore

/// An engine that touches no audio. Like `PipelineManager` it announces `.devices([])` from `stop()` when it had announced
/// devices, and the devices playing when `start()` runs: both arrive inside the call, which is how the module meets them.
final class FakeEngine: EqualizerEngine {
    var onEvent: ((EqualizerEngineEvent) -> Void)?
    /// What `start()` finds playing.
    var playing: [String] = []

    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var applied: [EQProfile] = []
    /// Every `setLoudnessCompensation` call, in order.
    private(set) var loudness: [Bool] = []
    /// "apply", "start" and "stop" in the order they were called.
    private(set) var calls: [String] = []
    private(set) var isRunning = false
    private var announced: [String] = []

    func start() {
        startCount += 1
        calls.append("start")
        isRunning = true
        if !playing.isEmpty { emit(.devices(playing)) }
    }

    func stop() {
        stopCount += 1
        calls.append("stop")
        isRunning = false
        if !announced.isEmpty { emit(.devices([])) }
    }

    func apply(_ profile: EQProfile) {
        applied.append(profile)
        calls.append("apply")
    }

    func setLoudnessCompensation(_ enabled: Bool) {
        loudness.append(enabled)
        calls.append("loudness")
    }

    /// Sends an event as the real manager does: on the main actor, from inside whatever the manager was doing.
    func emit(_ event: EqualizerEngineEvent) {
        if case .devices(let names) = event { announced = names }
        onEvent?(event)
    }
}
