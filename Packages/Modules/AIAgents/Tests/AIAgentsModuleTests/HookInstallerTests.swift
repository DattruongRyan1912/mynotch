import AgentHookKit
import Foundation
import Testing
@testable import AIAgentsModule

/// Works on synthetic files in a temporary directory; the real `~/.claude` and `~/.codex` are never touched.
@Suite struct HookInstallerTests {
    let directory: URL
    let helper = "/Users/example/Library/Application Support/io.lucasvu.mynotch/bin/mynotch-hook"
    let installer = HookInstaller(now: { utc("2026-10-14T05:07:09Z") }, calendar: hoChiMinhCalendar())

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "HookInstallerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: directory) }

    func write(_ json: String, to name: String) throws -> URL {
        let url = directory.appending(path: name)
        try Data(json.utf8).write(to: url)
        return url
    }

    func object(at url: URL) throws -> NSDictionary {
        try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? NSDictionary)
    }

    func groups(_ root: NSDictionary, _ event: String) -> [NSDictionary] {
        ((root["hooks"] as? NSDictionary)?[event] as? [NSDictionary]) ?? []
    }

    func commands(_ group: NSDictionary) -> [String] {
        (group["hooks"] as? [NSDictionary])?.compactMap { $0["command"] as? String } ?? []
    }

    func firstHook(_ group: NSDictionary) -> NSDictionary? {
        (group["hooks"] as? [NSDictionary])?.first
    }

    /// Runs a hook command as the agents do, through a shell.
    func run(_ command: String) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }

    func ours(_ root: NSDictionary, _ event: String) -> [NSDictionary] {
        groups(root, event).filter { commands($0).contains { $0.contains(helper) } }
    }

    let claudeSettings = """
    {
      "statusLine": {"type": "command", "command": "bunx some-statusline"},
      "permissions": {"allow": ["Bash(ls:*)"]},
      "hooks": {
        "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "/opt/other/rtk hook"}]}],
        "Stop": [{"hooks": [{"type": "command", "command": "/opt/orca/notify stop"}]}],
        "SessionStart": [{"hooks": [{"type": "command", "command": "/opt/orca/start"}]}]
      }
    }
    """

    // MARK: Claude settings

    @Test func mergingAddsOneGroupPerEventBesideTheOthersAndBacksUp() throws {
        defer { cleanUp() }
        let url = try write(claudeSettings, to: "settings.json")
        let original = try object(at: url)
        let summary = try installer.mergeClaudeSettings(settingsURL: url, helperPath: helper)

        let merged = try object(at: url)
        for event in ["UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Notification", "Stop", "StopFailure", "SessionEnd"] {
            #expect(ours(merged, event).count == 1, "\(event)")
            #expect(commands(ours(merged, event)[0]) == [HookInstaller.command(helperPath: helper, source: "claude")], "\(event)")
            #expect(firstHook(ours(merged, event)[0])?["timeout"] as? Int == HookInstaller.timeoutSeconds(for: event), "\(event)")
        }
        #expect(groups(merged, "PreToolUse").count == 2)
        #expect(groups(merged, "Stop").count == 2)
        #expect(groups(merged, "SessionStart") == (original["hooks"] as? NSDictionary)?["SessionStart"] as? [NSDictionary])
        #expect(merged["statusLine"] as? NSDictionary == original["statusLine"] as? NSDictionary)
        #expect(merged["permissions"] as? NSDictionary == original["permissions"] as? NSDictionary)
        #expect(summary.count == 8)

        let backup = directory.appending(path: "settings.json.mynotch-20261014-120709.bak")
        #expect(try object(at: backup) == original)
    }

    @Test func mergingTwiceAddsNothingAndMakesNoSecondBackup() throws {
        defer { cleanUp() }
        let url = try write(claudeSettings, to: "settings.json")
        _ = try installer.mergeClaudeSettings(settingsURL: url, helperPath: helper)
        let afterFirst = try object(at: url)
        let later = HookInstaller(now: { utc("2026-10-14T05:09:00Z") }, calendar: hoChiMinhCalendar())
        #expect(try later.mergeClaudeSettings(settingsURL: url, helperPath: helper).isEmpty)
        #expect(try object(at: url) == afterFirst)
        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".bak") }
        #expect(backups.count == 1)
    }

    @Test func removingTakesOnlyOurGroupsAndRestoresTheOriginal() throws {
        defer { cleanUp() }
        let url = try write(claudeSettings, to: "settings.json")
        let original = try object(at: url)
        _ = try installer.mergeClaudeSettings(settingsURL: url, helperPath: helper)
        let removed = try installer.removeClaude(settingsURL: url, helperPath: helper)
        #expect(removed.count == 8)
        #expect(try object(at: url) == original)
    }

    @Test func removingLeavesAnotherToolsHookInTheSameGroup() throws {
        defer { cleanUp() }
        let url = try write("""
        {"hooks": {"Stop": [{"hooks": [
          {"type": "command", "command": "/opt/other/stop"},
          {"type": "command", "command": "'\(helper)' --source claude"}]}]}}
        """, to: "settings.json")
        _ = try installer.removeClaude(settingsURL: url, helperPath: helper)
        let result = try object(at: url)
        #expect(groups(result, "Stop").map(commands) == [["/opt/other/stop"]])
    }

    @Test func mergingCreatesAMissingSettingsFileWithoutABackup() throws {
        defer { cleanUp() }
        let url = directory.appending(path: "settings.json")
        _ = try installer.mergeClaudeSettings(settingsURL: url, helperPath: helper)
        #expect(ours(try object(at: url), "Stop").count == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["settings.json"])
    }

    @Test func settingsThatAreNotAJSONObjectAreLeftAlone() throws {
        defer { cleanUp() }
        let url = try write("[1, 2]", to: "settings.json")
        #expect(throws: HookInstaller.InstallError.notAJSONObject) { try installer.mergeClaudeSettings(settingsURL: url, helperPath: helper) }
        #expect(try String(contentsOf: url, encoding: .utf8) == "[1, 2]")
    }

    @Test func removingFromAMissingFileDoesNothing() throws {
        defer { cleanUp() }
        let url = directory.appending(path: "settings.json")
        #expect(try installer.removeClaude(settingsURL: url, helperPath: helper).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func aSecondChangeInTheSameSecondKeepsTheOriginalBackup() throws {
        defer { cleanUp() }
        let url = try write(claudeSettings, to: "settings.json")
        let original = try object(at: url)
        _ = try installer.mergeClaudeSettings(settingsURL: url, helperPath: helper)
        _ = try installer.removeClaude(settingsURL: url, helperPath: helper)
        _ = try installer.mergeClaudeSettings(settingsURL: url, helperPath: helper)
        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".bak") }.sorted()
        #expect(backups == [
            "settings.json.mynotch-20261014-120709-1.bak",
            "settings.json.mynotch-20261014-120709-2.bak",
            "settings.json.mynotch-20261014-120709.bak",
        ])
        #expect(try object(at: directory.appending(path: "settings.json.mynotch-20261014-120709.bak")) == original)
    }

    @Test func eventsThatAreNotAnArrayAreNotReplaced() throws {
        defer { cleanUp() }
        let text = #"{"hooks": {"Stop": {"oops": true}}}"#
        let url = try write(text, to: "settings.json")
        #expect(throws: HookInstaller.InstallError.hooksNotAnArray(event: "Stop")) {
            try installer.mergeClaudeSettings(settingsURL: url, helperPath: helper)
        }
        #expect(try String(contentsOf: url, encoding: .utf8) == text)
    }

    @Test func onlyTheExactQuotedHelperIsOurs() throws {
        defer { cleanUp() }
        let sibling = "'\(helper)-beta' --source claude"
        let guardedSibling = HookInstaller.command(helperPath: helper + "-beta", source: "claude")
        let entries = [sibling, guardedSibling].map { ["type": "command", "command": $0] }
        let json = try JSONSerialization.data(withJSONObject: ["hooks": ["Stop": [["hooks": entries]]]])
        let url = try write(String(decoding: json, as: UTF8.self), to: "settings.json")
        _ = try installer.mergeClaudeSettings(settingsURL: url, helperPath: helper)
        #expect(groups(try object(at: url), "Stop").count == 2)
        _ = try installer.removeClaude(settingsURL: url, helperPath: helper)
        #expect(groups(try object(at: url), "Stop").map(commands) == [[sibling, guardedSibling]])
    }

    @Test func aWriteKeepsThePermissionsOfTheFile() throws {
        defer { cleanUp() }
        let url = try write(claudeSettings, to: "settings.json")
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        _ = try installer.mergeClaudeSettings(settingsURL: url, helperPath: helper)
        #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int == 0o600)
    }

    @Test func aSymlinkedFileIsWrittenThroughAndStaysALink() throws {
        defer { cleanUp() }
        let real = try write(claudeSettings, to: "real.json")
        let link = directory.appending(path: "settings.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        _ = try installer.mergeClaudeSettings(settingsURL: link, helperPath: helper)
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) == real.path)
        #expect(ours(try object(at: real), "Stop").count == 1)
        let backup = directory.appending(path: "settings.json.mynotch-20261014-120709.bak")
        #expect(ours(try object(at: backup), "Stop").isEmpty)
    }

    // MARK: Codex

    let codexHooks = """
    {"hooks": {
      "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "/opt/other/audit"}]}],
      "Stop": [{"hooks": [{"type": "command", "command": "/opt/other/done"}]}]
    }}
    """

    @Test func codexHooksMergeIdempotentlyAndRemoveCleanly() throws {
        defer { cleanUp() }
        let url = try write(codexHooks, to: "hooks.json")
        let original = try object(at: url)
        let added = try installer.mergeCodexHooks(hooksURL: url, helperPath: helper)
        #expect(!added.isEmpty)
        let merged = try object(at: url)
        for event in ["UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop", "SessionEnd"] {
            #expect(ours(merged, event).count == 1, "\(event)")
            #expect(commands(ours(merged, event)[0]) == [HookInstaller.command(helperPath: helper, source: "codex")], "\(event)")
            #expect(firstHook(ours(merged, event)[0])?["timeout"] as? Int == HookInstaller.timeoutSeconds(for: event), "\(event)")
        }
        #expect(groups(merged, "PreToolUse").count == 2)
        #expect(try installer.mergeCodexHooks(hooksURL: url, helperPath: helper).isEmpty)
        #expect(try object(at: directory.appending(path: "hooks.json.mynotch-20261014-120709.bak")) == original)

        #expect(try installer.removeCodex(hooksURL: url, helperPath: helper).count == added.count)
        #expect(try object(at: url) == original)
    }

    @Test func codexAsksToTrustNewHooks() {
        defer { cleanUp() }
        #expect(HookInstaller.codexTrustNote.contains("Codex"))
    }

    @Test func codexConfigTomlIsNotTouched() throws {
        defer { cleanUp() }
        let config = try write("notify = [\"x\"]\n", to: "config.toml")
        let url = try write(codexHooks, to: "hooks.json")
        _ = try installer.mergeCodexHooks(hooksURL: url, helperPath: helper)
        #expect(try String(contentsOf: config, encoding: .utf8) == "notify = [\"x\"]\n")
    }

    // MARK: Plugin

    @Test func thePluginIsValidJSONThatRunsTheHelper() throws {
        defer { cleanUp() }
        let plugin = directory.appending(path: "plugin dir", directoryHint: .isDirectory)
        let commandsToShow = try installer.claudePlugin(at: plugin, helperPath: helper)

        let manifest = try object(at: plugin.appending(path: ".claude-plugin/plugin.json"))
        #expect(manifest["name"] as? String == "mynotch")
        let marketplace = try object(at: plugin.appending(path: ".claude-plugin/marketplace.json"))
        let entry = try #require((marketplace["plugins"] as? [NSDictionary])?.first)
        #expect(entry["name"] as? String == "mynotch")
        #expect(entry["source"] as? String == "./")
        let marketplaceName = try #require(marketplace["name"] as? String)

        let hooks = try object(at: plugin.appending(path: "hooks/hooks.json"))
        for event in ["UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Notification", "Stop", "StopFailure", "SessionEnd"] {
            #expect(ours(hooks, event).count == 1, "\(event)")
            #expect(commands(ours(hooks, event)[0]) == [HookInstaller.command(helperPath: helper, source: "claude")], "\(event)")
            #expect(firstHook(ours(hooks, event)[0])?["timeout"] as? Int == HookInstaller.timeoutSeconds(for: event), "\(event)")
        }
        #expect(commandsToShow == [
            "claude plugin marketplace add '\(plugin.path)'",
            "claude plugin install mynotch@\(marketplaceName)",
        ])
    }

    // MARK: The command

    @Test func aHelperThatIsMissingOrNotExecutableIsASilentSuccessNotAHookError() throws {
        defer { cleanUp() }
        let missing = HookInstaller.command(helperPath: directory.appending(path: "gone's/mynotch-hook").path, source: "claude")
        let missingResult = try run(missing)
        #expect(missingResult.status == 0)
        #expect(missingResult.output.isEmpty)
        let plain = try write("#!/bin/sh\nexit 3\n", to: "plain-hook")
        let plainResult = try run(HookInstaller.command(helperPath: plain.path, source: "claude"))
        #expect(plainResult.status == 0)
        #expect(plainResult.output.isEmpty)
    }

    @Test func theCommandRunsTheHelperWithItsSourceFromAPathWithSpacesAndAQuote() throws {
        defer { cleanUp() }
        let folder = directory.appending(path: "Application Support's bin", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let marker = directory.appending(path: "arguments.txt")
        let script = folder.appending(path: "mynotch-hook")
        try Data("#!/bin/sh\necho \"$@\" > '\(marker.path)'\nexit 7\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let result = try run(HookInstaller.command(helperPath: script.path, source: "codex"))
        #expect(try String(contentsOf: marker, encoding: .utf8) == "--source codex\n")
        // The helper's own status is what the agent sees; the real helper always exits 0.
        #expect(result.status == 7)
    }

    @Test func shellQuotingSurvivesASingleQuoteInThePath() {
        defer { cleanUp() }
        #expect(HookInstaller.shellQuoted("/a b/it's") == "'/a b/it'\\''s'")
    }

    // MARK: Permission hook

    /// The helper waits up to 60 s for the user, so the agent must not stop the hook before that.
    @Test func thePermissionHookIsGivenMoreTimeThanTheHelperWaitsAndTheOthersFive() {
        #expect(HookInstaller.timeoutSeconds(for: "PermissionRequest") == 70)
        #expect(Double(HookInstaller.timeoutSeconds(for: "PermissionRequest")) > PermissionClient.defaultTimeout)
        for event in HookInstaller.claudeEvents where event != "PermissionRequest" {
            #expect(HookInstaller.timeoutSeconds(for: event) == 5, "\(event)")
        }
    }

    @Test func aSettingsFileInstalledBeforeThePermissionHookGetsItsTimeoutRaisedAndNothingElse() throws {
        defer { cleanUp() }
        let command = HookInstaller.command(helperPath: helper, source: "claude")
        let before: [String: Any] = [
            "theme": "dark",
            "hooks": [
                "PermissionRequest": [
                    ["matcher": "Bash", "hooks": [["type": "command", "command": "/opt/other/audit", "timeout": 5]]],
                    ["hooks": [["type": "command", "command": command, "timeout": 5]]],
                ],
                "Stop": [["hooks": [["type": "command", "command": command, "timeout": 5]]]],
            ],
        ]
        let url = try write(String(decoding: try JSONSerialization.data(withJSONObject: before), as: UTF8.self), to: "settings.json")
        let original = try object(at: url)
        let summary = try installer.mergeClaudeSettings(settingsURL: url, helperPath: helper)

        let merged = try object(at: url)
        #expect(firstHook(ours(merged, "PermissionRequest")[0])?["timeout"] as? Int == 70)
        let others = groups(merged, "PermissionRequest").filter { commands($0) == ["/opt/other/audit"] }
        #expect(others.count == 1)
        #expect(firstHook(others[0])?["timeout"] as? Int == 5)
        #expect(others[0]["matcher"] as? String == "Bash")
        #expect(merged["theme"] as? String == "dark")
        #expect(groups(merged, "Stop") == groups(original, "Stop"))
        // One line for the raised timeout and one for each event that was missing.
        #expect(summary.contains { $0.hasPrefix("PermissionRequest: ~") })
        #expect(summary.filter { $0.contains(": + ") }.count == HookInstaller.claudeEvents.count - 2)
        #expect(try object(at: directory.appending(path: "settings.json.mynotch-20261014-120709.bak")) == original)
        #expect(try installer.mergeClaudeSettings(settingsURL: url, helperPath: helper).isEmpty)
    }

    @Test func aTimeoutShorterThanTheWaitIsRaisedAndALongerOneIsTheUsers() throws {
        defer { cleanUp() }
        let command = HookInstaller.command(helperPath: helper, source: "claude")
        let cases: [(timeout: Int?, expected: Int?)] = [(5, 70), (30, 70), (70, 70), (120, 120), (nil, nil)]
        for (index, entry) in cases.enumerated() {
            var hook: [String: Any] = ["type": "command", "command": command]
            hook["timeout"] = entry.timeout
            let json = try JSONSerialization.data(withJSONObject: ["hooks": ["PermissionRequest": [["hooks": [hook]]]]])
            let url = try write(String(decoding: json, as: UTF8.self), to: "settings-\(index).json")
            _ = try installer.mergeClaudeSettings(settingsURL: url, helperPath: helper)
            #expect(firstHook(ours(try object(at: url), "PermissionRequest")[0])?["timeout"] as? Int == entry.expected, "\(entry)")
        }
    }

    @Test func removingAfterTheTimeoutWasRaisedStillRestoresTheOriginal() throws {
        defer { cleanUp() }
        let command = HookInstaller.command(helperPath: helper, source: "codex")
        let json = try JSONSerialization.data(withJSONObject: ["hooks": ["PermissionRequest": [["hooks": [["type": "command", "command": command, "timeout": 5]]]]]])
        let url = try write(String(decoding: json, as: UTF8.self), to: "hooks.json")
        _ = try installer.mergeCodexHooks(hooksURL: url, helperPath: helper)
        #expect(firstHook(ours(try object(at: url), "PermissionRequest")[0])?["timeout"] as? Int == 70)
        _ = try installer.removeCodex(hooksURL: url, helperPath: helper)
        #expect(groups(try object(at: url), "PermissionRequest").isEmpty)
    }

    @Test func theSettingsExplanationSaysWhatThePermissionHookDoes() {
        let text = HookInstaller.permissionExplanation
        for part in ["PermissionRequest", "Cho phép", "Từ chối", "Hỏi trong terminal", "60 giây"] { #expect(text.contains(part), "\(part)") }
    }
}
