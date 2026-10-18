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
    private(set) var freezeCount = 0
    private(set) var windowCaptures: [(id: CGWindowID, includeShadow: Bool)] = []

    func freezeDisplays() async throws -> [FrozenDisplay] {
        freezeCount += 1
        onFreeze?()
        if let freezeError { throw freezeError }
        return frozen
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
        waiting?.resume(returning: result)
        waiting = nil
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
