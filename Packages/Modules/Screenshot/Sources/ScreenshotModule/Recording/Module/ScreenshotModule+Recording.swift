import CoreGraphics
import Foundation

/// What the tab, the shortcuts and the menu ask of the module for recording. The work is the coordinator's; what waits runs in the
/// module's context, so stopping the module cancels it.
extension ScreenshotModule {
    /// The region to record. A whole screen is the display under the pointer, at once; a window, a region, or whichever the
    /// shortcut offers, comes from the overlay over the frozen screens, which are released before this returns. Nil when the person
    /// cancelled.
    func selectRegion(for target: RecordingTarget) async throws -> RecordingRegion? {
        guard let mode = target.selectionMode else {
            let displays = try await service.currentDisplays()
            guard let display = GeometryMapper.display(containing: recordingDependencies.pointerLocation(), in: displays) ?? displays.first else {
                throw CaptureError.noDisplays
            }
            return RecordingRegion(fullScreen: display)
        }
        isSelecting = true
        defer { isSelecting = false }
        // The chip is a window of its own: gone before the screens are frozen, as for a capture.
        chip?.hide()
        let frozen = try await service.freezeDisplays()
        guard !frozen.isEmpty else { throw CaptureError.noDisplays }
        let windows = onScreenWindows()
        guard let result = await overlay.run(mode: mode, frozen: frozen, windows: windows) else { return nil }
        return RecordingSelection.region(for: result, displays: frozen.map(\.info), windows: windows)
    }

    func beginRecording(_ target: RecordingTarget) {
        context?.run { [weak self] in await self?.recording?.begin(target) }
    }

    func stopRecording() {
        context?.run { [weak self] in await self?.recording?.stop() }
    }

    func toggleRecordingPause() {
        context?.run { [weak self] in await self?.recording?.togglePause() }
    }

    func cancelRecordingCountdown() {
        recording?.cancelCountdown()
    }

    func openRecording(_ summary: RecordingSummary) {
        recording?.open(summary.id)
    }

    func deleteRecording(_ summary: RecordingSummary) {
        context?.run { [weak self] in await self?.recording?.delete(summary.id) }
    }

    func refreshRecordings() async {
        await recording?.refreshList()
    }

    /// Seconds recorded so far, for the tab's clock.
    var recordingElapsed: TimeInterval { recording?.elapsed ?? 0 }
}
