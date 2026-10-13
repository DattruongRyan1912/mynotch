import CoreGraphics
import Foundation
@testable import ScreenshotModule

/// Hands out canned frozen displays and window images; never touches ScreenCaptureKit.
final class FakeCaptureService: CaptureService {
    var frozen: [FrozenDisplay] = []
    var freezeError: CaptureError?
    var windowImage: CGImage?
    var windowError: CaptureError?
    private(set) var freezeCount = 0
    private(set) var windowCaptures: [(id: CGWindowID, includeShadow: Bool)] = []

    func freezeDisplays() async throws -> [FrozenDisplay] {
        freezeCount += 1
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
    private(set) var images: [(image: CGImage, scale: CGFloat)] = []
    private(set) var texts: [String] = []

    func write(_ image: CGImage, scale: CGFloat) async -> Bool {
        images.append((image, scale))
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
