import AppKit
import SwiftUI

/// Hosts the markup editor in regular titled windows, one per capture. The decisions live in `ScreenshotModule`
/// (what is saved, where) and `EditorActivation` (the app's activation policy); this class creates windows, builds
/// each editor's model once and forwards what the buttons ask for. While an editor is open the app is a regular
/// one, because an accessory app's window cannot take typing.
final class MarkupEditorWindowController: NSObject {
    /// One open editor.
    private final class Session {
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
            model = MarkupEditorModel(image: source.image, document: source.document)
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
        let session = Session(record: record, source: source)
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
        window.setContentSize(NSSize(width: 960, height: 640))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        session.window = window
        sessions[id] = session
        // Switch the policy first, so the app comes forward as a regular app with its menu bar.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Closes every editor without asking, e.g. when the module stops.
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
            // Edits made while the save ran are not in the file: keep the window so they are not lost.
            guard session.model.finishedDocument() == document else { return }
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
        guard let session = session(of: sender), EditorClosing.needsConfirmation(
            current: session.model.finishedDocument(), saved: session.savedDocument,
            closesWithoutAsking: session.closesWithoutAsking
        ) else { return true }
        let alert = NSAlert()
        alert.messageText = "Bỏ các thay đổi chưa lưu?"
        alert.informativeText = "Các chú thích vừa thêm sẽ mất nếu đóng cửa sổ này."
        alert.addButton(withTitle: "Tiếp tục sửa")
        alert.addButton(withTitle: "Bỏ thay đổi")
        alert.beginSheetModal(for: sender) { response in
            guard response == .alertSecondButtonReturn else { return }
            session.closesWithoutAsking = true
            sender.close()
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
