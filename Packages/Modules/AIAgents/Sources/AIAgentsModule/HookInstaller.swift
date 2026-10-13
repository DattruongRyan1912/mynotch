import Foundation

/// Registers the `mynotch-hook` helper with Claude Code and Codex. It works on the file URLs it is given and
/// only ever adds or removes groups whose command contains the helper's path, so other tools' hooks, and every
/// other key of the file, stay as they are. Every change to an existing file is preceded by a backup.
struct HookInstaller {
    enum InstallError: Error, Equatable {
        case notAJSONObject
    }

    /// The Claude Code events whose hooks tell MyNotch what a session is doing.
    static let claudeEvents = ["UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Notification", "Stop", "StopFailure", "SessionEnd"]
    /// Codex has no notification, failure or session-end hooks.
    static let codexEvents = ["UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop"]
    static let pluginName = "mynotch"
    static let marketplaceName = "mynotch-local"

    var now: () -> Date = { Date() }
    var calendar: Calendar = .autoupdatingCurrent

    // MARK: Claude plugin

    /// Writes a plugin and a one-plugin marketplace into `directory`. Returns the two commands the user runs to
    /// add and install it; the app does not run them.
    func claudePlugin(at directory: URL, helperPath: String) throws -> [String] {
        let fileManager = FileManager.default
        let metadata = directory.appending(path: ".claude-plugin", directoryHint: .isDirectory)
        let hooks = directory.appending(path: "hooks", directoryHint: .isDirectory)
        for folder in [metadata, hooks] { try fileManager.createDirectory(at: folder, withIntermediateDirectories: true) }
        let description = "Shows what Claude Code is doing in the MyNotch notch."
        try Self.write(["name": Self.pluginName, "version": "1.0.0", "description": description], to: metadata.appending(path: "plugin.json"))
        try Self.write([
            "name": Self.marketplaceName,
            "owner": ["name": "MyNotch"],
            "plugins": [["name": Self.pluginName, "source": "./", "description": description]],
        ], to: metadata.appending(path: "marketplace.json"))
        var events: [String: Any] = [:]
        for event in Self.claudeEvents { events[event] = [Self.group(helperPath: helperPath, source: "claude")] }
        try Self.write(["hooks": events], to: hooks.appending(path: "hooks.json"))
        return [
            "claude plugin marketplace add \(Self.shellQuoted(directory.path))",
            "claude plugin install \(Self.pluginName)@\(Self.marketplaceName)",
        ]
    }

    // MARK: Settings and hook files

    /// Returns what was added, one line per event; empty when the helper was already registered.
    func mergeClaudeSettings(settingsURL: URL, helperPath: String) throws -> [String] {
        try merge(fileURL: settingsURL, helperPath: helperPath, source: "claude", events: Self.claudeEvents)
    }

    /// Returns what was removed, one line per event.
    func removeClaude(settingsURL: URL, helperPath: String) throws -> [String] {
        try remove(fileURL: settingsURL, helperPath: helperPath)
    }

    func mergeCodexHooks(hooksURL: URL, helperPath: String) throws -> [String] {
        try merge(fileURL: hooksURL, helperPath: helperPath, source: "codex", events: Self.codexEvents)
    }

    func removeCodex(hooksURL: URL, helperPath: String) throws -> [String] {
        try remove(fileURL: hooksURL, helperPath: helperPath)
    }

    private func merge(fileURL: URL, helperPath: String, source: String, events: [String]) throws -> [String] {
        let original = try Self.read(fileURL)
        var root = original ?? [:]
        guard root["hooks"] == nil || root["hooks"] is [String: Any] else { throw InstallError.notAJSONObject }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var added: [String] = []
        for event in events {
            var groups = hooks[event] as? [Any] ?? []
            guard !groups.contains(where: { Self.commands(in: $0).contains { $0.contains(helperPath) } }) else { continue }
            groups.append(Self.group(helperPath: helperPath, source: source))
            hooks[event] = groups
            added.append("\(event): + \(Self.command(helperPath: helperPath, source: source))")
        }
        guard !added.isEmpty else { return [] }
        root["hooks"] = hooks
        try save(root, to: fileURL, backingUp: original != nil)
        return added
    }

    private func remove(fileURL: URL, helperPath: String) throws -> [String] {
        guard var root = try Self.read(fileURL), var hooks = root["hooks"] as? [String: Any] else { return [] }
        var removed: [String] = []
        for (event, value) in hooks {
            guard let groups = value as? [Any] else { continue }
            var kept: [Any] = []
            var count = 0
            for group in groups {
                guard var object = group as? [String: Any], let entries = object["hooks"] as? [Any] else {
                    kept.append(group)
                    continue
                }
                let others = entries.filter { !((($0 as? [String: Any])?["command"] as? String)?.contains(helperPath) ?? false) }
                count += entries.count - others.count
                // A group left with nothing in it would be a dangling matcher.
                if others.count == entries.count {
                    kept.append(group)
                } else if !others.isEmpty {
                    object["hooks"] = others
                    kept.append(object)
                }
            }
            guard count > 0 else { continue }
            hooks[event] = kept.isEmpty ? nil : kept
            removed.append("\(event): - \(count) hook(s)")
        }
        guard !removed.isEmpty else { return [] }
        root["hooks"] = hooks.isEmpty ? nil : hooks
        try save(root, to: fileURL, backingUp: true)
        return removed.sorted()
    }

    // MARK: Files

    /// Nil when the file does not exist.
    private static func read(_ url: URL) throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let object = (try JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [String: Any] else { throw InstallError.notAJSONObject }
        return object
    }

    private func save(_ object: [String: Any], to url: URL, backingUp: Bool) throws {
        let fileManager = FileManager.default
        if backingUp {
            let backup = url.deletingLastPathComponent().appending(path: "\(url.lastPathComponent).mynotch-\(backupStamp()).bak")
            try? fileManager.removeItem(at: backup)
            try fileManager.copyItem(at: url, to: backup)
        }
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.write(object, to: url)
    }

    private func backupStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: now())
    }

    /// Atomic, so an editor or a running agent never sees half a file.
    private static func write(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }

    // MARK: Hook entries

    private static func group(helperPath: String, source: String) -> [String: Any] {
        ["hooks": [["type": "command", "command": command(helperPath: helperPath, source: source)]]]
    }

    private static func command(helperPath: String, source: String) -> String {
        "\(shellQuoted(helperPath)) --source \(source)"
    }

    private static func commands(in group: Any) -> [String] {
        ((group as? [String: Any])?["hooks"] as? [Any])?.compactMap { ($0 as? [String: Any])?["command"] as? String } ?? []
    }

    /// Hooks run through a shell and the helper lives under "Application Support", so the path needs quoting.
    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
