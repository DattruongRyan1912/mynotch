import EqualizerDSP
import Foundation
import MyNotchCore

nonisolated public enum EqualizerEngineEvent: Equatable, Sendable {
    /// Names of the devices being processed, sorted. Sent when the list changes, and again when sound returns after
    /// `permissionLikelyDenied`, so the listener can drop its hint.
    case devices([String])
    case permissionLikelyDenied
    /// One device could not be set up after all its retries; the others keep running and the next change tries again.
    case failed(String)
}

@MainActor public protocol EqualizerEngine: AnyObject {
    var onEvent: ((EqualizerEngineEvent) -> Void)? { get set }
    func start()
    func stop()
    func apply(_ profile: EQProfile)
}

/// Keeps one pipeline on every output device that other processes are playing to, and none anywhere else.
///
/// Whenever Core Audio reports a change it waits for the burst to end, then compares the devices that are playing with the
/// pipelines it has: a new device gets one, a quiet or vanished device loses its own, and a device whose sample rate moved is
/// rebuilt (its filters are computed for the old rate).
///
/// A build that fails is tried again after 1 s, then 3 s, and then given up on for as long as that device keeps playing. Building and
/// destroying a pipeline stirs Core Audio up itself, so a notification must never restart that count: only the device leaving
/// (or `stop`) does.
@MainActor public final class PipelineManager: EqualizerEngine {
    /// Device changes arrive in bursts (a new default device often changes the sample rate too).
    static let debounce = Duration.milliseconds(300)
    static let retryDelays: [Duration] = [.seconds(1), .seconds(3)]
    static let silenceCheckInterval = Duration.seconds(1)
    /// Room for stereo, 5.1 and 7.1. The chain is made before the stream's width is known; a wider stream is only filtered this far.
    static let maxChannels = 8

    private struct Entry {
        let handle: any PipelineHandle
        let chain: EQChain
        let name: String
        /// What the chain was computed for.
        let sampleRate: Double
    }

    public var onEvent: ((EqualizerEngineEvent) -> Void)?

    private let system: any AudioSystem
    private let scheduler: any Scheduler
    private var isRunning = false
    private var observation: AnyObject?
    private var profile = EQProfile.flat(named: "")
    private var pipelines: [String: Entry] = [:]
    /// The names last sent as `.devices`.
    private var announced: [String] = []

    private struct Failure {
        var attempts = 0
        /// Set while the device waits for its own retry; a look at the devices leaves it alone.
        var retry: ScheduledAction?
        var gaveUp = false
    }

    private var pendingLook: ScheduledAction?
    /// Per device that is playing but has no pipeline because its builds failed.
    private var failing: [String: Failure] = [:]

    private var silenceCheck: ScheduledAction?
    private var detector = SilenceDetector()
    /// Seconds of checks so far. Counted rather than read from a clock, so a sleeping Mac does not count as silence.
    private var elapsed: TimeInterval = 0

    public init(system: any AudioSystem = CoreAudioSystem(), scheduler: any Scheduler) {
        self.system = system
        self.scheduler = scheduler
    }

    /// A dropped manager must not keep a device muted.
    isolated deinit { stop() }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        observation = system.observeChanges { [weak self] in
            // Delivered on the main thread (see `AudioSystem`).
            MainActor.assumeIsolated { self?.systemChanged() }
        }
        reconcile()
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        observation = nil
        for action in [pendingLook, silenceCheck] { action?.cancel() }
        for failure in failing.values { failure.retry?.cancel() }
        pendingLook = nil
        silenceCheck = nil
        failing = [:]
        for entry in pipelines.values { entry.handle.tearDown() }
        pipelines = [:]
        detector = SilenceDetector()
        elapsed = 0
        announceDevices()
    }

    public func apply(_ profile: EQProfile) {
        self.profile = profile.clamped()
        for entry in pipelines.values { configure(entry.chain, sampleRate: entry.sampleRate) }
    }

    private func configure(_ chain: EQChain, sampleRate: Double) {
        chain.setParameters(gains: profile.gains, preampDB: profile.preamp, sampleRate: sampleRate)
    }

    private func systemChanged() {
        guard isRunning, pendingLook == nil else { return }
        pendingLook = scheduler.schedule(after: Self.debounce) { [weak self] in
            self?.pendingLook = nil
            self?.reconcile()
        }
    }

    private func reconcile() {
        guard isRunning else { return }
        let wanted = system.activeOutputDeviceUIDs()
        // A device that stopped playing has nothing left to retry, and a verdict that it failed no longer holds.
        for uid in failing.keys where !wanted.contains(uid) {
            failing[uid]?.retry?.cancel()
            failing[uid] = nil
        }
        for (uid, entry) in pipelines where !wanted.contains(uid) || entry.handle.sampleRate != entry.sampleRate {
            entry.handle.tearDown()
            pipelines[uid] = nil
        }
        var gaveUp: [String] = []
        for uid in wanted.sorted() where pipelines[uid] == nil {
            // Waiting for its own retry, or given up: not for a look to decide, whatever stirred it up.
            if let failure = failing[uid], failure.retry != nil || failure.gaveUp { continue }
            let name = system.deviceName(uid: uid) ?? uid
            let chain = EQChain(channels: Self.maxChannels)
            do {
                let handle = try system.makePipeline(deviceUID: uid, chain: chain)
                let rate = handle.sampleRate
                configure(chain, sampleRate: rate)
                pipelines[uid] = Entry(handle: handle, chain: chain, name: name, sampleRate: rate)
                failing[uid] = nil
            } catch {
                if let message = buildFailed(uid, name: name, error) { gaveUp.append(message) }
            }
        }
        announceDevices()
        updateSilenceCheck()
        for message in gaveUp { onEvent?(.failed(message)) }
    }

    /// Schedules the device's next try, or returns what to tell the user when there are none left.
    private func buildFailed(_ uid: String, name: String, _ error: any Error) -> String? {
        var failure = failing[uid] ?? Failure()
        failure.attempts += 1
        defer { failing[uid] = failure }
        guard failure.attempts <= Self.retryDelays.count else {
            failure.gaveUp = true
            return "\(name): \(error.localizedDescription)"
        }
        failure.retry = scheduler.schedule(after: Self.retryDelays[failure.attempts - 1]) { [weak self] in
            self?.failing[uid]?.retry = nil
            self?.reconcile()
        }
        return nil
    }

    private func announceDevices() {
        let names = pipelines.values.map(\.name).sorted()
        guard names != announced else { return }
        announced = names
        onEvent?(.devices(names))
    }

    // MARK: Permission

    /// Runs only while there are pipelines, so nothing ticks when nothing plays.
    private func updateSilenceCheck() {
        if pipelines.isEmpty {
            silenceCheck?.cancel()
            silenceCheck = nil
            detector = SilenceDetector()
            elapsed = 0
        } else if silenceCheck == nil {
            scheduleSilenceCheck()
        }
    }

    private func scheduleSilenceCheck() {
        silenceCheck = scheduler.schedule(after: Self.silenceCheckInterval) { [weak self] in self?.checkSilence() }
    }

    private func checkSilence() {
        silenceCheck = nil
        guard isRunning, !pipelines.isEmpty else { return }
        elapsed += 1
        // Exact zeros from every tap while something is playing: the sign of a denied "System Audio Recording" permission.
        let peak = pipelines.values.map { $0.handle.takePeak() }.max() ?? 0
        switch detector.update(peak: peak, at: elapsed) {
        case true?: onEvent?(.permissionLikelyDenied)
        case false?: onEvent?(.devices(announced))
        case nil: break
        }
        scheduleSilenceCheck()
    }
}
