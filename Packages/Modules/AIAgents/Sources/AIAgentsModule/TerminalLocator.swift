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
        /// Anything else (Ghostty, Warp, WezTerm, kitty, …): only brought to the front.
        case other
    }

    /// The `.app` folder.
    var app: URL
    var kind: Kind
    /// `/dev/ttys003`, when the agent has a terminal of its own.
    var tty: String?
}

/// Finds the terminal app of a process by walking up its parents: the shell, `login` and the terminal's helper processes
/// lead up to the app. Only an app that is running counts, so a command-line tool that lives inside an `.app` folder (the
/// `claude` the desktop app downloads is one) does not stand in for the terminal above it.
nonisolated struct TerminalLocator {
    /// What the walk found: the app, if the chain led to one, and the agent's tty, if it has one. A chain that ends without an
    /// app (tmux, a terminal that runs its jobs in a daemon) still says which tty to ask the terminals about.
    nonisolated struct Found: Equatable, Sendable {
        var target: TerminalTarget?
        var tty: String?
    }

    /// Shells nest a few deep, not dozens: a longer chain, or a loop, is not a terminal.
    static let maxDepth = 32
    static let terminalBundleID = "com.apple.Terminal"
    static let iTermBundleID = "com.googlecode.iterm2"

    var table: any ProcessTable
    var bundleIdentifier: (URL) -> String?
    /// Whether the app at this URL is a running app: one that is registered as such, which a tool inside a bundle is not.
    var isRunning: (URL) -> Bool
    /// The running app with this bundle identifier.
    var runningApp: (String) -> URL?

    func find(pid: pid_t) -> Found {
        var tty: String?
        var current = pid
        var seen: Set<pid_t> = []
        while current > 1, seen.count < Self.maxDepth, seen.insert(current).inserted, let entry = table.entry(pid: current) {
            if tty == nil { tty = entry.tty.flatMap(Self.device(named:)) }
            if let app = terminalApp(of: entry) { return Found(target: TerminalTarget(app: app.url, kind: app.kind, tty: tty), tty: tty) }
            current = entry.parentPID
        }
        return Found(target: nil, tty: tty)
    }

    private func terminalApp(of entry: ProcessEntry) -> (url: URL, kind: TerminalTarget.Kind)? {
        // iTerm2 runs the jobs of its sessions in `iTermServer` processes that it copies to its own folder in Application
        // Support, outside the app and outliving it, so the path of one says "iTerm2" and the app is looked up by name.
        if Self.isITermServer(entry.executablePath) {
            return runningApp(Self.iTermBundleID).map { ($0, .iTerm) }
        }
        guard let app = Self.appBundle(containing: entry.executablePath), isRunning(app) else { return nil }
        return (app, Self.kind(of: bundleIdentifier(app)))
    }

    /// True for `iTermServer` and `iTermServer-3.5.0`, wherever it lives.
    static func isITermServer(_ path: String?) -> Bool {
        guard let path, let name = path.split(separator: "/").last else { return false }
        return name.hasPrefix("iTermServer")
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
        case terminalBundleID: .terminal
        case iTermBundleID: .iTerm
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
