import Foundation
@testable import ClipboardModule

/// In-memory pasteboard that counts content reads, so tests can prove the monitor reads only when it must.
final class FakePasteboard: PasteboardAccess {
    struct Write: Equatable {
        let content: ClipboardContent
        let imageURL: URL?
        /// The picture's bytes when they came from memory and not from a file.
        var imageData: Data? = nil
        let plainTextOnly: Bool
        let sourceBundleID: String?
    }

    private(set) var changeCount = 0
    private(set) var snapshotCount = 0
    private(set) var writes: [Write] = []
    /// False makes every write fail, like an image file that is gone.
    var writesSucceed = true
    private var current: PasteboardSnapshot?

    /// Another app copying: new content under a new change count.
    func copy(_ snapshot: PasteboardSnapshot) {
        current = snapshot
        changeCount += 1
    }

    func snapshot() -> PasteboardSnapshot? {
        snapshotCount += 1
        return current
    }

    func write(_ content: ClipboardContent, imageURL: URL?, imageData: Data?, plainTextOnly: Bool, sourceBundleID: String?) -> Bool {
        guard writesSucceed else { return false }
        writes.append(Write(content: content, imageURL: imageURL, imageData: imageData, plainTextOnly: plainTextOnly, sourceBundleID: sourceBundleID))
        copy(PasteboardSnapshot(types: [ClipboardClassifier.ownWriteType, "public.utf8-plain-text"], string: content.plainText))
        return true
    }
}

/// Counts ⌘V instead of posting it; the real sender must never run in tests.
final class FakeKeystrokeSender: KeystrokeSending {
    private(set) var pasteCount = 0

    func sendPaste() {
        pasteCount += 1
    }
}

/// The modifier keys as a test sets them, so no test reads the real keyboard.
final class FakeModifierState: ModifierState {
    /// Whether the user is holding ⌃, ⌥, ⌘ or ⇧.
    var held = false
    private(set) var readCount = 0

    var isAnyHeld: Bool {
        readCount += 1
        return held
    }
}
