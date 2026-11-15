@preconcurrency import AVFoundation
import Accelerate
import Foundation
import SoundAnalysis
import Synchronization

/// The real `SpeechSource`: a tap of the system's sound like the bars', of its own and only while it listens, every sample of it
/// handed to macOS's sound classifier, which says for each half second how sure it is that someone speaks. Nothing heard is kept:
/// only the confidence leaves the classifier. Never used by tests.
final class DialogueListener: SpeechSource {
    /// How much one half second the classifier hears overlaps the next: 0.8 gives a result every tenth of a second, for "Tự căn"; watching
    /// in the background takes 0.5, a result every quarter, for less than half the work.
    static let listeningOverlap = 0.8
    static let watchingOverlap = 0.5

    private let overlap: Double
    private var session: SystemAudioTapSession?

    init(overlap: Double = DialogueListener.listeningOverlap) {
        self.overlap = overlap
    }
    private var sessionCount = 0

    isolated deinit { stop() }

    func start(onEvent: @escaping @MainActor (SpeechEvent) -> Void) {
        stop()
        sessionCount += 1
        let id = sessionCount
        let deliver: @MainActor (SpeechEvent) -> Void = { [weak self] event in
            guard let self, self.sessionCount == id, self.session != nil else { return }
            onEvent(event)
        }
        let emit: @Sendable (SpeechEvent) -> Void = { event in DispatchQueue.main.async { deliver(event) } }
        let session = SystemAudioTapSession(name: "MyNotch dialogue", consumer: SpeechConsumer(overlap: overlap, emit: emit), onFailure: { emit(.failed($0)) })
        self.session = session
        session.start()
    }

    func stop() {
        session?.stop()
        session = nil
    }
}

/// Reads every new sample of the ring and feeds it to the classifier, on a queue of its own so a slow analysis never holds up the
/// tap's. A result's time is the middle of the half second it heard, dated from when its samples came off the ring.
private nonisolated final class SpeechConsumer: SystemAudioConsumer, @unchecked Sendable {
    /// The shortest window the classifier takes.
    static let windowFrames: Int64 = 8_000
    static let windowTimescale: Int32 = 16_000
    /// Quieter than this is the silence of a tap the system did not allow.
    static let soundPeak: Float = 1e-4

    private let emit: @Sendable (SpeechEvent) -> Void
    private let overlap: Double
    private let analysisQueue = DispatchQueue(label: "io.lucasvu.mynotch.media.dialogue.analysis", qos: .utility)
    // Touched on the session's queue only.
    private var ring: SampleRing?
    private var format: AVAudioFormat?
    private var lastRead = 0
    private var samples: [Float] = []
    private var heardSound = false
    // Touched on the analysis queue only.
    private var analyzer: SNAudioStreamAnalyzer?
    private var observer: Observer?
    /// The ring's count at the start of the current analyzer, and the latest copy's end with when it was copied: what dates a result.
    private let clock = Mutex<(origin: Int, end: Int, date: Date, sampleRate: Double)>((0, 0, .distantPast, 48_000))

    init(overlap: Double, emit: @escaping @Sendable (SpeechEvent) -> Void) {
        self.overlap = overlap
        self.emit = emit
    }

    func begin(ring: SampleRing, sampleRate: Double) {
        self.ring = ring
        lastRead = ring.writtenCount
        let origin = lastRead
        clock.withLock { $0 = (origin, origin, Date(), sampleRate) }
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false) else {
            emit(.failed("no mono format at \(sampleRate) Hz"))
            return
        }
        self.format = format
        let emit = emit
        analysisQueue.async { [self] in
            do {
                let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
                request.windowDuration = CMTime(value: Self.windowFrames, timescale: Self.windowTimescale)
                request.overlapFactor = overlap
                let analyzer = SNAudioStreamAnalyzer(format: format)
                let observer = Observer { [weak self] range in self?.reading(for: range) }
                try analyzer.add(request, withObserver: observer)
                self.analyzer = analyzer
                self.observer = observer
            } catch {
                emit(.failed(error.localizedDescription))
            }
        }
    }

    func read() {
        guard let ring, let format, let range = ring.copy(since: lastRead, into: &samples) else { return }
        lastRead = range.upperBound
        let now = Date()
        clock.withLock { $0.end = range.upperBound; $0.date = now }
        if !heardSound, vDSP.maximumMagnitude(samples) > Self.soundPeak {
            heardSound = true
            emit(.heardSound)
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        let position = AVAudioFramePosition(range.lowerBound - clock.withLock { $0.origin })
        analysisQueue.async { [self] in analyzer?.analyze(buffer, atAudioFramePosition: position) }
    }

    func end() {
        ring = nil
        format = nil
        analysisQueue.async { [self] in
            analyzer?.completeAnalysis()
            analyzer = nil
            observer = nil
        }
    }

    /// On the analysis queue: the speech confidence of the half second `range` covers, dated at its middle.
    private func reading(for result: (range: CMTimeRange, confidence: Double)) {
        let date = clock.withLock { clock in
            let middle = Double(clock.origin) + (result.range.start.seconds + result.range.duration.seconds / 2) * clock.sampleRate
            return clock.date.addingTimeInterval((middle - Double(clock.end)) / clock.sampleRate)
        }
        emit(.reading(SpeechReading(date: date, confidence: result.confidence)))
    }

    private final class Observer: NSObject, SNResultsObserving, @unchecked Sendable {
        let onResult: ((range: CMTimeRange, confidence: Double)) -> Void

        init(onResult: @escaping ((range: CMTimeRange, confidence: Double)) -> Void) {
            self.onResult = onResult
        }

        func request(_ request: any SNRequest, didProduce result: any SNResult) {
            guard let result = result as? SNClassificationResult else { return }
            onResult((result.timeRange, result.classification(forIdentifier: "speech")?.confidence ?? 0))
        }
    }
}
