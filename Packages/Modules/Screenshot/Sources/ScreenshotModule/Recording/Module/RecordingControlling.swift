import AppKit
import Foundation
import MyNotchCore

/// What the module needs of a recording session. A protocol so the module's tests record nothing and encode nothing.
protocol RecordingControlling: AnyObject {
    var state: RecordingSession.State { get }
    /// Seconds recorded so far, pauses left out.
    var elapsed: TimeInterval { get }
    var currentRecordingID: UUID? { get }
    /// Called when the recording ended without `stop()`: the system stopped the stream, or writing failed.
    var onEnded: ((Result<RecordingProject, RecordingError>) -> Void)? { get set }

    func start(region: RecordingRegion, options: RecordingOptions) async throws(RecordingError)
    func pause() async
    func resume() async throws(RecordingError)
    @discardableResult func stop() async throws(RecordingError) -> RecordingProject
}

extension RecordingSession: RecordingControlling {}

/// How the person picks what to record.
nonisolated enum RecordingTarget: Equatable, Sendable {
    /// The display under the pointer, at once.
    case screen
    case window
    case region
    /// A region, a window after Space, or the whole screen after Return: what the shortcut offers.
    case any

    /// The overlay's mode; nil for the whole screen, which needs no overlay.
    var selectionMode: SelectionMode? {
        switch self {
        case .screen: nil
        case .window: .recordWindow
        case .region: .recordRegion
        case .any: .recordRegionOrWindow
        }
    }
}

/// Where the module is in making a recording. The tab, the notch and the menu all read it.
nonisolated enum RecordingPhase: Equatable, Sendable {
    case idle
    /// The permissions are being checked, or the overlay is up.
    case selecting
    /// Seconds left before the recording starts.
    case countdown(Int)
    /// The stream is being started.
    case starting
    case recording
    case paused
    /// The files are being closed.
    case stopping

    /// Something is going on that a clean-up must not disturb.
    var isBusy: Bool { self != .idle }
    /// A recording exists: it is being made or is paused.
    var hasRecording: Bool { self == .recording || self == .paused }
}

/// What the module gets from the system for recording, all of it replaceable: tests give fakes, so none of them touches the
/// screen, a microphone or a window.
struct RecordingDependencies {
    /// The recording session for a module's recordings folder.
    var makeRecorder: @MainActor (_ store: RecordingStore, _ context: ModuleContext) -> any RecordingControlling
    var makeEditors: @MainActor (ScreenshotModule) -> any RecordingEditorHosting
    /// Where the pointer is now, in AppKit points: the display under it is the one "Màn hình" records.
    var pointerLocation: @MainActor () -> CGPoint
    var microphones: @MainActor () -> [MicrophoneDevice]

    static let live = RecordingDependencies(
        makeRecorder: { store, context in
            RecordingSession(
                source: ScreenCaptureKitSource(), events: SystemActivityEvents(), permissions: context.permissions, store: store,
                scheduler: context.scheduler
            )
        },
        makeEditors: { RecordingEditorWindowController(pasteboard: $0.pasteboard) },
        pointerLocation: { NSEvent.mouseLocation },
        microphones: { MicrophoneDevice.available() }
    )
}
