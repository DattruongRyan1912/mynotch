import CoreGraphics
import Foundation
@testable import ScreenshotModule

/// Hands out canned frozen displays and window images; never touches ScreenCaptureKit.
final class FakeCaptureService: CaptureService {
    var frozen: [FrozenDisplay] = []
    /// Called as the screens are frozen, to see what is on screen at that moment.
    var onFreeze: (() -> Void)?
    var freezeError: CaptureError?
    var windowImage: CGImage?
    var windowError: CaptureError?
    var displaysError: CaptureError?
    private(set) var freezeCount = 0
    private(set) var displayRequests = 0
    private(set) var windowCaptures: [(id: CGWindowID, includeShadow: Bool)] = []

    func freezeDisplays() async throws -> [FrozenDisplay] {
        freezeCount += 1
        onFreeze?()
        if let freezeError { throw freezeError }
        return frozen
    }

    /// The displays of the frozen frames, without freezing anything.
    func currentDisplays() async throws -> [DisplayInfo] {
        displayRequests += 1
        if let displaysError { throw displaysError }
        return frozen.map(\.info)
    }

    func captureWindow(id: CGWindowID, includeShadow: Bool) async throws -> CGImage {
        windowCaptures.append((id, includeShadow))
        if let windowError { throw windowError }
        guard let windowImage else { throw CaptureError.failed("no window image") }
        return windowImage
    }
}

/// Answers `run` with a canned result, at once or once released, and records what it was asked to show.
final class FakeOverlay: SelectionOverlay {
    var result: CaptureResult?
    /// While set, `run` waits for `release` or `cancel`.
    var isGated = false
    private(set) var runs: [(mode: SelectionMode, frozen: [FrozenDisplay], windows: [CapturableWindow])] = []
    private(set) var cancelCount = 0
    private var waiting: CheckedContinuation<CaptureResult?, Never>?

    func run(mode: SelectionMode, frozen: [FrozenDisplay], windows: [CapturableWindow]) async -> CaptureResult? {
        runs.append((mode, frozen, windows))
        guard isGated else { return result }
        return await withCheckedContinuation { waiting = $0 }
    }

    func cancel() {
        cancelCount += 1
        release(nil)
    }

    func release(_ result: CaptureResult?) {
        guard let waiting else { return }
        self.waiting = nil
        waiting.resume(returning: result)
    }
}

/// Fake color picker overlay recording runs and handing out canned results.
final class FakeColorPickerOverlay: ColorPickerOverlay {
    var result: ColorPickerResult?
    var isGated = false
    private(set) var runs: [(frozen: [FrozenDisplay], initialFormat: ColorFormat)] = []
    private(set) var cancelCount = 0
    private var waiting: CheckedContinuation<ColorPickerResult?, Never>?
    private var onFormatChange: ((ColorFormat) -> Void)?

    func run(
        frozen: [FrozenDisplay],
        initialFormat: ColorFormat,
        onFormatChange: @escaping (ColorFormat) -> Void
    ) async -> ColorPickerResult? {
        runs.append((frozen, initialFormat))
        self.onFormatChange = onFormatChange
        guard isGated else { return result }
        return await withCheckedContinuation { waiting = $0 }
    }

    func cancel() {
        cancelCount += 1
        release(nil)
    }

    func release(_ result: ColorPickerResult?) {
        guard let waiting else { return }
        self.waiting = nil
        waiting.resume(returning: result)
    }

    func simulateFormatChange(_ format: ColorFormat) {
        onFormatChange?(format)
    }
}

/// Fake pinned window manager recording pinning and closures.
final class FakePinnedWindowManager: PinnedWindowManaging {
    private(set) var pinnedItems: [PinnedItem] = []
    private(set) var actionsByID: [UUID: PinnedWindowActions] = [:]
    private(set) var closeCount = 0
    private(set) var closeAllCount = 0

    @discardableResult
    func pin(
        image: CGImage,
        scale: CGFloat,
        record: CaptureRecord?,
        sourceFrame: CGRect?,
        actions: PinnedWindowActions
    ) -> PinnedItem {
        let item = PinnedItem(
            recordID: record?.id,
            image: image,
            scale: scale,
            sourceFrame: sourceFrame
        )
        pinnedItems.append(item)
        actionsByID[item.id] = actions
        return item
    }

    func close(id: UUID) {
        closeCount += 1
        pinnedItems.removeAll(where: { $0.id == id })
        actionsByID.removeValue(forKey: id)
    }

    func close(recordID: UUID) {
        let matchingIDs = pinnedItems.compactMap { $0.recordID == recordID ? $0.id : nil }
        for id in matchingIDs {
            close(id: id)
        }
    }

    func closeAll() {
        closeAllCount += 1
        pinnedItems.removeAll()
        actionsByID.removeAll()
    }
}

/// Recognises nothing but a canned text, immediately or once released.
final class FakeRecognizer: TextRecognizing {
    var text = "Xin chào"
    var error: (any Error)?
    var isGated = false
    private(set) var calls: [(size: CGSize, languages: [String])] = []
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func recognize(_ image: CGImage, languages: [String]) async throws -> String {
        calls.append((CGSize(width: image.width, height: image.height), languages))
        if isGated { await withCheckedContinuation { waiting.append($0) } }
        if let error { throw error }
        return text
    }

    func release() {
        waiting.forEach { $0.resume() }
        waiting.removeAll()
    }
}

/// Fake implementation of SubjectLifting for unit testing.
final class FakeSubjectLifter: SubjectLifting, @unchecked Sendable {
    var result: CGImage?
    var error: (any Error)?
    var isGated = false
    private(set) var calls: [(image: CGImage, cropToSubject: Bool)] = []
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func liftSubject(from image: CGImage, cropToSubject: Bool) async throws -> CGImage? {
        calls.append((image, cropToSubject))
        if isGated { await withCheckedContinuation { waiting.append($0) } }
        if let error { throw error }
        return result
    }

    func release() {
        waiting.forEach { $0.resume() }
        waiting.removeAll()
    }
}

/// Records writes instead of touching a pasteboard.
final class FakePasteboard: PasteboardWriting {
    var succeeds = true
    private(set) var images: [(image: CGImage, scale: CGFloat, markedAsOwn: Bool)] = []
    private(set) var texts: [String] = []
    private(set) var files: [(url: URL, markedAsOwn: Bool)] = []

    func write(_ image: CGImage, scale: CGFloat, markedAsOwn: Bool) async -> Bool {
        images.append((image, scale, markedAsOwn))
        return succeeds
    }

    func write(fileURL: URL, markedAsOwn: Bool) -> Bool {
        files.append((fileURL, markedAsOwn))
        return succeeds
    }

    func write(_ text: String) -> Bool {
        texts.append(text)
        return succeeds
    }
}

/// What the module reads from the system, changeable per test.
final class FakeSystem {
    var hasScreenAccess = true
    var windows: [CapturableWindow] = []
    var saveDirectory: URL?
}

/// Shows nothing: records what the module asks the chip window to show and hide, and lets a test press its buttons.
final class FakeCaptureChip: CaptureChipPresenting {
    private(set) var shown: [CaptureChipContent] = []
    private(set) var hideCount = 0
    private(set) var isVisible = false

    /// What the chip on screen holds, nil while there is none.
    var current: CaptureChipContent? { isVisible ? shown.last : nil }

    func show(_ content: CaptureChipContent) {
        shown.append(content)
        isVisible = true
    }

    func hide() {
        hideCount += 1
        isVisible = false
    }
}

/// Opens no window: records which capture the module asked an editor for.
final class FakeEditors: MarkupEditorHosting {
    private(set) var opened: [(record: CaptureRecord, source: MarkupEditorSource)] = []
    private(set) var closeAllCount = 0

    func open(_ record: CaptureRecord, source: MarkupEditorSource) {
        opened.append((record, source))
    }

    func closeAll() {
        closeAllCount += 1
    }
}

/// Opens no window: records which recording the module asked an editor for, and which ones are "open".
final class FakeRecordingEditors: RecordingEditorHosting {
    private(set) var opened: [URL] = []
    private(set) var closeAllCount = 0
    var openError: RecordingEditorError?
    /// An export is running in one of the editors.
    var isExporting = false
    private var open: Set<URL> = []

    func open(folder: URL) throws(RecordingEditorError) {
        if let openError { throw openError }
        opened.append(folder)
        open.insert(folder.standardizedFileURL)
    }

    func isOpen(folder: URL) -> Bool {
        open.contains(folder.standardizedFileURL)
    }

    /// The editor of `folder` is closed by the person.
    func close(folder: URL) {
        open.remove(folder.standardizedFileURL)
    }

    func closeAll() {
        closeAllCount += 1
        open.removeAll()
    }
}

/// A recorder that records nothing: it makes the folder and project a real session would, so the list, the defaults and a delete
/// have something to work on, and lets a test end it the ways a session ends.
final class FakeRecorder: RecordingControlling {
    var state = RecordingSession.State.idle
    var elapsed: TimeInterval = 0
    var currentRecordingID: UUID?
    var onEnded: ((Result<RecordingProject, RecordingError>) -> Void)?
    var store: RecordingStore?
    var startError: RecordingError?
    var resumeError: RecordingError?
    var stopError: RecordingError?
    /// While set, `start` waits for `releaseStart`.
    var isStartGated = false
    private(set) var starts: [(region: RecordingRegion, options: RecordingOptions)] = []
    private(set) var pauseCount = 0
    private(set) var resumeCount = 0
    private(set) var stopCount = 0
    private var waitingStart: CheckedContinuation<Void, Never>?

    func start(region: RecordingRegion, options: RecordingOptions) async throws(RecordingError) {
        starts.append((region, options))
        if isStartGated { await withCheckedContinuation { waitingStart = $0 } }
        if let startError { throw startError }
        let made = try? store?.create()
        let id = made?.id ?? UUID()
        currentRecordingID = id
        if let made { try? Self.project(id: id, region: region, status: .recording, seconds: 0).write(to: made.folder) }
        state = .recording
    }

    func releaseStart() {
        waitingStart?.resume()
        waitingStart = nil
    }

    func pause() async {
        pauseCount += 1
        state = .paused
    }

    func resume() async throws(RecordingError) {
        resumeCount += 1
        if let resumeError { throw resumeError }
        state = .recording
    }

    func stop() async throws(RecordingError) -> RecordingProject {
        stopCount += 1
        if let stopError {
            state = .idle
            currentRecordingID = nil
            throw stopError
        }
        let project = finish(status: .finished)
        state = .idle
        currentRecordingID = nil
        return project
    }

    /// The session ends by itself, as when the system stops the stream or writing fails.
    func end(_ status: RecordingProject.Status?, error: RecordingError? = nil) {
        guard state == .recording || state == .paused else { return }
        let result: Result<RecordingProject, RecordingError>
        if let status {
            result = .success(finish(status: status))
        } else {
            result = .failure(error ?? .failed("test"))
        }
        state = .idle
        currentRecordingID = nil
        onEnded?(result)
    }

    private func finish(status: RecordingProject.Status) -> RecordingProject {
        let id = currentRecordingID ?? UUID()
        let region = starts.last?.region
        let project = Self.project(id: id, region: region, status: status, seconds: max(elapsed, 3))
        if let store { try? project.write(to: store.folder(for: id)) }
        return project
    }

    static func project(id: UUID, region: RecordingRegion?, status: RecordingProject.Status, seconds: TimeInterval) -> RecordingProject {
        let region = region ?? RecordingRegion(fullScreen: DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 80), scale: 2))!
        return RecordingProject(
            id: id, createdAt: Date(timeIntervalSince1970: 1_800_000_000), status: status, region: region, fps: 60, hasMicrophone: true,
            hasSystemAudio: false,
            segments: seconds > 0 ? [.init(fileName: "segment-001.mov", captureStart: 0, duration: seconds, frames: 180)] : []
        )
    }
}

/// What the module gets from the system for recording, as fakes: nothing records, opens a window or listens to a microphone.
final class FakeRecordingSystem {
    let recorder = FakeRecorder()
    let editors = FakeRecordingEditors()
    var pointer = CGPoint(x: 10, y: 10)
    var microphones: [MicrophoneDevice] = []

    var dependencies: RecordingDependencies {
        RecordingDependencies(
            makeRecorder: { [recorder] store, _ in
                recorder.store = store
                return recorder
            },
            makeEditors: { [editors] _ in editors },
            pointerLocation: { [unowned self] in pointer },
            microphones: { [unowned self] in microphones }
        )
    }
}

/// Fake scrolling capture live preview HUD recorder for unit tests.
final class FakeScrollingPreview: ScrollingPreviewPresenting {
    private(set) var isShowing = false
    private(set) var shownCanvas: CGImage?
    private(set) var updatedCanvases: [CGImage] = []
    private(set) var frameCount: Int = 0
    private(set) var avoidingRect: CGRect?
    var onFinish: (@MainActor () -> Void)?
    var onCancel: (@MainActor () -> Void)?

    func show(
        canvas: CGImage,
        frameCount: Int,
        avoidingRect: CGRect?,
        onFinish: @escaping @MainActor () -> Void,
        onCancel: @escaping @MainActor () -> Void
    ) {
        isShowing = true
        shownCanvas = canvas
        self.frameCount = frameCount
        self.avoidingRect = avoidingRect
        self.onFinish = onFinish
        self.onCancel = onCancel
    }

    func update(canvas: CGImage, frameCount: Int) {
        updatedCanvases.append(canvas)
        self.frameCount = frameCount
    }

    func hide() {
        isShowing = false
    }

    func triggerFinish() {
        onFinish?()
    }

    func triggerCancel() {
        onCancel?()
    }
}
