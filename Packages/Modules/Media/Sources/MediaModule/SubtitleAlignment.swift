import Foundation
import MyNotchCore
import Observation

/// One moment of the film's sound: how sure the classifier is that someone speaks (0…1), at the middle of the half second it heard.
nonisolated struct SpeechReading: Equatable, Sendable {
    var date: Date
    var confidence: Double
}

/// The same, placed in the film: seconds into it.
nonisolated struct SpeechSample: Equatable, Sendable {
    var position: Double
    var confidence: Double
}

/// What listens to the film for `SubtitleAlignment`; tests give their own.
protocol SpeechSource: AnyObject {
    /// Delivers on the main actor until `stop()`: readings as the sound is heard, `heardSound` the first time anything but
    /// silence comes (a tap the system did not allow hears nothing at all), `failed` once when listening could not start.
    func start(onEvent: @escaping @MainActor (SpeechEvent) -> Void)
    func stop()
}

nonisolated enum SpeechEvent: Equatable, Sendable {
    case reading(SpeechReading)
    case heardSound
    case failed(String)
}

/// Finds the delay that puts the subtitles on the speech: the one whose lines are up while someone speaks and down while nobody does,
/// over what was heard. Only a delay the whole file is moved by: a copy of the film running at another speed is not set right.
nonisolated enum SubtitleAligner {
    /// How far from the delay the file has now it looks, either way, and in what steps.
    static let reach = 30.0
    static let step = 0.1
    /// Fewer lines than this in what was heard prove nothing.
    static let minimumLines = 5
    /// How much of what was heard must be speech, at a confidence of `speechConfidence` or more.
    static let minimumSpeechShare = 0.05
    static let speechConfidence = 0.5
    /// The best delay must fit this well (a correlation), and this much better than any other that is not next to it.
    static let minimumScore = 0.35
    static let minimumLead = 0.1
    /// Before the end of the listening, a delay is taken only when it leads by this much.
    static let earlyLead = 0.15
    /// Delays closer than this to the best are the same peak.
    static let peakWidth = 1.0

    enum Result: Equatable {
        case aligned(delay: Double, score: Double)
        case tooFewLines
        case noSpeech
        case noMatch
    }

    /// `cues` as the file has them, `delay` what they are moved by now (positive: later); the result is the delay to store.
    /// `report` hears the figures the answer came from, for the log: no sound, only how sure the classifier was.
    static func align(
        _ samples: [SpeechSample], cues: [SubtitleCue], delay: Double, lead: Double = minimumLead,
        report: (String) -> Void = { _ in }
    ) -> Result {
        guard let first = samples.map(\.position).min(), let last = samples.map(\.position).max() else { return .noSpeech }
        let heard = first...last
        let lines = cues.count(where: { heard.contains($0.start + delay) })
        let speaking = samples.count(where: { $0.confidence >= speechConfidence })
        let heardFigures = String(
            format: "%d moments %.1f–%.1f s, %d lines, speech %.0f%%", samples.count, first, last, lines,
            100 * Double(speaking) / Double(samples.count)
        )
        guard lines >= minimumLines else {
            report(heardFigures)
            return .tooFewLines
        }
        guard Double(speaking) >= Double(samples.count) * minimumSpeechShare else {
            report(heardFigures)
            return .noSpeech
        }

        let speech = samples.map(\.confidence)
        // Only the lines some delay in reach could put in what was heard: a film's file has thousands.
        let near = cues.filter { $0.end + delay + reach >= first && $0.start + delay - reach <= last }
        let steps = Int((reach / step).rounded())
        let scores = (-steps...steps).map { index -> (delay: Double, score: Double) in
            let candidate = ((delay + Double(index) * step) * 10).rounded() / 10
            let shown = samples.map { sample in
                near.contains { $0.start + candidate <= sample.position && sample.position < $0.end + candidate } ? 1.0 : 0.0
            }
            return (candidate, correlation(speech, shown))
        }
        guard let best = scores.max(by: { $0.score < $1.score }) else { return .noMatch }
        let rival = scores.filter { abs($0.delay - best.delay) > peakWidth }.max(by: { $0.score < $1.score })
        report(String(
            format: "%@; best delay %+.1f s score %.2f, next %+.1f s score %.2f", heardFigures, best.delay, best.score,
            rival?.delay ?? 0, rival?.score ?? 0
        ))
        let rivalScore = rival?.score ?? 0
        guard best.score >= minimumScore, best.score - rivalScore >= lead else { return .noMatch }
        return .aligned(delay: best.delay, score: best.score)
    }

    /// Pearson's: 1 when one goes up exactly as the other does; 0 for a series that never changes.
    static func correlation(_ xs: [Double], _ ys: [Double]) -> Double {
        let count = Double(xs.count)
        guard count > 1 else { return 0 }
        let meanX = xs.reduce(0, +) / count
        let meanY = ys.reduce(0, +) / count
        var covariance = 0.0, varianceX = 0.0, varianceY = 0.0
        for (x, y) in zip(xs, ys) {
            covariance += (x - meanX) * (y - meanY)
            varianceX += (x - meanX) * (x - meanX)
            varianceY += (y - meanY) * (y - meanY)
        }
        guard varianceX > 0, varianceY > 0 else { return 0 }
        return covariance / (varianceX * varianceY).squareRoot()
    }
}

/// Listens to the film for a while and moves its subtitles onto the speech: what the subtitle menu's "Tự căn" does. It hears the
/// system's sound (MyNotch's own left out) and keeps only how sure it is that someone speaks, never the sound itself. What it hears
/// while the film is paused, or after another film started, does not count.
@MainActor
@Observable
final class SubtitleAlignment {
    static let listeningSeconds = 45
    /// It looks from this many seconds in, every `checkEvery`, and stops at the first delay found twice in a row with a clear lead;
    /// otherwise it listens to the end and takes what the whole of it says.
    static let earliestSeconds = 12
    static let checkEvery = 3
    /// Two looks agreeing this closely are the same delay.
    static let agreement = 0.2
    /// Fewer moments than this placed in the film (paused most of the time) prove nothing.
    static let minimumSamples = 100
    /// Watching while the film plays: the latest this many seconds heard, looked at every `watchEvery`.
    static let watchWindow = 30.0
    static let watchEvery = 10
    /// It listens this long, then rests this long, and again: an advertisement is now and then, and listening is the work.
    static let watchListenSeconds = 30
    static let watchRestSeconds = 90
    /// Fewer moments than this in what was heard (a result every quarter of a second while watching) prove nothing.
    static let watchMinimumSamples = 60
    /// A delay this close to the one in force is the one in force.
    static let watchTolerance = 0.3

    enum Phase: Equatable {
        case idle
        case listening(secondsLeft: Int)
        case aligned(delay: Double)
        case failed(String)
    }

    static let pausedMessage = "Phát phim trước rồi bấm Tự căn"
    static let stillPausedMessage = "Phim đang dừng gần hết lúc nghe, chưa căn được"
    static let silentMessage = "Không nghe thấy âm thanh. Cho phép MyNotch ghi âm thanh hệ thống trong Quyền riêng tư & Bảo mật › Ghi màn hình & âm thanh hệ thống"
    static let tooFewLinesMessage = "Đoạn vừa nghe có quá ít câu phụ đề. Thử lại ở đoạn nhiều thoại hơn"
    static let noSpeechMessage = "Gần như không nghe thấy tiếng nói. Thử lại ở đoạn nhiều thoại hơn"
    static let noMatchMessage = "Không tìm được độ lệch đủ chắc (nhạc nền to hoặc phụ đề không khớp bản phim này)"

    private(set) var phase = Phase.idle
    /// The user wants the subtitles set right again whenever they drift (an advertisement in the video): the module watches while
    /// this is on and a film with subtitles plays.
    var watchWanted = false
    /// Listening in the background, between "Tự căn"s, to set the subtitles right when they drift.
    private(set) var isWatching = false
    /// Watching found the subtitles had drifted and moved them: the delay now.
    @ObservationIgnored var onRealigned: (Double) -> Void = { _ in }
    /// The subtitles as they are now, which watching moves, while it lasts.
    @ObservationIgnored private var watchedEntry: () -> SubtitleBook.Entry? = { nil }
    /// What the latest look found that was not the delay in force, for the next one to agree with.
    @ObservationIgnored private var drift: Double?
    /// Who gets what `collect` heard, or why nothing was: a reason to tell, or nil when it was stopped.
    @ObservationIgnored private var collector: ((Result<[SpeechSample], CollectFailure>) -> Void)?

    struct CollectFailure: Error, Equatable {
        /// What to tell the user; nil when the listening was stopped.
        var reason: String?
    }
    /// Looks taken in the current stretch of listening.
    @ObservationIgnored private var looksThisStretch = 0
    /// The listening came to something: a delay, or why there is none.
    @ObservationIgnored var onFinish: (Phase) -> Void = { _ in }
    /// What the answer came from, for the log.
    @ObservationIgnored var log: (String) -> Void = { _ in }
    /// How late the latest reading arrived after the moment it is for, the most it was: a dating gone wrong shows here.
    @ObservationIgnored private var latestLag = 0.0
    @ObservationIgnored private var largestLag = 0.0
    /// What the latest early look found, for the next one to agree with.
    @ObservationIgnored private var earlyDelay: Double?

    @ObservationIgnored private let scheduler: any Scheduler
    /// A source for "Tự căn" (false) or for watching (true), which may hear less finely.
    @ObservationIgnored private let makeSource: (_ watching: Bool) -> any SpeechSource
    @ObservationIgnored private var source: (any SpeechSource)?
    @ObservationIgnored private var tick: ScheduledAction?
    @ObservationIgnored private var readings: [SpeechReading] = []
    @ObservationIgnored private var heardSound = false
    /// The film's state as it changed while listening, to place each reading in the film as it was at that moment.
    @ObservationIgnored private var states: [(date: Date, state: NowPlayingState)] = []
    @ObservationIgnored private var key: String?
    @ObservationIgnored private var cues: [SubtitleCue] = []
    @ObservationIgnored private var delay = 0.0
    /// Hears the delay found and from how far into the video it was listened for.
    @ObservationIgnored private var apply: (Double, Double) -> Void = { _, _ in }

    init(scheduler: any Scheduler, makeSource: @escaping (_ watching: Bool) -> any SpeechSource) {
        self.scheduler = scheduler
        self.makeSource = makeSource
    }

    var isListening: Bool {
        if case .listening = phase { true } else { false }
    }

    /// Starts listening to the film `state` plays, whose subtitles are `entry`; `apply` gets the delay found.
    func start(entry: SubtitleBook.Entry, state: NowPlayingState, now: Date = Date(), apply: @escaping (Double, Double) -> Void) {
        cancel()
        stopWatching()
        guard state.isPlaying else { return end(.failed(Self.pausedMessage)) }
        key = SubtitleBook.key(for: state)
        cues = entry.cues
        delay = entry.delay(at: PlaybackClock.position(state, at: now))
        self.apply = apply
        earlyDelay = nil
        phase = .listening(secondsLeft: Self.listeningSeconds)
        listen(to: state, now: now, watching: false)
        scheduleTick()
    }

    private func listen(to state: NowPlayingState, now: Date, watching: Bool) {
        readings = []
        heardSound = false
        latestLag = 0
        largestLag = 0
        states = [(now, state)]
        let source = makeSource(watching)
        self.source = source
        source.start { [weak self] event in self?.receive(event) }
    }

    /// Listens to the film `state` plays for as long as it plays, and moves its subtitles, `entry` as they are at each look, when
    /// two looks in a row find them off by the same delay. Watching the same film again changes nothing.
    func watch(state: NowPlayingState, entry: @escaping () -> SubtitleBook.Entry?, now: Date = Date(), apply: @escaping (Double, Double) -> Void) {
        let key = SubtitleBook.key(for: state)
        guard !isListening, !(isWatching && key == self.key) else { return }
        stopWatching()
        self.key = key
        watchedEntry = entry
        self.apply = apply
        drift = nil
        isWatching = true
        looksThisStretch = 0
        listen(to: state, now: now, watching: true)
        scheduleWatch()
    }

    /// Listening stops for `watchRestSeconds`; what the looks found is kept, for the next stretch to agree with.
    private func rest() {
        source?.stop()
        source = nil
        tick = scheduler.schedule(after: .seconds(Self.watchRestSeconds)) { [weak self] in self?.resumeWatching() }
    }

    private func resumeWatching() {
        guard isWatching, let state = states.last?.state else { return }
        looksThisStretch = 0
        listen(to: state, now: Date(), watching: true)
        scheduleWatch()
    }

    func stopWatching() {
        guard isWatching else { return }
        isWatching = false
        stopListening()
    }

    private func scheduleWatch() {
        tick = scheduler.schedule(after: .seconds(Self.watchEvery)) { [weak self] in self?.lookForDrift() }
    }

    /// A look at the latest `watchWindow` seconds heard: the delay they say, against the one in force where the film is.
    private func lookForDrift() {
        guard isWatching else { return }
        looksThisStretch += 1
        look()
        if looksThisStretch * Self.watchEvery >= Self.watchListenSeconds {
            rest()
        } else {
            scheduleWatch()
        }
    }

    private func look() {
        guard let latest = readings.map(\.date).max() else { return }
        let cutoff = latest.addingTimeInterval(-Self.watchWindow)
        readings.removeAll { $0.date < cutoff }
        if let kept = states.lastIndex(where: { $0.date <= cutoff }), kept > 0 { states.removeFirst(kept) }
        let samples = readings.compactMap(place)
        guard heardSound, samples.count >= Self.watchMinimumSamples, let entry = watchedEntry(),
              let first = samples.map(\.position).min(), let last = samples.map(\.position).max() else { return }
        let inForce = entry.delay(at: last)
        // A look that proves nothing (too few lines, too little speech) leaves what the last one found for the next to agree with;
        // only a look that finds the subtitles fit forgets it.
        guard case .aligned(let found, _) = SubtitleAligner.align(
            samples, cues: entry.cues, delay: inForce, lead: SubtitleAligner.earlyLead
        ) else { return }
        guard abs(found - inForce) > Self.watchTolerance else {
            drift = nil
            return
        }
        guard let drift, abs(drift - found) <= Self.agreement else {
            drift = found
            return
        }
        self.drift = nil
        log(String(format: "drifted from %+.1f s to %+.1f s, heard %.1f–%.1f s", inForce, found, first, last))
        apply(found, first)
        // What was heard was heard against the old delay: the next looks start afresh.
        readings = []
        onRealigned(found)
    }

    /// Stops listening, with nothing moved.
    func cancel() {
        let stopped = collector
        collector = nil
        stopped?(.failure(CollectFailure(reason: nil)))
        stopListening()
        if isListening { phase = .idle }
    }

    /// Back to nothing to say: another film, or its subtitles removed.
    func reset() {
        stopWatching()
        stopListening()
        phase = .idle
    }

    /// What plays changed (a pause, a seek, another film): readings after `date` are placed with it.
    func noteState(_ state: NowPlayingState, at date: Date = Date()) {
        guard isListening || isWatching, state != states.last?.state else { return }
        states.append((date, state))
    }

    private func receive(_ event: SpeechEvent) {
        guard isListening || isWatching else { return }
        switch event {
        case .reading(let reading):
            readings.append(reading)
            latestLag = Date().timeIntervalSince(reading.date)
            largestLag = max(largestLag, latestLag)
        case .heardSound: heardSound = true
        case .failed(let reason):
            if isWatching {
                log("watching stopped: \(reason)")
                stopWatching()
                return
            }
            stopListening()
            end(.failed("Không nghe được âm thanh hệ thống: \(reason)"))
        }
    }

    private func scheduleTick() {
        tick = scheduler.schedule(after: .seconds(1)) { [weak self] in self?.ticked() }
    }

    private func ticked() {
        guard case .listening(let left) = phase else { return }
        guard left > 1 else { return finish() }
        let heard = Self.listeningSeconds - left + 1
        if heard >= Self.earliestSeconds, (heard - Self.earliestSeconds) % Self.checkEvery == 0, lookEarly() { return }
        phase = .listening(secondsLeft: left - 1)
        scheduleTick()
    }

    /// True when what was heard so far is enough: the same delay twice in a row, each with a clear lead.
    private func lookEarly() -> Bool {
        // Hearing for someone else (`collect`) is for all of the time: the answer is theirs to work out.
        guard collector == nil, heardSound else { return false }
        let samples = readings.compactMap(place)
        guard case .aligned(let found, _) = SubtitleAligner.align(samples, cues: cues, delay: delay, lead: SubtitleAligner.earlyLead) else {
            earlyDelay = nil
            return false
        }
        defer { earlyDelay = found }
        guard let earlyDelay, abs(earlyDelay - found) <= Self.agreement else { return false }
        stopListening()
        log(String(format: "found after %d of %d s", Self.listeningSeconds - currentSecondsLeft + 1, Self.listeningSeconds))
        // What the whole of the listening says, with its figures for the log.
        settle(samples)
        return true
    }

    private var currentSecondsLeft: Int {
        if case .listening(let left) = phase { left } else { 0 }
    }

    private func finish() {
        stopListening()
        guard heardSound else { return end(.failed(Self.silentMessage)) }
        let samples = readings.compactMap(place)
        log(String(
            format: "%d readings, %d in the film, %d state changes, reading lag %.2f s (most %.2f s)", readings.count, samples.count,
            states.count - 1, latestLag, largestLag
        ))
        guard samples.count >= Self.minimumSamples else { return end(.failed(Self.stillPausedMessage)) }
        if let collector {
            self.collector = nil
            phase = .idle
            return collector(.success(samples))
        }
        settle(samples)
    }

    /// Listens to the film `state` plays as "Tự căn" does, the same countdown in the tab, and hands what was heard, placed in the film,
    /// to `collected` instead of aligning anything: for the search to try the subtitles it finds on. A film paused, or nothing heard,
    /// is a failure `collected` hears with the reason "Tự căn" would give, and nothing else does.
    func collect(state: NowPlayingState, now: Date = Date(), collected: @escaping (Result<[SpeechSample], CollectFailure>) -> Void) {
        cancel()
        stopWatching()
        guard state.isPlaying else { return collected(.failure(CollectFailure(reason: Self.pausedMessage))) }
        key = SubtitleBook.key(for: state)
        collector = collected
        phase = .listening(secondsLeft: Self.listeningSeconds)
        listen(to: state, now: now, watching: false)
        scheduleTick()
    }

    private func settle(_ samples: [SpeechSample]) {
        switch SubtitleAligner.align(samples, cues: cues, delay: delay, report: log) {
        case .aligned(let found, _):
            apply(found, samples.map(\.position).min() ?? 0)
            end(.aligned(delay: found))
        case .tooFewLines: end(.failed(Self.tooFewLinesMessage))
        case .noSpeech: end(.failed(Self.noSpeechMessage))
        case .noMatch: end(.failed(Self.noMatchMessage))
        }
    }

    private func end(_ phase: Phase) {
        if let collector, case .failed(let reason) = phase {
            self.collector = nil
            self.phase = .idle
            return collector(.failure(CollectFailure(reason: reason)))
        }
        self.phase = phase
        onFinish(phase)
    }

    /// Where in the film a reading was heard: nil while it was paused, or while something else played.
    private func place(_ reading: SpeechReading) -> SpeechSample? {
        guard let state = states.last(where: { $0.date <= reading.date })?.state ?? states.first?.state,
              state.isPlaying, SubtitleBook.key(for: state) == key,
              let position = PlaybackClock.position(state, at: reading.date) else { return nil }
        return SpeechSample(position: position, confidence: reading.confidence)
    }

    private func stopListening() {
        source?.stop()
        source = nil
        tick?.cancel()
        tick = nil
    }
}
