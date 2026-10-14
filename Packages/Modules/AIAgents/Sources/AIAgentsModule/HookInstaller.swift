import AgentHookKit
import Foundation

/// Registers the `mynotch-hook` helper with Claude Code and Codex. It works on the file URLs it is given and
/// only ever adds or removes groups whose command runs the helper, so other tools' hooks, and every
/// other key of the file, stay as they are. Every change to an existing file is preceded by a backup.
struct HookInstaller {
    enum InstallError: Error, Equatable {
        case notAJSONObject
        /// An event's hooks are not a list, so adding to them would replace what the user wrote.
        case hooksNotAnArray(event: String)
    }

    /// The Claude Code events whose hooks tell MyNotch what a session is doing.
    static let claudeEvents = ["UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Notification", "Stop", "StopFailure", "SessionEnd"]
    /// Codex has no notification or failure hooks.
    static let codexEvents = ["UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop", "SessionEnd"]
    /// Shown after installing for Codex: it does not run a hook it has not been told to trust.
    static let codexTrustNote = "Codex sẽ hỏi bạn tin cậy hook mới (xem lại trong Codex) trước khi chạy chúng."
    static let pluginName = "mynotch"
    static let marketplaceName = "mynotch-local"
    /// Shown with the plugin route: the app does not run the plugin commands, so it cannot undo them either.
    static let pluginUninstallCommand = "claude plugin uninstall \(pluginName)@\(marketplaceName)"
    /// A hook that has not answered by then is killed, so a stuck helper never holds up the agent.
    static let hookTimeoutSeconds = 5
    /// The permission hook waits for the user, up to `PermissionClient.defaultTimeout`. The agent gives it a little
    /// longer than that, so the helper always ends first and quietly, and the agent never reports a killed hook.
    static let permissionHookTimeoutSeconds = Int(PermissionClient.defaultTimeout) + 10
    /// What the Settings page and the confirmation say the permission hook does.
    static let permissionExplanation = "Khi Claude Code hoặc Codex xin quyền dùng một công cụ, hook PermissionRequest cho notch hiện thẻ "
        + "với nút Cho phép, Từ chối và Hỏi trong terminal, và chờ câu trả lời tối đa 60 giây. Hết giờ, không có MyNotch, "
        + "hay chọn Hỏi trong terminal thì agent tự hỏi trong terminal như thường. Nút Cho phép chỉ hiện khi thẻ cho thấy "
        + "đủ yêu cầu (cả lệnh, cả đường dẫn) mà không phải cuộn, và chỉ gồm ký tự ASCII thường; yêu cầu khác chỉ có Từ chối "
        + "(thẻ dưới notch gợi ý mở tab AI để đọc) hoặc Trả lời trong terminal."

    static func timeoutSeconds(for event: String) -> Int {
        event == PermissionWire.eventName ? permissionHookTimeoutSeconds : hookTimeoutSeconds
    }

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
        for event in Self.claudeEvents { events[event] = [Self.group(helperPath: helperPath, source: "claude", event: event)] }
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
            if let existing = hooks[event], !(existing is [Any]) { throw InstallError.hooksNotAnArray(event: event) }
            var groups = hooks[event] as? [Any] ?? []
            if groups.contains(where: { Self.commands(in: $0).contains { Self.runsHelper($0, helperPath: helperPath) } }) {
                if let line = Self.raiseTimeout(in: &groups, event: event, helperPath: helperPath) {
                    hooks[event] = groups
                    added.append(line)
                }
                continue
            }
            groups.append(Self.group(helperPath: helperPath, source: source, event: event))
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
                let others = entries.filter { entry in
                    let command = (entry as? [String: Any])?["command"] as? String ?? ""
                    return !Self.runsHelper(command, helperPath: helperPath)
                }
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

    /// A backup is never overwritten: a second change within the same second gets the next free `-1`, `-2`, …
    private func save(_ object: [String: Any], to url: URL, backingUp: Bool) throws {
        let fileManager = FileManager.default
        // Dotfiles are often links into a repository: the content is replaced, the link stays.
        let target = url.resolvingSymlinksInPath()
        if backingUp {
            let folder = url.deletingLastPathComponent()
            let base = "\(url.lastPathComponent).mynotch-\(backupStamp())"
            var backup = folder.appending(path: base + ".bak")
            var number = 0
            while fileManager.fileExists(atPath: backup.path) {
                number += 1
                backup = folder.appending(path: "\(base)-\(number).bak")
            }
            try fileManager.copyItem(at: target, to: backup)
        }
        try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let permissions = (try? fileManager.attributesOfItem(atPath: target.path))?[.posixPermissions]
        try Self.write(object, to: target)
        if let permissions { try? fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path) }
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

    private static func group(helperPath: String, source: String, event: String) -> [String: Any] {
        ["hooks": [["type": "command", "command": command(helperPath: helperPath, source: source), "timeout": timeoutSeconds(for: event)]]]
    }

    /// An install made before the permission hook existed gave it the 5 seconds of the others, which would end the wait
    /// for the user long before the helper does. Raises the timeout of our own entry only, and only a shorter one: a longer
    /// timeout is the user's. Returns the line for the summary, nil when nothing was changed.
    private static func raiseTimeout(in groups: inout [Any], event: String, helperPath: String) -> String? {
        guard event == PermissionWire.eventName else { return nil }
        let wanted = timeoutSeconds(for: event)
        var previous: Int?
        for index in groups.indices {
            guard var group = groups[index] as? [String: Any], var entries = group["hooks"] as? [Any] else { continue }
            var changed = false
            for position in entries.indices {
                guard var entry = entries[position] as? [String: Any], let command = entry["command"] as? String,
                      runsHelper(command, helperPath: helperPath), let current = entry["timeout"] as? Int, current < wanted
                else { continue }
                entry["timeout"] = wanted
                entries[position] = entry
                previous = previous ?? current
                changed = true
            }
            if changed {
                group["hooks"] = entries
                groups[index] = group
            }
        }
        return previous.map { "\(event): ~ timeout \($0) → \(wanted) s" }
    }

    /// Runs the helper only while it is there: a moved or trashed app would otherwise make the shell exit 127, which
    /// the agent reports as a hook error on every event. The helper itself always exits 0.
    static func command(helperPath: String, source: String) -> String {
        "P=\(shellQuoted(helperPath)); [ -x \"$P\" ] && exec \"$P\" --source \(source); exit 0"
    }

    /// The command starts with the quoted helper path, so a longer path that starts the same is not ours. The
    /// bare `'<path>' --source …` form of the first version is still ours, so it can be removed.
    private static func runsHelper(_ command: String, helperPath: String) -> Bool {
        let quoted = shellQuoted(helperPath)
        return command.hasPrefix("P=" + quoted + "; ") || command == quoted || command.hasPrefix(quoted + " ")
    }

    private static func commands(in group: Any) -> [String] {
        ((group as? [String: Any])?["hooks"] as? [Any])?.compactMap { ($0 as? [String: Any])?["command"] as? String } ?? []
    }

    /// Hooks run through a shell and the helper lives under "Application Support", so the path needs quoting.
    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
