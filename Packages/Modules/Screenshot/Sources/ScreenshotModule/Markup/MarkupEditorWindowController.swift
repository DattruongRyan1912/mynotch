import AppKit
import SwiftUI

/// Hosts the markup editor in regular titled windows, one per capture. The decisions live in `ScreenshotModule`
/// (what is saved, where) and `EditorActivation` (the app's activation policy); this class creates windows, builds
/// each editor's model once and forwards what the buttons ask for. While an editor is open the app is a regular
/// one, because an accessory app's window cannot take typing.
final class MarkupEditorWindowController: NSObject {
    /// One open editor.
    final class Session {
        let record: CaptureRecord
        let source: MarkupEditorSource
        let model: MarkupEditorModel
        var window: NSWindow?
        /// What was last saved, or the document the editor opened with: Huỷ and the close button ask when the
        /// editor differs from it.
        var savedDocument: MarkupDocument
        var isSaving = false
        var closesWithoutAsking = false

        init(record: CaptureRecord, source: MarkupEditorSource) {
            self.record = record
            self.source = source
            model = MarkupEditorModel(image: source.image, document: source.document, pointScale: source.scale, canvasFill: source.canvasFill)
            savedDocument = model.document
        }
    }

    private weak var module: ScreenshotModule?
    private var sessions: [UUID: Session] = [:]

    init(module: ScreenshotModule) {
        self.module = module
    }

    /// Shows the editor of `record`, or brings its window forward if it is already open.
    func open(_ record: CaptureRecord, source: MarkupEditorSource) {
        if let window = sessions[record.id]?.window {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let session = makeSession(record, source: source)
        let id = record.id
        let view = MarkupEditorView(
            model: session.model,
            onSave: { [weak self] in self?.save(id, $0) },
            onCopy: { [weak self] in self?.copy(id, $0) },
            onCancel: { [weak self] _ in self?.sessions[id]?.window?.performClose(nil) }
        )
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Sửa ảnh chụp"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1040, height: 680))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        session.window = window
        // Switch the policy first, so the app comes forward as a regular app with its menu bar.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// The editor of `record`, registered with its model and no window yet: the first thing `open` does, split out so the
    /// answers of the close alert can be tested without a window.
    func makeSession(_ record: CaptureRecord, source: MarkupEditorSource) -> Session {
        let session = Session(record: record, source: source)
        sessions[record.id] = session
        return session
    }

    /// What the close alert's button does for the editor of `id`. Lưu is the Lưu button: it saves, copies when Settings
    /// says so, and closes the window once the save is done; a save that fails leaves the editor open.
    func answerClose(_ choice: EditorClosing.Choice, for id: UUID) {
        guard let session = sessions[id] else { return }
        switch choice {
        case .save:
            save(id, session.model.finishedDocument())
        case .discard:
            session.closesWithoutAsking = true
            session.window?.close()
        case .keepEditing:
            break
        }
    }

    /// Closes every editor without asking, e.g. when the module stops. Annotations not saved by then are lost: there
    /// is no moment left to ask, and for this personal app that is accepted.
    func closeAll() {
        for session in Array(sessions.values) {
            session.closesWithoutAsking = true
            session.window?.close()
        }
    }

    private func save(_ id: UUID, _ document: MarkupDocument) {
        guard let session = sessions[id], let module, !session.isSaving else { return }
        session.isSaving = true
        Task {
            let saved = await module.saveMarkup(document, of: session.source, for: session.record)
            session.isSaving = false
            guard saved else { return }
            session.savedDocument = document
            guard EditorClosing.shouldCloseAfterSave(saved: document, current: session.model.finishedDocument()) else { return }
            session.closesWithoutAsking = true
            session.window?.close()
        }
    }

    private func copy(_ id: UUID, _ document: MarkupDocument) {
        guard let session = sessions[id], let module else { return }
        Task { _ = await module.copyMarkup(document, of: session.source) }
    }

    private func session(of window: NSWindow) -> Session? {
        sessions.values.first { $0.window === window }
    }
}

extension MarkupEditorWindowController: NSWindowDelegate {
    /// Asks before throwing away annotations that were not saved.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender.attachedSheet == nil else { return false }
        guard let session = session(of: sender) else { return true }
        // A save that succeeds closes the window itself; asking now would be about work that is being saved.
        guard !session.isSaving else { return false }
        guard EditorClosing.needsConfirmation(
            current: session.model.finishedDocument(), saved: session.savedDocument,
            closesWithoutAsking: session.closesWithoutAsking
        ) else { return true }
        let alert = NSAlert()
        alert.messageText = "Lưu các thay đổi chưa lưu?"
        alert.informativeText = "Nếu không lưu, những gì vừa sửa sẽ mất khi đóng cửa sổ này."
        let buttons = EditorClosing.alertButtons.map { alert.addButton(withTitle: $0) }
        buttons[1].hasDestructiveAction = true
        // The last button is the way out: Esc keeps editing.
        buttons[2].keyEquivalent = "\u{1b}"
        let id = session.record.id
        alert.beginSheetModal(for: sender) { [weak self] response in
            self?.answerClose(EditorClosing.choice(for: response), for: id)
        }
        return false
    }

    /// Back to a menu bar app, unless Settings or another titled window is still open.
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, let session = session(of: window) else { return }
        sessions[session.record.id] = nil
        // Dropping the content frees the capture's pixels at once.
        window.contentViewController = nil
        NSApp.setActivationPolicy(EditorActivation.policyAfterClosing(window))
    }
}
