import AppKit

/// Manages the full-screen color picker overlay across all connected displays.
@MainActor
final class ColorPickerOverlayController: ColorPickerOverlay {
    private var panels: [SelectionPanel] = []
    private var views: [ColorPickerView] = []
    private var interaction: ColorPickerInteraction?
    private var onFormatChange: ((ColorFormat) -> Void)?
    private var continuation: CheckedContinuation<ColorPickerResult?, Never>?
    private var runNumber = 0
    private var isCursorHidden = false
    private var screenChangeObserver: (any NSObjectProtocol)?
    private var screenFrames: [CGRect] = []

    init() {}

    func run(
        frozen: [FrozenDisplay],
        initialFormat: ColorFormat,
        onFormatChange: @escaping (ColorFormat) -> Void
    ) async -> ColorPickerResult? {
        guard continuation == nil, !frozen.isEmpty else { return nil }
        runNumber += 1
        let number = runNumber
        self.onFormatChange = onFormatChange

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                present(frozen: frozen, initialFormat: initialFormat)
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

    private func present(frozen: [FrozenDisplay], initialFormat: ColorFormat) {
        let initialPointer = NSEvent.mouseLocation
        interaction = ColorPickerInteraction(
            frozen: frozen,
            initialFormat: initialFormat,
            initialPointer: initialPointer
        )

        for display in frozen {
            let view = ColorPickerView(display: display.info, image: display.image)
            view.onEvent = { [weak self] event in
                self?.handle(event)
            }
            let panel = SelectionPanel(frame: display.info.frame)
            panel.contentView = view
            panels.append(panel)
            views.append(view)
        }

        hideCursorIfNeeded()
        refresh()

        screenFrames = NSScreen.screens.map(\.frame)
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                if let self, NSScreen.screens.map(\.frame) != self.screenFrames {
                    self.cancel()
                }
            }
        }

        panels.forEach { $0.orderFrontRegardless() }

        // Give keyboard focus to panel holding the pointer
        let pointer = NSEvent.mouseLocation
        let index = panels.firstIndex { $0.frame.contains(pointer) } ?? 0
        panels[index].makeKeyAndOrderFront(nil)
        panels[index].makeFirstResponder(views[index])
    }

    private func handle(_ event: ColorPickerEvent) {
        guard var current = interaction else { return }

        switch event {
        case .moved(let pt, let shift):
            current.pointerMoved(to: pt, shiftDown: shift)
            self.interaction = current
            refresh()

        case .down(let pt, let shift, let cmd):
            let outcome = current.mouseDown(at: pt, shiftDown: shift, commandDown: cmd)
            self.interaction = current
            applyOutcome(outcome)

        case .key(let key):
            let outcome = current.keyDown(key)
            self.interaction = current
            applyOutcome(outcome)
        }
    }

    private func applyOutcome(_ outcome: ColorPickerInteraction.Outcome) {
        switch outcome {
        case .none:
            refresh()

        case .formatChanged(let newFormat):
            onFormatChange?(newFormat)
            refresh()

        case .pickedIntermediate:
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            refresh()

        case .cancel:
            cancel()

        case .finish(let result):
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            finish(result)
        }
    }

    private func refresh() {
        guard let interaction = interaction else { return }

        for (idx, panel) in panels.enumerated() {
            let view = views[idx]
            let isActive = panel.frame.contains(interaction.virtualPointer)
            view.apply(interaction: interaction, isActiveDisplay: isActive)

            // Ensure key window moves as pointer moves across screens
            if isActive && !panel.isKeyWindow {
                panel.makeKeyAndOrderFront(nil)
                panel.makeFirstResponder(view)
            }
        }
    }

    private func hideCursorIfNeeded() {
        if !isCursorHidden {
            NSCursor.hide()
            isCursorHidden = true
        }
    }

    private func unhideCursorIfNeeded() {
        if isCursorHidden {
            NSCursor.unhide()
            isCursorHidden = false
        }
    }

    private func finish(_ result: ColorPickerResult?) {
        guard let cont = continuation else { return }
        continuation = nil
        onFormatChange = nil
        interaction = nil

        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
            self.screenChangeObserver = nil
        }

        unhideCursorIfNeeded()

        views.forEach { $0.releaseImage() }
        views.removeAll()

        for panel in panels {
            panel.orderOut(nil)
            panel.contentView = nil
            panel.close()
        }
        panels.removeAll()

        cont.resume(returning: result)
    }
}
