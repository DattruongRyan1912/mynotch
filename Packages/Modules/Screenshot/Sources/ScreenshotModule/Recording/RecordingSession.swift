import Foundation
import MyNotchCore
import Observation
import os

/// One recording, from the first frame to the last: checks what it needs, opens the folder, drives the engine and the source,
/// collects what the pointer does, and leaves a recording that can be opened, edited and exported.
///
/// What is on disk is always usable. The project is saved as `recording` as soon as the stream runs, and the project and the
/// activity are saved again every 5 seconds and at every pause; the segments are written in fragments. If the app ends in the
/// middle, `RecordingStore.list` finds a recording still marked `recording` and rescues it.
@Observable
final class RecordingSession {
    enum State: Equatable {
        case idle, starting, recording, paused, stopping
    }

    /// How often the project and the activity are saved while recording, in ticks (a tick is half a second).
    static let saveEveryTicks = 10
    static let tick: Duration = .milliseconds(500)
    /// A stream that has sent no picture after this many seconds is not recording anything, whatever it says.
    static let firstFrameTimeout: TimeInterval = 5

    private(set) var state: State = .idle
    /// The recording made last, once it ended.
    private(set) var lastProject: RecordingProject?
    /// Called when the recording ended without `stop()`: the system stopped the stream, or writing failed. What could be
    /// kept was kept; a failure with nothing to keep says why. After it the session is idle again.
    @ObservationIgnored var onEnded: ((Result<RecordingProject, RecordingError>) -> Void)?

    @ObservationIgnored private let source: any RecordingSource
    @ObservationIgnored private let events: any ActivityEventSource
    @ObservationIgnored private let permissions: any PermissionCenter
    @ObservationIgnored private let store: RecordingStore
    @ObservationIgnored private let scheduler: any Scheduler
    @ObservationIgnored private let clock: @Sendable () -> TimeInterval
    @ObservationIgnored private let engineOptions: RecordingEngine.Options
    @ObservationIgnored private let logger: Logger

    @ObservationIgnored private var engine: RecordingEngine?
    @ObservationIgnored private var recorder: ActivityRecorder?
    @ObservationIgnored private var project: RecordingProject?
    @ObservationIgnored private var folder: URL?
    @ObservationIgnored private var captureOffset: TimeInterval = 0
    @ObservationIgnored private var startedAt: TimeInterval = 0
    @ObservationIgnored private var tickHandle: ScheduledAction?
    @ObservationIgnored private var tickCount = 0
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var isBusy = false

    /// `clock` is the host clock; tests set it by hand. `engineOptions` lets tests wait for the encoder instead of dropping.
    init(
        source: any RecordingSource, events: any ActivityEventSource, permissions: any PermissionCenter, store: RecordingStore,
        scheduler: any Scheduler, clock: @escaping @Sendable () -> TimeInterval = RecordingClock.now,
        engineOptions: RecordingEngine.Options = .init(), logger: Logger = Log.logger(category: "recording")
    ) {
        self.source = source
        self.events = events
        self.permissions = permissions
        self.store = store
        self.scheduler = scheduler
        self.clock = clock
        self.engineOptions = engineOptions
        self.logger = logger
    }

    /// The recording in progress, so the list can leave it alone (`RecordingStore.list(excluding:)`).
    var currentRecordingID: UUID? { project?.id }

    /// Seconds recorded so far, pauses left out.
    var elapsed: TimeInterval {
        guard let engine else { return 0 }
        let now = captureNow
        return engine.timeline.segments.reduce(0) { $0 + ($1.duration ?? max(0, now - $1.start)) }
    }

    private var captureNow: TimeInterval { clock() + captureOffset }

    // MARK: Start

    /// Starts recording `region`. Throws before anything is created when Screen Recording is missing, or the microphone is
    /// asked for and is not granted (the first time, macOS is asked); Accessibility only decides whether keys are noticed.
    func start(region: RecordingRegion, options: RecordingOptions = RecordingOptions()) async throws(RecordingError) {
        guard state == .idle else { throw .alreadyRecording }
        guard permissions.status(of: .screenRecording) == .granted else { throw .screenRecordingDenied }
        state = .starting
        if options.microphone != nil {
            do {
                try await ensureMicrophone()
            } catch {
                state = .idle
                throw error
            }
        }
        let keyboard = permissions.status(of: .accessibility) == .granted
        let created: (id: UUID, folder: URL)
        do {
            created = try store.create()
        } catch {
            state = .idle
            throw .writerFailed(error.localizedDescription)
        }
        var kinds: [AudioTrackKind] = []
        if options.microphone != nil { kinds.append(.microphone) }
        if options.systemAudio { kinds.append(.system) }
        let engine = RecordingEngine(
            folder: created.folder, region: region, fps: options.fps, audio: kinds, options: engineOptions,
            onEvent: { [weak self] event in Task { @MainActor in self?.handle(event) } }
        )
        do {
            try await engine.begin()
            try await source.start(RecordingSourceConfiguration(region: region, options: options), sink: engine)
        } catch {
            await engine.abort()
            await source.stop()
            store.discard(id: created.id)
            state = .idle
            throw error
        }
        captureOffset = source.captureClockOffset
        startedAt = captureNow
        let recorder = ActivityRecorder(region: region, recordsKeys: keyboard, clock: captureClock())
        self.engine = engine
        self.recorder = recorder
        folder = created.folder
        // Whole seconds, which is all the file keeps of a date, so what is saved reads back equal.
        let createdAt = Date(timeIntervalSince1970: Date.now.timeIntervalSince1970.rounded(.down))
        project = RecordingProject(
            id: created.id, createdAt: createdAt, status: .recording, region: region, fps: options.fps,
            hasMicrophone: options.microphone != nil, hasSystemAudio: options.systemAudio
        )
        events.start(sink: recorder, includesKeys: keyboard)
        state = .recording
        await save()
        tickCount = 0
        scheduleTick()
    }

    private func ensureMicrophone() async throws(RecordingError) {
        switch permissions.status(of: .microphone) {
        case .granted:
            return
        case .notDetermined:
            if await permissions.request(.microphone) == .granted { return }
            throw .microphoneDenied
        case .denied, .unknown:
            throw .microphoneDenied
        }
    }

    private func captureClock() -> @Sendable () -> TimeInterval {
        let clock = clock, offset = captureOffset
        return { clock() + offset }
    }

    // MARK: Pause, resume, stop

    /// Ends the segment being written. The picture and the sound of the pause are not in the video.
    func pause() async {
        guard state == .recording, !isBusy, let engine else { return }
        isBusy = true
        defer { isBusy = false }
        state = .paused
        _ = await engine.pause(at: captureNow)
        await save()
    }

    /// Opens the next segment.
    func resume() async throws(RecordingError) {
        guard state == .paused, !isBusy, let engine else { return }
        isBusy = true
        defer { isBusy = false }
        try await engine.resume(at: captureNow)
        state = .recording
    }

    /// Ends the recording and returns it. Throws `nothingRecorded` when no frame was ever written; then nothing is kept.
    @discardableResult
    func stop() async throws(RecordingError) -> RecordingProject {
        while isBusy { await Task.yield() }
        guard state == .recording || state == .paused else { throw .failed("Không có bản quay nào đang chạy") }
        state = .stopping
        await endCapture()
        return try await finalize(interrupted: false).get()
    }

    // MARK: Ending

    private func handle(_ event: RecordingEngine.Event) {
        guard state == .recording || state == .paused else { return }
        let error: RecordingError?
        switch event {
        case .failed(let failure): error = failure
        case .sourceStopped(let reason): error = reason
        }
        logger.error("Recording ended by itself: \(String(describing: error), privacy: .public)")
        state = .stopping
        let interrupted = error != nil && error != .stoppedBySystem
        Task {
            while isBusy { await Task.yield() }
            await endCapture()
            let result = await finalize(interrupted: interrupted, cause: error)
            onEnded?(result)
        }
    }

    /// Stops what feeds the recording: the timer, the pointer and the stream.
    private func endCapture() async {
        tickHandle?.cancel()
        tickHandle = nil
        await tickTask?.value
        events.stop()
        await source.stop()
    }

    /// Closes the files and saves the project and the activity for good. Afterwards the session is idle again.
    private func finalize(interrupted: Bool, cause: RecordingError? = nil) async -> Result<RecordingProject, RecordingError> {
        defer { reset() }
        guard let engine, let recorder, var project, let folder else { return .failure(.failed("Không có bản quay nào đang chạy")) }
        let closed = await engine.finish(at: captureNow)
        project.segments = Self.segments(of: closed)
        project.status = interrupted ? .interrupted : .finished
        do {
            try await Self.write(project, recorder, engine.timeline, to: folder)
            if interrupted { project = try await RecordingRecovery.recover(folder: folder) }
        } catch {
            return .failure(.writerFailed(error.localizedDescription))
        }
        guard !project.segments.isEmpty else {
            store.discard(id: project.id)
            return .failure(cause.flatMap { $0 == .stoppedBySystem ? nil : $0 } ?? .nothingRecorded)
        }
        lastProject = project
        return .success(project)
    }

    private func reset() {
        engine = nil
        recorder = nil
        project = nil
        folder = nil
        captureOffset = 0
        tickTask = nil
        state = .idle
    }

    /// Returns once everything delivered so far has been written and the timer's work is done. For tests.
    func settle() async {
        await engine?.drain()
        await tickTask?.value
    }

    // MARK: Saving

    private func scheduleTick() {
        tickHandle = scheduler.schedule(after: Self.tick) { [weak self] in self?.runTick() }
    }

    private func runTick() {
        guard state == .recording || state == .paused, let engine else { return }
        tickCount += 1
        let now = captureNow
        if state == .recording, engine.timeline.segments.isEmpty, now - startedAt > Self.firstFrameTimeout {
            // Not a permission the system reported, but a stream that never delivers: say so instead of recording nothing.
            handle(.failed(.nothingRecorded))
            return
        }
        let saves = tickCount.isMultiple(of: Self.saveEveryTicks)
        let previous = tickTask
        tickTask = Task {
            await previous?.value
            await engine.tick(at: now)
            if saves { await save() }
        }
        scheduleTick()
    }

    /// Saves the project (with the segments closed so far) and the activity, still marked as being recorded.
    private func save() async {
        guard let engine, let recorder, var project, let folder else { return }
        project.segments = Self.segments(of: await engine.closed)
        do {
            try await Self.write(project, recorder, engine.timeline, to: folder)
        } catch {
            logger.error("Could not save the recording: \(error, privacy: .public)")
        }
    }

    /// The activity first, so a project that says `recording` always has an activity beside it. Built and written off the main
    /// actor: an hour of pointer samples is a long list.
    @concurrent private static func write(
        _ project: RecordingProject, _ recorder: ActivityRecorder, _ timeline: RecordingTimeline, to folder: URL
    ) async throws {
        try recorder.track(on: timeline).write(to: folder)
        try project.write(to: folder)
    }

    private static func segments(of closed: [RecordingEngine.ClosedSegment]) -> [RecordingProject.Segment] {
        closed.map {
            .init(
                fileName: $0.fileName, captureStart: $0.summary.start, duration: $0.summary.duration, frames: $0.summary.frames,
                droppedFrames: $0.summary.droppedFrames, droppedAudio: $0.summary.droppedAudio
            )
        }
    }
}
