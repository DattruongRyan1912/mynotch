import AppKit

/// What `SelectionReplacer.replace` did.
enum ReplaceOutcome: Equatable {
    /// Accessibility wrote the text over the selection.
    case replaced
    /// The app would not take it that way, so it was pasted with ⌘V.
    case pasted
    case needsAccessibility
    /// What is selected in the other app is no longer the text that was translated, so nothing was changed.
    case selectionChanged
    case failed
}

/// Puts a translation in place of the text it came from, in the app that text was selected in.
final class SelectionReplacer {
    /// Added to everything MyNotch puts on the pasteboard, so the Clipboard module's history skips it. The same string
    /// as `ClipboardClassifier.ownWriteType`, which lives in another package.
    static let ownWriteType = NSPasteboard.PasteboardType("io.lucasvu.mynotch.clipboard")

    /// The app needs a moment to come to the front after `activate`.
    private static let frontPause = Duration.milliseconds(50)
    private static let frontChecks = 10
    /// The app reads the pasteboard some time after ⌘V; the user's clipboard goes back only after this.
    private static let restoreDelay = Duration.milliseconds(500)

    private let accessibility: any AccessibilityClient
    private let applications: any ApplicationActivating
    private let keystroke: any PasteKeystroke
    private let pasteboard: NSPasteboard
    private let pause: @MainActor (Duration) async throws -> Void

    init(
        accessibility: any AccessibilityClient = SystemAccessibilityClient(),
        applications: any ApplicationActivating = SystemApplicationActivator(),
        keystroke: any PasteKeystroke = CGEventPasteKeystroke(),
        pasteboard: NSPasteboard,
        pause: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.accessibility = accessibility
        self.applications = applications
        self.keystroke = keystroke
        self.pasteboard = pasteboard
        self.pause = pause
    }

    /// Whether MyNotch may write to other apps. Checking never prompts.
    var isTrusted: Bool { accessibility.isTrusted }

    /// Replaces `selected`, which is still selected in `application`, with `text`: through Accessibility if the app
    /// takes it, else by pasting. Cancelling before the app is in front changes nothing.
    func replace(_ text: String, expecting selected: String, in application: FocusedApplication) async -> ReplaceOutcome {
        guard accessibility.isTrusted else { return .needsAccessibility }
        // The user may have selected something else since, and that is not theirs to lose. Checked before the app is
        // brought to the front, so a replacement that will not happen does not take the focus either.
        switch accessibility.readSelection(in: application) {
        case .text(let current) where current == selected: break
        case .unresponsive: break   // cannot be told; the app may still answer the replacement
        case .text, .empty: return .selectionChanged
        }
        guard await bringToFront(application), !Task.isCancelled else { return .failed }
        if accessibility.replaceSelection(with: text, in: application) { return .replaced }
        return await paste(text)
    }

    private func bringToFront(_ application: FocusedApplication) async -> Bool {
        guard applications.activate(application) else { return false }
        for _ in 0..<Self.frontChecks {
            if applications.isFrontmost(application) { return true }
            do {
                try await pause(Self.frontPause)
            } catch {
                return false   // cancelled
            }
        }
        return applications.isFrontmost(application)
    }

    /// ⌘V with the translation on the pasteboard, which goes back to what it held.
    private func paste(_ text: String) async -> ReplaceOutcome {
        let backup = PasteboardBackup(pasteboard)
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: Self.ownWriteType)
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            backup.restore(to: pasteboard, marking: Self.ownWriteType)
            return .failed
        }
        let written = pasteboard.changeCount
        keystroke.send()
        // Restoring before the app has read the pasteboard would paste the old clipboard, so a cancel (the module
        // stopping) must not shorten this wait: it runs in a task of its own, which does not inherit the cancellation.
        let pause = pause
        await Task { try? await pause(Self.restoreDelay) }.value
        // Whatever was copied meanwhile is newer than the backup.
        if pasteboard.changeCount == written { backup.restore(to: pasteboard, marking: Self.ownWriteType) }
        return .pasted
    }
}
