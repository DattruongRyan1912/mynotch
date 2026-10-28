import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import MediaModule

/// A film's lines: someone speaks for 1.5–3 s, then nobody for 1–4 s, from 2 s in to `until`.
func filmLines(until end: Double = 120, seed: UInt64 = 7) -> [SubtitleCue] {
    var generator = SeededGenerator(seed: seed)
    var cues: [SubtitleCue] = []
    var time = 2.0
    while time < end {
        let length = Double.random(in: 1.5...3, using: &generator)
        cues.append(SubtitleCue(start: time, end: time + length, text: "line \(cues.count)"))
        time += length + Double.random(in: 1...4, using: &generator)
    }
    return cues
}

/// What the classifier hears of `cues` spoken in the film, every tenth of a second over `heard`: sure while a line is spoken, a little
/// unsure otherwise, as it is with music under the speech.
func speech(of cues: [SubtitleCue], over heard: ClosedRange<Double>, seed: UInt64 = 3) -> [SpeechSample] {
    var generator = SeededGenerator(seed: seed)
    return stride(from: heard.lowerBound, through: heard.upperBound, by: 0.1).map { position in
        let speaking = cues.contains { $0.start <= position && position < $0.end }
        let confidence = speaking ? Double.random(in: 0.6...1, using: &generator) : Double.random(in: 0...0.3, using: &generator)
        return SpeechSample(position: position, confidence: confidence)
    }
}

/// The same numbers on every run.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}

@Suite struct SubtitleAlignerTests {
    let spoken = filmLines()

    /// The file's lines, `late` seconds after they are spoken.
    func file(late: Double) -> [SubtitleCue] {
        spoken.map { SubtitleCue(start: $0.start + late, end: $0.end + late, text: $0.text) }
    }

    @Test func aFileThatComesLateIsMovedSooner() {
        let result = SubtitleAligner.align(speech(of: spoken, over: 30...75), cues: file(late: 3), delay: 0)
        guard case .aligned(let delay, let score) = result else { Issue.record("\(result)"); return }
        #expect(delay == -3, "the figure reads +3s: three seconds sooner")
        #expect(score > 0.8)
    }

    @Test func aFileThatComesEarlyIsMovedLater() {
        let result = SubtitleAligner.align(speech(of: spoken, over: 30...75), cues: file(late: -2.5), delay: 0)
        #expect(result.delay == 2.5)
    }

    @Test func theDelayFoundIsAllTheFileNeedsWhateverItHadBefore() {
        // Moved 1 s later by hand already, and 4 s late in all: 4 s sooner from the file, whatever the hand did.
        let result = SubtitleAligner.align(speech(of: spoken, over: 30...75), cues: file(late: 4), delay: 1)
        #expect(result.delay == -4)
    }

    @Test func itLooksNoFurtherThanItsReach() {
        let result = SubtitleAligner.align(speech(of: spoken, over: 40...100), cues: file(late: 40), delay: 0)
        #expect(result.delay == nil)
    }

    @Test func soundWithoutSpeechIsNoSpeech() {
        let music = stride(from: 30.0, through: 75, by: 0.1).map { SpeechSample(position: $0, confidence: 0.1) }
        #expect(SubtitleAligner.align(music, cues: spoken, delay: 0) == .noSpeech)
    }

    @Test func aFewLinesProveNothing() {
        let quiet = Array(spoken.prefix(3))
        #expect(SubtitleAligner.align(speech(of: spoken, over: 0...10), cues: quiet, delay: 0) == .tooFewLines)
    }

    @Test func anotherFilmsSubtitlesMatchNothing() {
        let other = filmLines(seed: 99)
        #expect(SubtitleAligner.align(speech(of: spoken, over: 30...75), cues: other, delay: 0) == .noMatch)
    }

    @Test func aCorrelationIsOneForTheSameShapeAndZeroForAFlatOne() {
        #expect(abs(SubtitleAligner.correlation([0, 1, 0, 1], [0, 2, 0, 2]) - 1) < 1e-9)
        #expect(SubtitleAligner.correlation([0, 1, 0, 1], [1, 1, 1, 1]) == 0)
    }
}

private extension SubtitleAligner.Result {
    var delay: Double? {
        if case .aligned(let delay, _) = self { delay } else { nil }
    }
}

/// Plays a source of speech: the test hands it readings.
@MainActor
final class FakeSpeechSource: SpeechSource {
    private(set) var isListening = false
    private(set) var starts = 0
    private var onEvent: (@MainActor (SpeechEvent) -> Void)?

    func start(onEvent: @escaping @MainActor (SpeechEvent) -> Void) {
        starts += 1
        isListening = true
        self.onEvent = onEvent
    }

    func stop() {
        isListening = false
        onEvent = nil
    }

    func send(_ event: SpeechEvent) { onEvent?(event) }

    /// The film's speech as heard from `start` on, the film at `position` then.
    func hear(_ samples: [SpeechSample], filmAt position: Double, at start: Date) {
        send(.heardSound)
        for sample in samples {
            send(.reading(SpeechReading(date: start.addingTimeInterval(sample.position - position), confidence: sample.confidence)))
        }
    }
}

@MainActor
@Suite final class SubtitleAlignmentTests {
    let scheduler = ManualScheduler()
    let source = FakeSpeechSource()
    lazy var alignment = SubtitleAlignment(scheduler: scheduler) { [unowned self] _ in source }
    let start = Date(timeIntervalSinceReferenceDate: 1_000_000)
    let spoken = filmLines()
    var applied: [Double] = []
    var finished: [SubtitleAlignment.Phase] = []

    /// A film playing from 30 s in at `start`.
    func film(playing: Bool = true, at position: Double = 30, title: String = "Film") -> NowPlayingState {
        NowPlayingState(
            bundleIdentifier: "com.google.Chrome", title: title, durationSeconds: 6_000,
            elapsedAnchor: PlaybackAnchor(elapsedSeconds: position, timestamp: start, rate: 1), isPlaying: playing
        )
    }

    func entry(late: Double) -> SubtitleBook.Entry {
        let cues = spoken.map { SubtitleCue(start: $0.start + late, end: $0.end + late, text: $0.text) }
        return SubtitleBook.Entry(name: "film.srt", cues: cues, delay: 0, usedAt: start)
    }

    func begin(late: Double = 3, state: NowPlayingState? = nil) {
        alignment.onFinish = { [unowned self] in finished.append($0) }
        alignment.start(entry: entry(late: late), state: state ?? film(), now: start) { [unowned self] delay, _ in applied.append(delay) }
    }

    func listenToTheEnd() {
        scheduler.advance(by: .seconds(SubtitleAlignment.listeningSeconds))
    }

    @Test func itListensCountingDownAndMovesTheSubtitlesOntoTheSpeech() {
        begin()
        #expect(alignment.phase == .listening(secondsLeft: SubtitleAlignment.listeningSeconds))
        #expect(source.isListening)
        scheduler.advance(by: .seconds(1))
        #expect(alignment.phase == .listening(secondsLeft: SubtitleAlignment.listeningSeconds - 1))
        source.hear(speech(of: spoken, over: 30...75), filmAt: 30, at: start)
        listenToTheEnd()
        #expect(!source.isListening)
        #expect(applied == [-3])
        #expect(alignment.phase == .aligned(delay: -3))
        #expect(finished == [.aligned(delay: -3)])
    }

    /// Hears a second of the film each second, from 30 s in, for `seconds` or until it stops listening; how many it heard.
    @discardableResult
    func hearAsItPlays(for seconds: Int, of spoken: [SubtitleCue]? = nil) -> Int {
        source.send(.heardSound)
        for second in 0..<seconds {
            guard alignment.isListening else { return second }
            let from = 30.0 + Double(second)
            for sample in speech(of: spoken ?? self.spoken, over: from...(from + 0.9)) {
                source.send(.reading(SpeechReading(date: start.addingTimeInterval(sample.position - 30), confidence: sample.confidence)))
            }
            scheduler.advance(by: .seconds(1))
        }
        return seconds
    }

    @Test func aClearAnswerComesBeforeTheEndOfTheListening() {
        begin()
        // Two looks in a row agree as soon as enough lines were heard: done then, well before 45 s.
        let heard = hearAsItPlays(for: SubtitleAlignment.listeningSeconds)
        #expect(heard < 30, "heard \(heard) s")
        #expect(heard >= SubtitleAlignment.earliestSeconds + SubtitleAlignment.checkEvery)
        #expect(applied == [-3])
        #expect(alignment.phase == .aligned(delay: -3))
        #expect(!source.isListening)
        #expect(scheduler.pendingCount == 0)
    }

    @Test func withoutAClearAnswerItListensToTheEnd() {
        begin()
        // Another film's speech: no look finds a delay, so it waits for all of it.
        hearAsItPlays(for: 20, of: filmLines(seed: 99))
        #expect(applied.isEmpty)
        #expect(alignment.isListening)
        #expect(alignment.phase == .listening(secondsLeft: SubtitleAlignment.listeningSeconds - 20))
    }

    @Test func aPausedFilmIsNotListenedTo() {
        begin(state: film(playing: false))
        #expect(source.starts == 0)
        #expect(alignment.phase == .failed(SubtitleAlignment.pausedMessage))
        #expect(finished.count == 1)
    }

    @Test func nothingHeardAtAllIsMostLikelyTheMissingPermission() {
        begin()
        listenToTheEnd()
        #expect(alignment.phase == .failed(SubtitleAlignment.silentMessage))
        #expect(applied.isEmpty)
    }

    @Test func whatIsHeardWhileTheFilmIsPausedDoesNotCount() {
        begin()
        // Paused a second in, for the rest of the time: what comes after says nothing about the film.
        alignment.noteState(film(playing: false, at: 31), at: start.addingTimeInterval(1))
        source.hear(speech(of: spoken, over: 30...75), filmAt: 30, at: start)
        listenToTheEnd()
        #expect(alignment.phase == .failed(SubtitleAlignment.stillPausedMessage))
        #expect(applied.isEmpty)
    }

    @Test func aSeekWhileListeningPlacesWhatFollowsWhereTheFilmWent() {
        begin()
        let seekAt = start.addingTimeInterval(20)
        // 20 s heard from 30 s in, then the film jumps to 80 s.
        source.hear(speech(of: spoken, over: 30...50), filmAt: 30, at: start)
        alignment.noteState(film(at: 80).with(anchorAt: seekAt), at: seekAt)
        source.hear(speech(of: spoken, over: 80...105), filmAt: 80, at: seekAt)
        listenToTheEnd()
        #expect(applied == [-3])
    }

    @Test func stoppingListensNoMoreAndMovesNothing() {
        begin()
        alignment.cancel()
        #expect(alignment.phase == .idle)
        #expect(!source.isListening)
        listenToTheEnd()
        #expect(applied.isEmpty)
        #expect(finished.isEmpty)
    }

    @Test func theTapFailingSaysSo() {
        begin()
        source.send(.failed("no process tap"))
        #expect(alignment.phase == .failed("Không nghe được âm thanh hệ thống: no process tap"))
        #expect(!source.isListening)
    }
}

private extension NowPlayingState {
    func with(anchorAt date: Date) -> NowPlayingState {
        var state = self
        state.elapsedAnchor?.timestamp = date
        return state
    }
}

@MainActor
@Suite struct SubtitleQuickControlAlignmentTests {
    let entry = SubtitleBook.Entry(name: "film.srt", cues: [], delay: 3.5, usedAt: Date())

    @Test func listeningShowsTheSecondsLeftInTheFiguresRoom() {
        #expect(SubtitleQuickControl.figure(for: entry, phase: .listening(secondsLeft: 32)) == "32s")
        #expect(SubtitleQuickControl.figure(for: entry, phase: .idle) == "−3.5s")
        #expect(SubtitleQuickControl.figure(for: entry, phase: nil) == "−3.5s")
    }

    @Test func theHelpSaysWhatTheLastListeningCameTo() {
        #expect(SubtitleQuickControl.help(for: entry, phase: .aligned(delay: -1.2)) == "film.srt: lệch −3.5s. Đã tự căn theo tiếng thoại: +1.2s")
        #expect(SubtitleQuickControl.help(for: entry, phase: .failed("x")) == "film.srt: lệch −3.5s. Chưa tự căn được: x")
        #expect(SubtitleAlignmentToast.text(for: .aligned(delay: 2)) == "Đã căn phụ đề: −2s")
        #expect(SubtitleAlignmentToast.text(for: .listening(secondsLeft: 3)) == nil)
    }
}

@MainActor
@Suite final class MediaSubtitleAlignmentTests {
    let source = FakeNowPlayingSource()
    let speechSource = FakeSpeechSource()
    let module: MediaModule
    let harness: RegistryHarness
    let storageBase: URL
    let files = ScratchFolders.shared.reserveShort()
    let spoken = filmLines()

    init() {
        module = MediaModule(
            source: source, spectrum: FakeSpectrumSource(), lyricsClient: FakeHTTPClient(), tokens: FakeTokenStore(),
            signIn: FakeAppleMusicSignIn(), lookUpApp: { _ in nil }
        )
        let speechSource = speechSource
        module.makeSpeechSource = { _ in speechSource }
        harness = RegistryHarness([module])
        storageBase = harness.storageRoot.caches.deletingLastPathComponent()
    }

    deinit {
        try? FileManager.default.removeItem(at: storageBase)
        try? FileManager.default.removeItem(at: files)
    }

    var store: NowPlayingStore { module.store }

    func settle(until condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { await Task.yield() }
    }

    /// An SRT of the film's lines, `late` seconds after they are spoken.
    func srt(late: Double) -> String {
        func time(_ seconds: Double) -> String {
            let millis = Int((seconds * 1000).rounded())
            return String(format: "%02d:%02d:%02d,%03d", millis / 3_600_000, millis / 60_000 % 60, millis / 1000 % 60, millis % 1000)
        }
        return spoken.enumerated().map { index, cue in
            "\(index + 1)\n\(time(cue.start + late)) --> \(time(cue.end + late))\n\(cue.text)\n"
        }.joined(separator: "\n")
    }

    @Test func theFoundDelayMovesTheLinesOnTheScreenAndIsRemembered() async throws {
        await harness.registry.bootstrap()
        source.emit(AdapterLines.track("A film", artist: "", bundle: "com.google.Chrome", elapsed: 30, duration: 6_000))
        await settle { store.state.isActive }
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        let url = files.appending(path: "film.srt")
        try Data(srt(late: 3).utf8).write(to: url)
        #expect(module.loadSubtitles(from: url))
        let firstLine = try #require(store.syncedLyrics?.first?.time)

        module.alignSubtitles()
        #expect(module.subtitleAlignment?.isListening == true)
        let anchor = try #require(store.state.elapsedAnchor)
        speechSource.hear(speech(of: spoken, over: anchor.elapsedSeconds...(anchor.elapsedSeconds + 45)), filmAt: anchor.elapsedSeconds, at: anchor.timestamp)
        harness.scheduler.advance(by: .seconds(SubtitleAlignment.listeningSeconds))

        #expect(module.subtitleAlignment?.phase == .aligned(delay: -3))
        #expect(module.subtitles.current?.delay == -3)
        #expect(abs((store.syncedLyrics?.first?.time ?? 0) - (firstLine - 3)) < 1e-9)
        #expect(harness.presenter.toastCount == 1)
    }
}

@MainActor
@Suite final class SubtitleWatchTests {
    let scheduler = ManualScheduler()
    let source = FakeSpeechSource()
    lazy var alignment = SubtitleAlignment(scheduler: scheduler) { [unowned self] _ in source }
    let start = Date(timeIntervalSinceReferenceDate: 2_000_000)
    let fileLines = filmLines(until: 400)
    var entry: SubtitleBook.Entry
    var applied: [(delay: Double, from: Double)] = []
    var realigned: [Double] = []

    init() {
        entry = SubtitleBook.Entry(name: "film.srt", cues: filmLines(until: 400), delay: 0, usedAt: Date())
    }

    func film(at position: Double = 200, playing: Bool = true) -> NowPlayingState {
        NowPlayingState(
            bundleIdentifier: "com.google.Chrome", title: "Film", durationSeconds: 6_000,
            elapsedAnchor: PlaybackAnchor(elapsedSeconds: position, timestamp: start, rate: 1), isPlaying: playing
        )
    }

    func watch() {
        alignment.onRealigned = { [unowned self] in realigned.append($0) }
        alignment.watch(state: film(), entry: { [unowned self] in entry }, now: start) { [unowned self] delay, from in
            applied.append((delay, from))
            entry.parts.append(.init(from: from, delay: delay))
        }
    }

    /// Plays the film from 200 s for up to `seconds`, the speech `late` seconds after the file's lines; how long until watching
    /// moved them, nil when it never did.
    @discardableResult
    func play(for seconds: Int, late: Double) -> Int? {
        let spoken = fileLines.map { SubtitleCue(start: $0.start + late, end: $0.end + late, text: $0.text) }
        for second in 0..<seconds {
            // Each stretch of listening is a session of its own, which says it heard sound again.
            source.send(.heardSound)
            let from = 200.0 + Double(second)
            for sample in speech(of: spoken, over: from...(from + 0.9), seed: UInt64(second + 1)) {
                source.send(.reading(SpeechReading(date: start.addingTimeInterval(sample.position - 200), confidence: sample.confidence)))
            }
            scheduler.advance(by: .seconds(1))
            if !applied.isEmpty { return second + 1 }
        }
        return nil
    }

    @Test func afterAnAdvertisementTheRestOfTheFilmIsMovedOnceTwoLooksAgree() throws {
        watch()
        #expect(alignment.isWatching)
        // Two stretches of listening with a rest between them at most.
        let took = try #require(play(for: 240, late: 25))
        #expect(took <= SubtitleAlignment.watchListenSeconds * 2 + SubtitleAlignment.watchRestSeconds, "took \(took) s")
        #expect(applied.first?.delay == 25)
        // From where the looks started hearing, not from the start of the film.
        #expect((applied.first?.from ?? 0) >= 200)
        #expect(realigned == [25])
        #expect(alignment.isWatching, "still watching for the next advertisement")
        #expect(alignment.phase == .idle, "the tab's figure is not taken over")
    }

    @Test func itListensThenRestsThenListensAgain() {
        watch()
        #expect(source.isListening)
        scheduler.advance(by: .seconds(SubtitleAlignment.watchListenSeconds))
        #expect(!source.isListening, "resting")
        #expect(alignment.isWatching)
        scheduler.advance(by: .seconds(SubtitleAlignment.watchRestSeconds))
        #expect(source.isListening)
        #expect(source.starts == 2)
        alignment.stopWatching()
        #expect(scheduler.pendingCount == 0)
    }

    @Test func subtitlesThatFitAreLeftAlone() {
        watch()
        #expect(play(for: 90, late: 0) == nil)
        #expect(realigned.isEmpty)
    }

    @Test func tellingItTwiceToWatchTheSameFilmStartsNothingNewAndStoppingStopsIt() {
        watch()
        watch()
        #expect(source.starts == 1)
        alignment.stopWatching()
        #expect(!alignment.isWatching)
        #expect(!source.isListening)
        #expect(scheduler.pendingCount == 0)
    }

    @Test func tuAlignStopsWatchingWhileItListens() {
        watch()
        alignment.start(entry: entry, state: film(), now: start) { _, _ in }
        #expect(!alignment.isWatching)
        #expect(alignment.isListening)
    }
}

@MainActor
@Suite final class MediaSubtitleWatchTests {
    let source = FakeNowPlayingSource()
    let speechSource = FakeSpeechSource()
    let module: MediaModule
    let harness: RegistryHarness
    let storageBase: URL
    let files = ScratchFolders.shared.reserveShort()

    init() {
        module = MediaModule(
            source: source, spectrum: FakeSpectrumSource(), lyricsClient: FakeHTTPClient(), tokens: FakeTokenStore(),
            signIn: FakeAppleMusicSignIn(), lookUpApp: { _ in nil }
        )
        let speechSource = speechSource
        module.makeSpeechSource = { _ in speechSource }
        harness = RegistryHarness([module])
        storageBase = harness.storageRoot.caches.deletingLastPathComponent()
    }

    deinit {
        try? FileManager.default.removeItem(at: storageBase)
        try? FileManager.default.removeItem(at: files)
    }

    var keys: MediaSettingsKeys { MediaSettingsKeys(harness.settingsEnvironment(for: "media")!.settings) }

    func settle(until condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { await Task.yield() }
    }

    @Test func itWatchesOnlyWhileWantedAndTheFilmPlaysWithItsSubtitles() async throws {
        #expect(keys.subtitleWatch.defaultValue == false)
        await harness.registry.bootstrap()
        source.emit(AdapterLines.track("A film", artist: "", bundle: "com.google.Chrome", elapsed: 30, duration: 6_000))
        await settle { module.store.state.isActive }
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        let url = files.appending(path: "film.srt")
        try Data(MediaSubtitleTests.srt.utf8).write(to: url)
        module.loadSubtitles(from: url)
        #expect(module.subtitleAlignment?.isWatching == false)

        module.setSubtitleWatching(true)
        await settle { module.subtitleAlignment?.isWatching == true }
        #expect(module.subtitleAlignment?.watchWanted == true)
        #expect(speechSource.isListening)

        source.emit(AdapterLines.track("A film", artist: "", playing: false, bundle: "com.google.Chrome", elapsed: 31, duration: 6_000))
        await settle { module.subtitleAlignment?.isWatching == false }
        #expect(!speechSource.isListening, "nothing heard while the film is paused")

        module.setSubtitleWatching(false)
        source.emit(AdapterLines.track("A film", artist: "", bundle: "com.google.Chrome", elapsed: 31, duration: 6_000))
        await settle { module.store.state.isPlaying }
        #expect(module.subtitleAlignment?.isWatching == false)
    }
}
