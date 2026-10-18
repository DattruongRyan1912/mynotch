import AppKit
import Foundation
import MyNotchCore

/// Everything the module does for a recording, from the tab's "Quay" or the shortcut to the editor that opens at the end: it checks
/// the permissions, asks for the region, counts down, runs the session, shows the notch's activity and the menu entries, writes the
/// person's defaults into the new recording and opens the editor. It exists while the module runs.
///
/// One thing is going on at a time, and `state.recordingPhase` says which. Everything that waits (the overlay, the countdown, the
/// session) goes through the module's context, so stopping the module cancels it.
final class RecordingCoordinator {
    static let countdownSeconds = 3

    private weak var module: ScreenshotModule?
    private let context: ModuleContext
    private let keys: ScreenshotSettingKeys
    private let state: ScreenshotState
    private let dependencies: RecordingDependencies
    let store: RecordingStore
    private let recorder: any RecordingControlling
    private(set) var editors: (any RecordingEditorHosting)?
    private var countdown: ScheduledAction?
    private var pending: (region: RecordingRegion, options: RecordingOptions)?
    private var isChangingPause = false
    private var isShuttingDown = false

    init(
        module: ScreenshotModule, context: ModuleContext, keys: ScreenshotSettingKeys, state: ScreenshotState,
        store: RecordingStore, dependencies: RecordingDependencies
    ) {
        self.module = module
        self.context = context
        self.keys = keys
        self.state = state
        self.store = store
        self.dependencies = dependencies
        recorder = dependencies.makeRecorder(store, context)
        recorder.onEnded = { [weak self] result in self?.recorderEnded(result) }
    }

    private(set) var phase: RecordingPhase {
        get { state.recordingPhase }
        set { state.recordingPhase = newValue }
    }

    /// Seconds recorded so far, for the tab's clock.
    var elapsed: TimeInterval { recorder.elapsed }

    /// The recording being made, which the list, a delete and a clean must leave alone.
    var currentRecordingID: UUID? { recorder.currentRecordingID }

    /// Whether an editor is exporting a recording, which no clean-up may disturb.
    var isExporting: Bool { editors?.isExporting ?? false }

    /// Whether recordings may be removed at all now. Not while the stream starts or the files close: the folder of the recording in
    /// the making is there, and its ID is not known to anyone else yet.
    var canRemoveRecordings: Bool { phase != .starting && phase != .stopping }

    /// Whether a clean may remove this recording: not the one being made, and not one an editor has open.
    func mayRemove(_ id: UUID) -> Bool {
        id != recorder.currentRecordingID && editors?.isOpen(folder: store.folder(for: id)) != true
    }

    private var isCurrent: Bool { !isShuttingDown && module?.isCurrent(context) == true }

    // MARK: Starting

    /// Picks what to record and starts: permissions, then the overlay (or the display under the pointer), then the countdown if it
    /// is on. Does nothing while another recording or an overlay is in the way.
    func begin(_ target: RecordingTarget) async {
        guard let module, phase == .idle, !module.isSelecting, !isShuttingDown else { return }
        guard module.hasScreenAccess() else {
            module.showPermissionHint()
            return
        }
        let options = recordingOptions()
        // From here the phase says so, also while the system asks about the microphone: the answer has to come before the
        // overlay and the countdown, or its prompt would eat the countdown.
        phase = .selecting
        guard await microphoneIsReady(for: options) else {
            if isCurrent { phase = .idle }
            return
        }
        guard isCurrent else { return }
        context.presenter.close()
        let region: RecordingRegion?
        do {
            region = try await module.selectRegion(for: target)
        } catch {
            guard isCurrent else { return }
            phase = .idle
            module.report(error)
            return
        }
        guard isCurrent else { return }
        // Nil is Esc, or an answer with nothing left to record.
        guard let region else {
            phase = .idle
            return
        }
        if context.settings.value(keys.recordCountdown) {
            pending = (region, options)
            setCountdown(Self.countdownSeconds)
        } else {
            await startSession(region, options)
        }
    }

    private func recordingOptions() -> RecordingOptions {
        let settings = context.settings
        return RecordingOptions(
            microphone: MicrophoneChoice.selection(for: settings.value(keys.recordMicrophone), available: dependencies.microphones()),
            systemAudio: settings.value(keys.recordSystemAudio)
        )
    }

    /// True when no microphone is wanted or it may be used. A microphone never asked about is asked now; a refusal says how to
    /// change it and nothing starts.
    private func microphoneIsReady(for options: RecordingOptions) async -> Bool {
        guard options.microphone != nil else { return true }
        var status = context.permissions.status(of: .microphone)
        if status == .notDetermined { status = await context.permissions.request(.microphone) }
        guard status == .granted else {
            if isCurrent { show(.microphoneDenied) }
            return false
        }
        return true
    }

    private func setCountdown(_ seconds: Int) {
        phase = .countdown(seconds)
        context.activities.set(RecordingActivity.countdown(seconds: seconds) { [weak self] in self?.cancelCountdown() })
        countdown = context.scheduler.schedule(after: .seconds(1)) { [weak self] in self?.countdownElapsed() }
    }

    private func countdownElapsed() {
        guard case .countdown(let left) = phase else { return }
        if left > 1 {
            setCountdown(left - 1)
            return
        }
        guard let pending else {
            cancelCountdown()
            return
        }
        self.pending = nil
        countdown = nil
        // The phase changes now and not when the task runs, so a cancel in between finds nothing to cancel.
        phase = .starting
        context.run { [weak self] in await self?.startSession(pending.region, pending.options) }
    }

    /// Stops a countdown before it ends; nothing was started.
    func cancelCountdown() {
        guard case .countdown = phase else { return }
        countdown?.cancel()
        countdown = nil
        pending = nil
        phase = .idle
        context.activities.clear(id: RecordingActivity.id)
    }

    private func startSession(_ region: RecordingRegion, _ options: RecordingOptions) async {
        phase = .starting
        do {
            try await recorder.start(region: region, options: options)
        } catch {
            phase = .idle
            context.activities.clear(id: RecordingActivity.id)
            if isCurrent { show(error) }
            return
        }
        guard !isShuttingDown else {
            _ = try? await recorder.stop()
            phase = .idle
            return
        }
        phase = .recording
        publish()
        await refreshList()
    }

    // MARK: Pause and stop

    func togglePause() async {
        guard phase.hasRecording, !isChangingPause else { return }
        isChangingPause = true
        defer { isChangingPause = false }
        if phase == .recording {
            await recorder.pause()
            guard phase == .recording else { return }
            phase = .paused
        } else {
            do {
                try await recorder.resume()
            } catch {
                if isCurrent { show(error) }
                return
            }
            guard phase == .paused else { return }
            phase = .recording
        }
        publish()
    }

    /// Ends the recording and opens it in the editor; during the countdown it only cancels.
    func stop() async {
        if case .countdown = phase {
            cancelCountdown()
            return
        }
        guard phase.hasRecording else { return }
        phase = .stopping
        publish()
        do {
            let project = try await recorder.stop()
            phase = .idle
            context.activities.clear(id: RecordingActivity.id)
            await openEditor(for: project)
        } catch {
            phase = .idle
            context.activities.clear(id: RecordingActivity.id)
            if isCurrent { show(error) }
            await refreshList()
        }
    }

    /// The recording ended without being asked to: the system stopped the stream, or writing failed. What could be kept was kept.
    private func recorderEnded(_ result: Result<RecordingProject, RecordingError>) {
        guard phase.hasRecording else { return }
        phase = .idle
        context.activities.clear(id: RecordingActivity.id)
        context.run { [weak self] in await self?.handleEnd(result) }
    }

    private func handleEnd(_ result: Result<RecordingProject, RecordingError>) async {
        switch result {
        case .failure(let error):
            show(error)
            await refreshList()
        case .success(let project):
            await openEditor(for: project)
            let interrupted = project.status == .interrupted
            module?.showToast(
                interrupted ? "Quay bị dừng giữa chừng, phần đã quay vẫn còn" : "Đã dừng quay",
                systemImage: interrupted ? "exclamationmark.triangle.fill" : "stop.circle.fill"
            )
        }
    }

    // MARK: The notch and the menu

    /// The activity for the phase: the clock starts where the recording is, and the system advances it, so nothing is published
    /// on a tick.
    private func publish() {
        switch phase {
        case .recording, .paused:
            let now = Date.now
            context.activities.set(RecordingActivity.recording(
                startedAt: now.addingTimeInterval(-recorder.elapsed), pausedAt: phase == .paused ? now : nil,
                pause: { [weak self] in self?.runTogglePause() }, stop: { [weak self] in self?.runStop() }
            ))
        case .stopping:
            context.activities.set(RecordingActivity.saving())
        default:
            break
        }
    }

    private func runTogglePause() {
        context.run { [weak self] in await self?.togglePause() }
    }

    private func runStop() {
        context.run { [weak self] in await self?.stop() }
    }

    /// The status-bar menu's entries while something is going on. The module cannot tell whether the notch is hidden, so they are
    /// offered whenever a recording runs, and the menu asks each time it opens, which keeps the clock current.
    var menuItems: [ModuleMenuItem] {
        switch phase {
        case .countdown(let seconds):
            return [ModuleMenuItem(id: "cancelRecording", title: "Huỷ quay (còn \(seconds) giây)") { [weak self] in self?.cancelCountdown() }]
        case .recording, .paused:
            return [
                ModuleMenuItem(id: "stopRecording", title: "🔴 Dừng quay (\(RecordingElapsed.text(recorder.elapsed)))") { [weak self] in
                    self?.runStop()
                },
                ModuleMenuItem(id: "pauseRecording", title: phase == .paused ? "Tiếp tục quay" : "Tạm dừng quay") { [weak self] in
                    self?.runTogglePause()
                },
            ]
        default:
            return []
        }
    }

    // MARK: Shortcuts

    /// Starts a recording (region, window or whole screen, as the overlay offers), or ends the one that is going on.
    func toggleFromShortcut() {
        switch phase {
        case .idle: context.run { [weak self] in await self?.begin(.any) }
        case .countdown: cancelCountdown()
        case .recording, .paused: runStop()
        case .selecting, .starting, .stopping: break
        }
    }

    func pauseFromShortcut() {
        guard phase.hasRecording else { return }
        runTogglePause()
    }

    // MARK: Recordings

    /// Reads the folder again. Never while the stream starts, when the new recording's project could be taken for one a crash left
    /// (`RecordingStore.list` rescues those); a recording that runs is named, so it is left alone.
    func refreshList() async {
        guard phase != .starting else { return }
        let active = Set(recorder.currentRecordingID.map { [$0] } ?? [])
        let list = await store.list(excluding: active)
        guard isCurrent else { return }
        state.recordings = list
    }

    /// Writes the person's defaults into a recording that was just made, then opens it. A failure to write them only means it opens
    /// with the standard ones.
    private func openEditor(for project: RecordingProject) async {
        let folder = store.folder(for: project.id)
        let settings = context.settings
        let defaults = RecordingDefaults(
            exportLevel: settings.value(keys.exportLevel), zoomScale: settings.value(keys.zoomScale),
            zoomHoldSeconds: settings.value(keys.zoomHoldSeconds), clickEffect: settings.value(keys.clickEffect)
        )
        do {
            try await Self.write(defaults, to: folder)
        } catch {
            context.logger.error("Could not write the defaults of a new recording: \(error, privacy: .public)")
        }
        await refreshList()
        guard isCurrent else { return }
        open(folder: folder)
    }

    @concurrent private nonisolated static func write(_ defaults: RecordingDefaults, to folder: URL) async throws {
        try defaults.write(to: folder)
    }

    /// "Mở" in the list.
    func open(_ id: UUID) {
        guard id != recorder.currentRecordingID else {
            show("Bản quay này đang quay, dừng quay rồi mới sửa được")
            return
        }
        open(folder: store.folder(for: id))
    }

    private func open(folder: URL) {
        guard let module else { return }
        // The editor is a window of its own; the notch has nothing more to show behind it.
        context.presenter.close()
        let editors = editors ?? dependencies.makeEditors(module)
        self.editors = editors
        do {
            try editors.open(folder: folder)
        } catch {
            show(error.message)
        }
    }

    /// "Xoá" in the list, after the person said yes. Removes that recording's folder and nothing else: the exported files in
    /// `~/Movies/MyNotch` are the person's own. The one being recorded, and one an editor has open, stay.
    func delete(_ id: UUID) async {
        guard phase != .starting, id != recorder.currentRecordingID else {
            show("Bản quay này đang quay, dừng quay rồi mới xoá được")
            return
        }
        if editors?.isOpen(folder: store.folder(for: id)) == true {
            show("Bản quay này đang mở trong cửa sổ sửa, đóng cửa sổ rồi mới xoá được")
            return
        }
        let removed = await Self.remove(id, from: store)
        await refreshList()
        if !removed { show("Không xoá được bản quay") }
    }

    @concurrent private nonisolated static func remove(_ id: UUID, from store: RecordingStore) async -> Bool {
        store.remove(id: id)
    }

    // MARK: Ending

    /// The module stops: a countdown is cancelled, a recording is closed properly (it is kept, whole) and the editors close.
    func shutdown() async {
        isShuttingDown = true
        recorder.onEnded = nil
        cancelCountdown()
        while phase == .starting || phase == .stopping { try? await Task.sleep(for: .milliseconds(10)) }
        if phase.hasRecording { _ = try? await recorder.stop() }
        phase = .idle
        context.activities.clear(id: RecordingActivity.id)
        editors?.closeAll()
        editors = nil
    }

    // MARK: Messages

    private func show(_ error: RecordingError) {
        switch error {
        case .screenRecordingDenied:
            module?.showPermissionHint()
        case .microphoneDenied:
            show(
                "Cần quyền Micrô để quay có tiếng: bật MyNotch trong Cài đặt hệ thống → Quyền riêng tư & Bảo mật → Micrô, hoặc tắt micro trong cài đặt quay",
                duration: .seconds(5)
            )
        default:
            show(error.message)
        }
    }

    private func show(_ text: String, duration: Duration = .seconds(2)) {
        module?.showToast(text, systemImage: "exclamationmark.triangle.fill", duration: duration)
    }
}
