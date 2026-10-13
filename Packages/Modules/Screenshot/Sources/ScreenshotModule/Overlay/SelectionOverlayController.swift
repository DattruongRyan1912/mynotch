import AppKit

/// Covers every display with its frozen frame and lets the user pick what to capture. A thin shell around
/// `OverlayInteraction`, which holds all the decisions: this class creates the panels, forwards events and
/// closes everything, releasing the frozen images, as soon as there is a result.
final class SelectionOverlayController: SelectionOverlay {
    private let processID: pid_t
    private var panels: [SelectionPanel] = []
    private var views: [SelectionView] = []
    private var interaction: OverlayInteraction?
    /// What the views show now, so a pointer that only moves does not redraw them.
    private var shown: (highlight: OverlayInteraction.Highlight, hint: String)?
    private var continuation: CheckedContinuation<CaptureResult?, Never>?
    /// Counts the runs, so a cancellation of an earlier one that arrives late cannot end a later one.
    private var runNumber = 0
    private var screenChangeObserver: (any NSObjectProtocol)?
    /// The screens' frames when the overlay came up.
    private var screenFrames: [CGRect] = []

    /// `processID` is the app's own, whose windows window mode never offers.
    init(processID: pid_t = ProcessInfo.processInfo.processIdentifier) {
        self.processID = processID
    }

    func run(mode: SelectionMode, frozen: [FrozenDisplay], windows: [CapturableWindow]) async -> CaptureResult? {
        guard continuation == nil, !frozen.isEmpty else { return nil }
        runNumber += 1
        let number = runNumber
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                present(mode: mode, frozen: frozen, windows: windows)
            }
        } onCancel: {
            Task { @MainActor in
                if self.runNumber == number { self.cancel() }
            }
        }
    }

    func cancel() {
        finish(nil)
    }

    private func present(mode: SelectionMode, frozen: [FrozenDisplay], windows: [CapturableWindow]) {
        interaction = OverlayInteraction(mode: mode, displays: frozen.map(\.info), windows: windows, excludingPID: processID)
        for display in frozen {
            let view = SelectionView(display: display.info, image: display.image)
            view.onEvent = { [weak self] in self?.handle($0) }
            let panel = SelectionPanel(frame: display.info.frame)
            panel.contentView = view
            panels.append(panel)
            views.append(view)
        }
        refresh()
        // A display that comes, goes or moves leaves the frozen frames stale, so the overlay gives up instead.
        screenFrames = NSScreen.screens.map(\.frame)
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                if let self, NSScreen.screens.map(\.frame) != self.screenFrames { self.cancel() }
            }
        }
        panels.forEach { $0.orderFrontRegardless() }
        // The panel under the pointer takes the keyboard; being non-activating, it does so without activating the app.
        let pointer = NSEvent.mouseLocation
        let index = panels.firstIndex { $0.frame.contains(pointer) } ?? 0
        panels[index].makeKeyAndOrderFront(nil)
        panels[index].makeFirstResponder(views[index])
    }

    private func handle(_ event: SelectionEvent) {
        guard var current = interaction else { return }
        let pointer = NSEvent.mouseLocation
        let outcome: OverlayInteraction.Outcome
        switch event {
        case .moved:
            current.pointerMoved(to: pointer)
            outcome = .none
        case .down:
            outcome = current.mouseDown(at: pointer)
        case .dragged:
            current.mouseDragged(to: pointer)
            outcome = .none
        case .up:
            outcome = current.mouseUp(at: pointer)
        case .key(let key):
            outcome = current.keyDown(key, pointer: pointer)
        }
        interaction = current
        switch outcome {
        case .none: refresh()
        case .cancel: finish(nil)
        case .finish(let result): finish(result)
        }
    }

    private func refresh() {
        guard let interaction else { return }
        let state = (highlight: interaction.highlight, hint: interaction.hint)
        guard shown?.highlight != state.highlight || shown?.hint != state.hint else { return }
        shown = state
        views.forEach { $0.apply(state.highlight, hint: state.hint) }
    }

    /// Closes the panels, drops the frozen images and resumes `run`. Does nothing when no overlay is up.
    private func finish(_ result: CaptureResult?) {
        guard let continuation else { return }
        self.continuation = nil
        interaction = nil
        shown = nil
        if let screenChangeObserver { NotificationCenter.default.removeObserver(screenChangeObserver) }
        screenChangeObserver = nil
        views.forEach { $0.releaseImage() }
        for panel in panels {
            panel.orderOut(nil)
            panel.contentView = nil
            panel.close()
        }
        panels = []
        views = []
        continuation.resume(returning: result)
    }
}
