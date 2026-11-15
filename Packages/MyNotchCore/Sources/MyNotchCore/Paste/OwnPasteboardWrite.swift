import AppKit

/// The marker MyNotch adds to everything it writes to the pasteboard, so that its own clipboard history, and other clipboard
/// managers that know the type, skip the write instead of recording it as something the user copied.
public nonisolated enum OwnPasteboardWrite {
    /// The type's identifier. It is a contract with the history already on disk and with other clipboard managers: it must
    /// never change.
    public static let typeIdentifier = "io.lucasvu.mynotch.clipboard"

    public static var pasteboardType: NSPasteboard.PasteboardType { NSPasteboard.PasteboardType(typeIdentifier) }
}
