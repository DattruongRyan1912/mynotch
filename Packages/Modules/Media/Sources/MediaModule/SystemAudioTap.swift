import Accelerate
import CoreAudio
import Foundation
import MyNotchCore

/// The real `SpectrumSource`: a private Core Audio process tap of everything the system plays except MyNotch,
/// read through a private aggregate device on the default output device. macOS asks for "System Audio
/// Recording Only" the first time a tap starts. Never used by tests.
final class SystemAudioTap: SpectrumSource {
    private let bandCount: Int
    private var session: SystemAudioTapSession?
    /// Identifies the current session, so events still queued from a stopped one are dropped.
    private var sessionCount = 0

    init(bandCount: Int) {
        self.bandCount = bandCount
    }

    /// A dropped tap must not keep capturing.
    isolated deinit { stop() }

    func start(onEvent: @escaping @MainActor (SpectrumEvent) -> Void) {
        stop()
        sessionCount += 1
        let id = sessionCount
        let deliver: @MainActor (SpectrumEvent) -> Void = { [weak self] event in
            guard let self, self.sessionCount == id, self.session != nil else { return }
            onEvent(event)
        }
        let emit: @Sendable (SpectrumEvent) -> Void = { event in DispatchQueue.main.async { deliver(event) } }
        let session = SystemAudioTapSession(
            name: "MyNotch spectrum", consumer: SpectrumConsumer(bandCount: bandCount, emit: emit),
            onFailure: { emit(.failed($0)) }
        )
        self.session = session
        session.start()
    }

    func stop() {
        session?.stop()
        session = nil
    }
}

/// What reads the tapped audio, on the session's queue: a new ring after each (re)build, then about 30 times a second.
nonisolated protocol SystemAudioConsumer: AnyObject {
    func begin(ring: SampleRing, sampleRate: Double)
    func read()
    /// The ring is gone, until the next `begin`.
    func end()
}

/// The bars' levels: the latest frame of the ring, analysed about 30 times a second.
private nonisolated final class SpectrumConsumer: SystemAudioConsumer {
    static let frameCount = 1024

    private let bandCount: Int
    private let emit: @Sendable (SpectrumEvent) -> Void
    private var ring: SampleRing?
    private var analyzer: SpectrumAnalyzer?
    private var frame = [Float](repeating: 0, count: frameCount)
    private let silentFrame = [Float](repeating: 0, count: frameCount)
    /// Ring position after the previous analysis, to tell new samples from none.
    private var lastWritten = 0
    private var lastBands: [Float]?
    /// Kept across rebuilds: a denied permission does not come back with a new device.
    private var silence = SilenceDetector()

    init(bandCount: Int, emit: @escaping @Sendable (SpectrumEvent) -> Void) {
        self.bandCount = bandCount
        self.emit = emit
    }

    func begin(ring: SampleRing, sampleRate: Double) {
        self.ring = ring
        lastWritten = 0
        analyzer = SpectrumAnalyzer(frameCount: Self.frameCount, bandCount: bandCount, sampleRate: sampleRate)
    }

    func read() {
        guard let ring, analyzer != nil else { return }
        let end = ring.copyLatest(into: &frame)
        let isFresh = end.map { $0 > lastWritten } ?? false
        if let end { lastWritten = end }
        let peak = isFresh ? vDSP.maximumMagnitude(frame) : nil
        let now = Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
        if let likelyDenied = silence.update(peak: peak, at: now) {
            emit(.permissionLikelyDenied(likelyDenied))
        }
        // Without new samples the bars fall back to rest instead of freezing.
        guard let bands = analyzer?.process(isFresh ? frame : silentFrame), bands != lastBands else { return }
        lastBands = bands
        emit(.bands(bands))
    }

    func end() {
        ring = nil
        analyzer = nil
        lastBands = nil
    }
}

/// Everything that touches Core Audio, confined to one serial queue: setup, teardown, rebuilds after device
/// changes, and the consumer's reads about 30 times a second. The IO block only copies samples into a `SampleRing`.
nonisolated final class SystemAudioTapSession: @unchecked Sendable {
    static let frameCount = SpectrumConsumer.frameCount
    static let analysisInterval = DispatchTimeInterval.nanoseconds(1_000_000_000 / 30)
    /// About a third of a second at 48 kHz: many IO cycles fit between two analyses.
    static let ringCapacity = 16 * frameCount
    /// Device changes arrive in bursts (a new default device often changes the sample rate too).
    static let rebuildDelay = DispatchTimeInterval.milliseconds(300)

    static let rebuildRetryDelays: [DispatchTimeInterval] = [.seconds(1), .seconds(3)]

    private let queue: DispatchQueue
    /// What the tap and its aggregate device are called, for whoever looks at the audio devices.
    private let name: String
    private let consumer: any SystemAudioConsumer
    private let onFailure: @Sendable (String) -> Void
    private let logger = Log.logger(category: "media")

    // Everything below is only touched on `queue`.
    private var isStopped = false
    private var isRebuildPending = false
    private var tap: AudioHardwareTap?
    private var aggregate: AudioHardwareAggregateDevice?
    private var ioProc: AudioDeviceIOProcID?
    private var listeners: [AudioPropertyListener] = []
    private var timer: DispatchSourceTimer?

    /// `consumer` is only called on the session's queue; `onFailure` hears why the tap could not be set up, once.
    init(name: String, consumer: any SystemAudioConsumer, onFailure: @escaping @Sendable (String) -> Void) {
        self.name = name
        self.consumer = consumer
        self.onFailure = onFailure
        queue = DispatchQueue(label: "io.lucasvu.mynotch.media.\(name)", qos: .userInitiated)
    }

    func start() {
        queue.async { self.build() }
    }

    func stop() {
        queue.async {
            self.isStopped = true
            self.tearDown()
        }
    }

    private func build() {
        guard !isStopped else { return }
        do {
            try setUp()
        } catch {
            fail(error)
        }
    }

    private func fail(_ error: any Error) {
        tearDown()
        isStopped = true
        onFailure(error.localizedDescription)
    }

    /// A rebuild right after a device change can hit a device that is not ready yet, so it tries again after
    /// each of these delays before giving up. The first start does not retry: it fails on a real problem.
    private func rebuild(retryDelays: ArraySlice<DispatchTimeInterval> = SystemAudioTapSession.rebuildRetryDelays[...]) {
        guard !isStopped else { return }
        tearDown()
        do {
            try setUp()
        } catch {
            guard let delay = retryDelays.first else { return fail(error) }
            logger.notice("Rebuilding the system audio tap failed, retrying: \(error.localizedDescription, privacy: .public)")
            tearDown()
            queue.asyncAfter(deadline: .now() + delay) { self.rebuild(retryDelays: retryDelays.dropFirst()) }
        }
    }

    private func setUp() throws {
        let system = AudioHardwareSystem.shared
        // MyNotch's own sounds stay out of the bars; it has no process object until it has played something.
        let ownProcess = try? system.process(for: getpid())
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: ownProcess.map { [$0.id] } ?? [])
        description.name = name
        description.isPrivate = true
        description.muteBehavior = .unmuted
        guard let tap = try system.makeProcessTap(description: description) else { throw TapError("no process tap") }
        self.tap = tap
        let format = try tap.format
        guard format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32, format.mSampleRate > 0 else {
            throw TapError("unsupported tap format \(format.mFormatID) / \(format.mBitsPerChannel) bit")
        }
        guard let output = try system.defaultOutputDevice else { throw TapError("no default output device") }
        let outputUID = try output.uid
        guard let aggregate = try system.makeAggregateDevice(description: [
            kAudioAggregateDeviceNameKey: name,
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            // Run from the start rather than wait for the first tapped audio: a denied tap then still
            // delivers its silence, and starting never waits on this queue.
            kAudioAggregateDeviceTapAutoStartKey: false,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: try tap.uid, kAudioSubTapDriftCompensationKey: true]],
        ]) else { throw TapError("no aggregate device") }
        self.aggregate = aggregate

        let ring = SampleRing(capacity: Self.ringCapacity)
        consumer.begin(ring: ring, sampleRate: format.mSampleRate)
        var ioProc: AudioDeviceIOProcID?
        try check(AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregate.id, nil, Self.ioBlock(writingTo: ring)), "create the IO proc")
        self.ioProc = ioProc
        try check(AudioDeviceStart(aggregate.id, ioProc), "start the aggregate device")

        // A new default output device, or a new sample rate on it, needs a new aggregate device and analyzer.
        let rebuild: @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            queue.async { self.scheduleRebuild() }
        }
        let watched = [
            (AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice),
            (output.id, kAudioDevicePropertyNominalSampleRate),
            (tap.id, kAudioTapPropertyFormat),
        ]
        // One at a time, so a failure leaves the ones already added for `tearDown` to remove.
        for (object, selector) in watched {
            listeners.append(try AudioPropertyListener(object: object, selector: selector, onChange: rebuild))
        }
        startTimer()
    }

    /// Runs on Core Audio's real-time thread: no allocation, no locks, no actors, only the copy into the ring.
    private static func ioBlock(writingTo ring: SampleRing) -> AudioDeviceIOBlock {
        { _, input, _, _, _ in ring.write(input) }
    }

    private func startTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.analysisInterval, repeating: Self.analysisInterval, leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in self?.consumer.read() }
        timer.resume()
        self.timer = timer
    }

    private func scheduleRebuild() {
        guard !isStopped, !isRebuildPending else { return }
        isRebuildPending = true
        queue.asyncAfter(deadline: .now() + Self.rebuildDelay) {
            self.isRebuildPending = false
            guard !self.isStopped else { return }
            self.logger.notice("Rebuilding the system audio tap after an output device change")
            self.rebuild()
        }
    }

    /// Undoes `setUp` in reverse; safe after a partial setup. Once the IO proc is destroyed, Core Audio
    /// releases its block and with it the ring.
    private func tearDown() {
        timer?.cancel()
        timer = nil
        listeners.forEach { $0.remove() }
        listeners = []
        let system = AudioHardwareSystem.shared
        if let aggregate {
            if let ioProc {
                log(AudioDeviceStop(aggregate.id, ioProc), "stop the aggregate device")
                log(AudioDeviceDestroyIOProcID(aggregate.id, ioProc), "destroy the IO proc")
            }
            do { try system.destroyAggregateDevice(aggregate) } catch { logFailure("destroy the aggregate device", error) }
        }
        if let tap {
            do { try system.destroyProcessTap(tap) } catch { logFailure("destroy the process tap", error) }
        }
        ioProc = nil
        aggregate = nil
        tap = nil
        consumer.end()
    }

    private func check(_ status: OSStatus, _ step: String) throws {
        guard status == noErr else { throw TapError("could not \(step) (OSStatus \(status))") }
    }

    private func log(_ status: OSStatus, _ step: String) {
        if status != noErr { logger.error("Could not \(step, privacy: .public) (OSStatus \(status))") }
    }

    private func logFailure(_ step: String, _ error: any Error) {
        logger.error("Could not \(step, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }
}

private nonisolated struct TapError: LocalizedError {
    let errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }
}
