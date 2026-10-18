import AppKit
import SwiftUI

/// What the module needs of the editor's windows: to open one and to close them all. A protocol so tests open no window.
protocol RecordingEditorHosting: AnyObject {
    /// Shows the editor of the recording in `folder`, or brings its window forward if it is open. Throws when the recording
    /// cannot be opened: still being recorded, or its project cannot be read.
    func open(folder: URL) throws(RecordingEditorError)
    func closeAll()
}

/// What the answer to "close while exporting?" is.
nonisolated enum RecordingEditorClosing {
    enum Choice: Equatable, Sendable {
        case keepExporting
        /// Stops the export, which leaves no file, and closes.
        case cancelAndClose
    }

    /// The alert's buttons: the first is the default (Return), the last is the way out (Esc).
    static let alertButtons = ["Tiếp tục xuất", "Huỷ xuất và đóng"]

    /// Anything but the second button keeps exporting, so a sheet dismissed some other way cannot lose the export.
    static func choice(for response: NSApplication.ModalResponse) -> Choice {
        response == .alertSecondButtonReturn ? .cancelAndClose : .keepExporting
    }
}

/// Hosts the recording editor in regular titled windows, one per recording. Edits are saved as they are made, so closing asks
/// nothing, except while an export runs: closing then cancels it. Like the markup editor's windows, while one is open the app is a
/// regular one, because an accessory app's window cannot take typing.
final class RecordingEditorWindowController: NSObject, RecordingEditorHosting {
    /// One open editor.
    final class Session {
        let folder: URL
        let model: RecordingEditorModel
        let player: RecordingPlayer
        var window: NSWindow?
        var startTask: Task<Void, Never>?
        var closesWithoutAsking = false

        init(folder: URL, model: RecordingEditorModel, player: RecordingPlayer) {
            self.folder = folder
            self.model = model
            self.player = player
        }
    }

    private let pasteboard: any PasteboardWriting
    private let exportDirectory: URL
    private let reveal: (URL) -> Void
    private var sessions: [URL: Session] = [:]

    /// `exportDirectory` is where exports go: `~/Movies/MyNotch` unless a test says otherwise.
    init(
        pasteboard: any PasteboardWriting, exportDirectory: URL = RecordingExporter.defaultDirectory,
        reveal: @escaping (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
    ) {
        self.pasteboard = pasteboard
        self.exportDirectory = exportDirectory
        self.reveal = reveal
    }

    func open(folder: URL) throws(RecordingEditorError) {
        let key = folder.standardizedFileURL
        if let window = sessions[key]?.window {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let session = try makeSession(folder: key)
        let view = RecordingEditorView(model: session.model, player: session.player)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Sửa bản quay"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 980, height: 760))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        session.window = window
        // Switch the policy first, so the app comes forward as a regular app with its menu bar.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// The editor of the recording in `folder`, registered with its model and no window yet, and its preview on its way: the
    /// first thing `open` does, split out so the rest can be tested without a window.
    func makeSession(folder: URL) throws(RecordingEditorError) -> Session {
        let player = RecordingPlayer()
        let model = try RecordingEditorModel.load(folder: folder, player: player, pasteboard: pasteboard, exportDirectory: exportDirectory, reveal: reveal)
        let session = Session(folder: folder, model: model, player: player)
        sessions[folder] = session
        session.startTask = Task { await model.start() }
        return session
    }

    /// What the alert's answer does for the editor of `folder`.
    func answerClose(_ choice: RecordingEditorClosing.Choice, for folder: URL) {
        guard let session = sessions[folder], choice == .cancelAndClose else { return }
        session.closesWithoutAsking = true
        session.window?.close()
    }

    /// Closes every editor without asking, e.g. when the module stops. An export under way is cancelled.
    func closeAll() {
        for session in Array(sessions.values) {
            session.closesWithoutAsking = true
            session.window?.close()
            // A session that never got a window is dropped by hand.
            if session.window == nil { end(session) }
        }
    }

    var openFolders: [URL] { Array(sessions.keys) }

    private func end(_ session: Session) {
        session.model.cancelExport()
        session.startTask?.cancel()
        session.player.pause()
        sessions[session.folder] = nil
    }

    private func session(of window: NSWindow) -> Session? {
        sessions.values.first { $0.window === window }
    }
}

extension RecordingEditorWindowController: NSWindowDelegate {
    /// Asks before closing on an export that is running.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender.attachedSheet == nil else { return false }
        guard let session = session(of: sender), session.model.isExporting, !session.closesWithoutAsking else { return true }
        let alert = NSAlert()
        alert.messageText = "Đang xuất video"
        alert.informativeText = "Nếu đóng cửa sổ này, việc xuất sẽ bị huỷ và không có file nào được tạo."
        let buttons = RecordingEditorClosing.alertButtons.map { alert.addButton(withTitle: $0) }
        buttons[1].hasDestructiveAction = true
        buttons[1].keyEquivalent = "\u{1b}"
        let folder = session.folder
        alert.beginSheetModal(for: sender) { [weak self] response in
            self?.answerClose(RecordingEditorClosing.choice(for: response), for: folder)
        }
        return false
    }

    /// Back to a menu bar app, unless Settings or another titled window is still open.
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, let session = session(of: window) else { return }
        end(session)
        // Dropping the content frees the player and the strip's pictures at once.
        window.contentViewController = nil
        NSApp.setActivationPolicy(EditorActivation.policyAfterClosing(window))
    }
}
