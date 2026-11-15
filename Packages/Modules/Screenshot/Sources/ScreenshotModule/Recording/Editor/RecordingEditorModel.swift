import AppKit
import AVFoundation
import Observation

/// Why a recording could not be opened for editing.
nonisolated enum RecordingEditorError: Error, Equatable, Sendable {
    /// Still being recorded: the recorder rewrites `project.json` every few seconds and would overwrite the edits.
    case stillRecording
    case unreadable(String)

    /// One line for a toast, in Vietnamese.
    var message: String {
        switch self {
        case .stillRecording: "Bản quay này đang quay, dừng quay rồi mới sửa được"
        case .unreadable: "Không mở được bản quay để sửa"
        }
    }
}

/// How the export is going.
nonisolated enum RecordingExportState: Equatable, Sendable {
    case idle
    /// 0 to 1.
    case running(Double)
    case finished(RecordingExportResult)
    /// One line, in Vietnamese.
    case failed(String)
}

/// The recording editor's state: the edits and their history, what is selected, the preview and the export. Every time is in
/// recording time (the segments' time, pauses left out), which is also what the timeline shows; the player's own time is the
/// edited video's, and the cut map of the composition it holds goes between the two.
///
/// Edits are written to `project.json` as they are made, so closing the window loses nothing. A drag changes nothing until it
/// ends: the view calls one edit then, which is one undo step, one write and one new preview.
@Observable final class RecordingEditorModel {
    /// The edited video never gets shorter than this.
    static let minimumKept = 0.2
    /// A zoom lasts at least this long.
    static let minimumZoom = 0.5
    static let zoomScaleRange = 1.25...3.0
    /// A zoom added by hand lasts this long, as far as the recording goes on.
    static let manualZoomLength = 3.0
    /// A stretch picked on the timeline is at least this long.
    static let minimumSelection = 0.05
    static let thumbnailCount = 24

    let folder: URL
    let activity: ActivityTrack
    let player: any PreviewPlaying
    /// As last saved, apart from the edit in `history`.
    private(set) var project: RecordingProject
    private var history: EditHistory<RecordingEdit>
    /// What the activity says to zoom on, for as long as the person has not edited the zooms.
    private let planned: [ZoomSegment]
    @ObservationIgnored private let pasteboard: any PasteboardWriting
    @ObservationIgnored private let exportDirectory: URL
    @ObservationIgnored private let reveal: (URL) -> Void
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let write: (RecordingProject) throws -> Void

    var selectedZoom: Int?
    /// A stretch of the recording picked on the timeline, to cut or to bring back.
    var selection: Range<TimeInterval>?
    /// A line for the person that stays until they dismiss it.
    private(set) var message: String?

    /// The composition the player holds, with the cuts, zooms and rings as they were when it was built.
    private(set) var preview: RecordingComposition?
    /// Goes up each time the player is given a new composition.
    private(set) var previewRevision = 0
    private(set) var previewError: String?
    private(set) var thumbnails: [CGImage?] = []
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var previewGeneration = 0

    private(set) var exportState = RecordingExportState.idle
    @ObservationIgnored private var exportTask: Task<Void, Never>?

    /// `write` saves the project; tests replace it to see a save that fails. `now` is the clock that dates an export.
    init(
        folder: URL, project: RecordingProject, activity: ActivityTrack, player: any PreviewPlaying, pasteboard: any PasteboardWriting,
        exportDirectory: URL, reveal: @escaping (URL) -> Void = { _ in }, now: @escaping () -> Date = { .now },
        write: ((RecordingProject) throws -> Void)? = nil
    ) {
        self.folder = folder
        self.project = project
        self.activity = activity
        self.player = player
        self.pasteboard = pasteboard
        self.exportDirectory = exportDirectory
        self.reveal = reveal
        self.now = now
        self.write = write ?? { try $0.write(to: folder) }
        history = EditHistory(RecordingEdit(of: project))
        planned = ZoomPlanner.plan(activity: activity, rules: project.zoomRules, duration: project.duration)
    }

    /// Opens the recording in `folder`. Without `activity.json` it still opens, with no automatic zooms.
    static func load(
        folder: URL, player: any PreviewPlaying, pasteboard: any PasteboardWriting, exportDirectory: URL,
        reveal: @escaping (URL) -> Void = { _ in }, now: @escaping () -> Date = { .now }, save: ((RecordingProject) throws -> Void)? = nil
    ) throws(RecordingEditorError) -> RecordingEditorModel {
        let project: RecordingProject
        do {
            project = try RecordingProject.load(from: folder)
        } catch {
            throw .unreadable(error.localizedDescription)
        }
        guard project.status != .recording else { throw .stillRecording }
        var lost = false
        let activity: ActivityTrack
        do {
            activity = try ActivityTrack.load(from: folder)
        } catch {
            lost = true
            activity = ActivityTrack(pixelWidth: project.region.pixelWidth, pixelHeight: project.region.pixelHeight, keyboardRecorded: false)
        }
        let model = RecordingEditorModel(
            folder: folder, project: project, activity: activity, player: player, pasteboard: pasteboard,
            exportDirectory: exportDirectory, reveal: reveal, now: now, write: save
        )
        if lost { model.message = "Không đọc được dữ liệu con trỏ, nên bản quay mở không có zoom tự động" }
        return model
    }

    // MARK: Reading

    var edit: RecordingEdit { history.value }
    /// Seconds of the recording.
    var duration: TimeInterval { project.duration }
    var cutMap: CutMap { CutMap(duration: duration, cuts: edit.cuts) }
    var zoomSegments: [ZoomSegment] { edit.zoomSegments ?? planned }
    var clickEffect: Bool { edit.clickEffect }
    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }

    var exportLevel: ExportLevel {
        get { project.exportLevel }
        set {
            guard newValue != project.exportLevel, !isExporting else { return }
            project.exportLevel = newValue
            persist()
        }
    }

    /// What `project.json` holds: the recording with the edit in it.
    var currentProject: RecordingProject { edit.applied(to: project) }

    func dismissMessage() { message = nil }

    // MARK: Undo

    func undo() {
        guard !isExporting, history.undo() else { return }
        changed()
    }

    func redo() {
        guard !isExporting, history.redo() else { return }
        changed()
    }

    // MARK: Cuts

    /// Cuts everything before `time`; `0` brings it all back. A cut that already started at 0 is the one that moves. The handle
    /// stops where the other end's cut begins, leaving the shortest video there can be.
    func trimStart(to time: TimeInterval) {
        let others = cutMap.cuts.filter { $0.start > 0 }
        let limit = (cutMap.cuts.first { $0.end >= duration }?.start ?? duration) - Self.minimumKept
        var cuts = others
        let end = min(time, limit)
        if end > 0.001 { cuts.append(CutRange(start: 0, end: end)) }
        setCuts(cuts)
    }

    /// Cuts everything after `time`; the recording's end brings it all back.
    func trimEnd(to time: TimeInterval) {
        let others = cutMap.cuts.filter { $0.end < duration }
        let limit = (cutMap.cuts.first { $0.start <= 0 }?.end ?? 0) + Self.minimumKept
        var cuts = others
        let start = max(time, limit)
        if start < duration - 0.001 { cuts.append(CutRange(start: start, end: duration)) }
        setCuts(cuts)
    }

    var canCutSelection: Bool {
        guard let selection else { return false }
        return selection.upperBound - selection.lowerBound >= Self.minimumSelection && !selectionIsCut && !isExporting
    }

    /// The picked stretch lies inside what is cut already: the button then brings it back instead.
    var selectionIsCut: Bool { selection.flatMap { cut(containing: $0) } != nil }

    func cutSelection() {
        guard canCutSelection, let selection else { return }
        if setCuts(cutMap.cuts + [CutRange(start: selection.lowerBound, end: selection.upperBound)]) { self.selection = nil }
    }

    /// Brings back the cut stretch that holds the picked one.
    func restoreSelection() {
        guard !isExporting, let selection, let cut = cut(containing: selection) else { return }
        if setCuts(cutMap.cuts.filter { $0 != cut }) { self.selection = nil }
    }

    private func cut(containing range: Range<TimeInterval>) -> CutRange? {
        cutMap.cuts.first { $0.start <= range.lowerBound + 1e-6 && range.upperBound <= $0.end + 1e-6 }
    }

    /// Whether the cuts are now as asked: not when it would leave nothing, nor while an export runs.
    @discardableResult
    private func setCuts(_ cuts: [CutRange]) -> Bool {
        guard !isExporting else { return false }
        let merged = CutMap(duration: duration, cuts: cuts)
        guard merged.editedDuration >= Self.minimumKept else {
            message = "Không thể cắt hết video, phải còn lại ít nhất một đoạn"
            return false
        }
        if history.apply({ $0.cuts = merged.cuts }) { changed() }
        return true
    }

    // MARK: Zooms

    func selectZoom(_ index: Int?) {
        selectedZoom = index.flatMap { zoomSegments.indices.contains($0) ? $0 : nil }
    }

    /// The scale stays between 1.25 and 3.
    func setZoomScale(_ scale: Double, at index: Int) {
        editZoom(at: index) { $0.scale = min(max(scale, Self.zoomScaleRange.lowerBound), Self.zoomScaleRange.upperBound) }
    }

    func setZoomStart(_ time: TimeInterval, at index: Int) {
        editZoom(at: index) { $0.start = min(max(time, 0), $0.end - Self.minimumZoom) }
    }

    func setZoomEnd(_ time: TimeInterval, at index: Int) {
        let limit = duration
        editZoom(at: index) { $0.end = min(max(time, $0.start + Self.minimumZoom), limit) }
    }

    func removeSelectedZoom() {
        if let selectedZoom { removeZoom(at: selectedZoom) }
    }

    func removeZoom(at index: Int) {
        guard zoomSegments.indices.contains(index) else { return }
        editZooms { $0.remove(at: index) }
    }

    /// A zoom of three seconds from `time`, or fewer when the recording ends first, looking where the pointer was.
    func addZoom(at time: TimeInterval) {
        let start = min(max(time, 0), max(duration - Self.minimumZoom * 2, 0))
        let segment = ZoomPlanner.manualSegment(
            at: start, duration: min(Self.manualZoomLength, duration - start), activity: activity, rules: project.zoomRules
        )
        var position = 0
        editZooms { list in
            position = list.firstIndex { $0.start > segment.start } ?? list.count
            list.insert(segment, at: position)
        }
        if zoomSegments.indices.contains(position) { selectedZoom = position }
    }

    /// Re-generates zoom segments automatically from all clicks recorded in the activity.
    func generateZoomsFromClicks(holdDuration: TimeInterval = 1.5) {
        var rules = project.zoomRules
        rules.idleTimeout = holdDuration
        rules.followPointer = false
        let generated = ZoomPlanner.plan(activity: activity, rules: rules, duration: duration)
        editZooms { $0 = generated }
        selectedZoom = nil
    }

    /// Clears all zoom segments from the recording.
    func clearAllZooms() {
        editZooms { $0.removeAll() }
        selectedZoom = nil
    }

    /// Toggles a zoom segment at a specific click moment.
    /// If an existing zoom already covers this click, it is removed. Otherwise, a new zoom segment is created around it.
    func toggleZoom(atClick click: ActivityTrack.Click, holdDuration: TimeInterval = 1.5) {
        if let existingIndex = zoomSegments.firstIndex(where: { $0.start <= click.t && $0.end >= click.t }) {
            removeZoom(at: existingIndex)
            return
        }
        let start = min(max(click.t, 0), max(duration - Self.minimumZoom * 2, 0))
        let end = min(start + holdDuration, duration)
        guard end > start else { return }
        let segment = ZoomSegment(
            start: start, end: end, scale: project.zoomRules.scale,
            focus: [.init(t: click.t, x: click.x, y: click.y)], manual: true
        )
        var position = 0
        editZooms { list in
            position = list.firstIndex { $0.start > segment.start } ?? list.count
            list.insert(segment, at: position)
        }
        if zoomSegments.indices.contains(position) { selectedZoom = position }
    }

    private func editZoom(at index: Int, _ change: (inout ZoomSegment) -> Void) {
        guard zoomSegments.indices.contains(index) else { return }
        editZooms { change(&$0[index]) }
    }

    /// The first zoom edit makes the planned list the person's own, in the same step, so undoing it gives back "not edited".
    private func editZooms(_ change: (inout [ZoomSegment]) -> Void) {
        guard !isExporting else { return }
        var list = zoomSegments
        change(&list)
        guard list != zoomSegments else { return }
        if history.apply({ $0.zoomSegments = list }) { changed() }
    }

    func setClickEffect(_ isOn: Bool) {
        guard !isExporting, history.apply({ $0.clickEffect = isOn }) else { return }
        changed()
    }

    /// What every edit, undo and redo ends with.
    private func changed() {
        if let selectedZoom, !zoomSegments.indices.contains(selectedZoom) { self.selectedZoom = nil }
        persist()
        schedulePreview()
    }

    private func persist() {
        let saved = currentProject
        do {
            try write(saved)
        } catch {
            message = "Không lưu được chỉnh sửa vào thư mục bản quay"
        }
    }

    // MARK: Playback

    private var playbackCuts: CutMap { preview?.cutMap ?? cutMap }

    var isPlaying: Bool { player.isPlaying }

    /// Where the player is, in recording time: through the cuts of the composition it holds. After the last moment, the end.
    var playhead: TimeInterval { playbackCuts.recordingTime(forEdited: player.editedTime) ?? duration }

    func togglePlayback() {
        if player.isPlaying { player.pause() } else { player.play() }
    }

    func seek(toRecording time: TimeInterval) {
        player.seek(toEdited: Self.editedTime(forRecording: time, in: playbackCuts))
    }

    /// Where `time` of the recording is in the edited video. A moment that was cut is where what follows it begins, and one
    /// past the end is the end.
    static func editedTime(forRecording time: TimeInterval, in cuts: CutMap) -> TimeInterval {
        let moment = max(time, 0)
        if let edited = cuts.editedTime(forRecording: moment) { return edited }
        var offset = 0.0
        for range in cuts.kept {
            if range.lowerBound >= moment { return offset }
            offset += range.upperBound - range.lowerBound
        }
        return cuts.editedDuration
    }

    // MARK: Preview

    /// Builds the preview and the strip of pictures, which is made once: it is the recording, whatever is cut.
    func start() async {
        schedulePreview()
        await previewTask?.value
        await makeThumbnails()
    }

    /// Waits for the preview that is being built, for tests.
    func settle() async {
        await previewTask?.value
    }

    private func schedulePreview() {
        previewGeneration += 1
        let generation = previewGeneration
        let snapshot = currentProject
        let folder = folder, activity = activity
        previewTask = Task { [weak self] in
            let built: RecordingComposition
            do throws(RecordingCompositionError) {
                built = try await RecordingComposition.make(
                    project: snapshot, folder: folder, activity: activity, options: .init(renderSize: Self.previewSize(of: snapshot))
                )
            } catch {
                // A newer edit has made this one stale; its own answer is the one to show.
                guard let self, generation == self.previewGeneration else { return }
                self.previewError = error.message
                self.preview = nil
                return
            }
            guard let self, generation == self.previewGeneration else { return }
            self.show(built)
        }
    }

    /// What the preview is drawn at: no bigger than 1920×1080, which is as much as the pane shows, and the compositor takes the
    /// camera's view from the full-size picture, so a zoom stays sharp. A 5K recording is drawn at a third of the pixels, which
    /// keeps the preview smooth and its buffers small.
    static func previewSize(of project: RecordingProject) -> CGSize {
        ExportLevel.chat.plan(forVideoOfSize: CGSize(width: project.region.pixelWidth, height: project.region.pixelHeight), fps: project.fps).size
    }

    /// Gives the player the new composition, at the moment of the recording it was at.
    private func show(_ built: RecordingComposition) {
        let moment = playhead
        preview = built
        previewError = nil
        previewRevision += 1
        player.load(built.makePlayerItem(), at: Self.editedTime(forRecording: moment, in: built.cutMap))
    }

    private func makeThumbnails() async {
        var whole = project
        whole.cuts = []
        guard let built = try? await RecordingComposition.make(project: whole, folder: folder, activity: activity) else { return }
        var images = [CGImage?](repeating: nil, count: Self.thumbnailCount)
        thumbnails = images
        await RecordingThumbnails.make(
            of: built.composition, duration: built.duration, count: Self.thumbnailCount, maximumSize: CGSize(width: 480, height: 270)
        ) { index, image in
            images[index] = image
            thumbnails = images
        }
    }

    // MARK: Export

    var isExporting: Bool {
        if case .running = exportState { return true }
        return false
    }

    /// Starts exporting the recording as it is edited now, at the chosen level, and returns at once. Edits wait until it is done.
    func startExport() {
        guard !isExporting else { return }
        exportState = .running(0)
        message = nil
        exportTask = Task { await runExport() }
    }

    /// The export, waited for: for tests.
    func export() async {
        startExport()
        await waitForExport()
    }

    /// Waits for the export that is running, if there is one.
    func waitForExport() async {
        await exportTask?.value
    }

    /// Stops an export that is running; no file is left.
    func cancelExport() {
        exportTask?.cancel()
    }

    /// Shows the exported file in Finder.
    func revealExport() {
        if case .finished(let result) = exportState { reveal(result.url) }
    }

    private func runExport() async {
        do {
            let result = try await RecordingExporter.export(
                project: currentProject, folder: folder, activity: activity, level: exportLevel, into: exportDirectory,
                progress: { fraction in Task { @MainActor [weak self] in self?.noteProgress(fraction) } }
            )
            exportState = .finished(result)
            markExported()
            // Marked as MyNotch's own: the clipboard history does not record a file it was asked to put there.
            if !pasteboard.write(fileURL: result.url, markedAsOwn: true) {
                message = "Đã xuất xong nhưng không chép được file vào clipboard"
            }
        } catch RecordingExportError.cancelled {
            exportState = .idle
            message = RecordingExportError.cancelled.message
        } catch let error as RecordingExportError {
            exportState = .failed(error.message)
        } catch {
            exportState = .failed(RecordingExportError.failed(error.localizedDescription).message)
        }
    }

    /// Dates the export in the project, which is what lets the storage page delete this original later, if the person asked it to.
    /// Written through the model's own project, so the next edit, which rewrites the whole file, keeps it.
    private func markExported() {
        project.exportedAt = Date(timeIntervalSince1970: now().timeIntervalSince1970.rounded(.down))
        persist()
    }

    private func noteProgress(_ fraction: Double) {
        guard case .running(let current) = exportState, fraction > current else { return }
        exportState = .running(fraction)
    }

    /// Back to the editor after a finished or failed export.
    func dismissExport() {
        if !isExporting { exportState = .idle }
    }
}
