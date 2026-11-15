import AppKit
import Foundation

/// What clicking a session and its context menu do to the machine. Behind closures so tests never open
/// Terminal or touch the pasteboard.
struct AgentOpener {
    var openInTerminal: (URL) -> Void
    var openFolder: (URL) -> Void
    var copy: (String) -> Void

    private static let terminalBundleID = "com.apple.Terminal"

    static let system = AgentOpener(
        openInTerminal: { folder in
            let workspace = NSWorkspace.shared
            guard let terminal = workspace.urlForApplication(withBundleIdentifier: terminalBundleID) else {
                workspace.open(folder)
                return
            }
            workspace.open([folder], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
        },
        openFolder: { NSWorkspace.shared.open($0) },
        copy: { text in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
    )

    /// The folder a session works in, if it is a folder that exists. The path comes from a transcript and Terminal
    /// runs a file it is asked to open, so a path that names a file, or anything but an absolute path, is refused.
    static func directory(for cwd: String?) -> URL? {
        guard let cwd, cwd.hasPrefix("/") else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: cwd, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        return URL(filePath: cwd, directoryHint: .isDirectory)
    }
}
