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
            #expect(commands(ours(merged, event)[0]).first?.hasSuffix("--source claude") == true)
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
        for event in ["UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop"] {
            #expect(ours(merged, event).count == 1, "\(event)")
            #expect(commands(ours(merged, event)[0]).first?.hasSuffix("--source codex") == true)
        }
        #expect(groups(merged, "PreToolUse").count == 2)
        #expect(try installer.mergeCodexHooks(hooksURL: url, helperPath: helper).isEmpty)
        #expect(try object(at: directory.appending(path: "hooks.json.mynotch-20261014-120709.bak")) == original)

        #expect(try installer.removeCodex(hooksURL: url, helperPath: helper).count == added.count)
        #expect(try object(at: url) == original)
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
        }
        #expect(commandsToShow == [
            "claude plugin marketplace add '\(plugin.path)'",
            "claude plugin install mynotch@\(marketplaceName)",
        ])
    }

    @Test func shellQuotingSurvivesASingleQuoteInThePath() {
        #expect(HookInstaller.shellQuoted("/a b/it's") == "'/a b/it'\\''s'")
    }
}
