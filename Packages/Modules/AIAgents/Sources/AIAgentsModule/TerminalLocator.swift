import Foundation

/// The app an agent's terminal belongs to, and which of its terminals the agent is in.
nonisolated struct TerminalTarget: Equatable, Sendable {
    nonisolated enum Kind: Equatable, Sendable {
        /// Terminal.app: its tabs can be told apart by tty.
        case terminal
        /// iTerm2: its sessions can be told apart by tty.
        case iTerm
        /// VS Code and its relatives: the folder is opened in the editor.
        case editor
        /// Anything else (Ghostty, Warp, kitty, …): only brought to the front.
        case other
    }

    /// The `.app` folder.
    var app: URL
    var kind: Kind
    /// `/dev/ttys003`, when the agent has a terminal of its own.
    var tty: String?
}

/// Finds the terminal app of a process by walking up its parents, which stay as they are however the agent was started:
/// the shell, `login` and the terminal's helper processes lead up to the app.
nonisolated enum TerminalLocator {
    /// Shells nest a few deep, not dozens: a longer chain, or a loop, is not a terminal.
    static let maxDepth = 32

    static func locate(pid: pid_t, table: any ProcessTable, bundleIdentifier: (URL) -> String?) -> TerminalTarget? {
        var tty: String?
        var current = pid
        var seen: Set<pid_t> = []
        while current > 1, seen.count < maxDepth, seen.insert(current).inserted, let entry = table.entry(pid: current) {
            if tty == nil { tty = entry.tty.flatMap(device(named:)) }
            if let app = appBundle(containing: entry.executablePath) {
                return TerminalTarget(app: app, kind: kind(of: bundleIdentifier(app)), tty: tty)
            }
            current = entry.parentPID
        }
        return nil
    }

    /// The outermost `.app` folder of a path: an editor's terminal runs in a helper app inside the editor's own.
    static func appBundle(containing path: String?) -> URL? {
        guard let path, path.hasPrefix("/") else { return nil }
        var parts: [Substring] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            parts.append(part)
            if part.hasSuffix(".app"), part.count > 4 { return URL(filePath: "/" + parts.joined(separator: "/"), directoryHint: .isDirectory) }
        }
        return nil
    }

    private static let editors: Set<String> = [
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92", "com.vscodium",
    ]

    static func kind(of bundleIdentifier: String?) -> TerminalTarget.Kind {
        switch bundleIdentifier {
        case "com.apple.Terminal": .terminal
        case "com.googlecode.iterm2": .iTerm
        case let id? where editors.contains(id): .editor
        default: .other
        }
    }

    /// `/dev/ttys003` for `ttys003`; nil for anything that is not a plain device name, since it is put in a script.
    private static func device(named name: String) -> String? {
        let path = "/dev/" + name
        return TerminalScript.isDevicePath(path) ? path : nil
    }
}
