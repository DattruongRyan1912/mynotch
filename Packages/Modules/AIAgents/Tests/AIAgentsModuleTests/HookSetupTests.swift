import Foundation
import Testing
@testable import AIAgentsModule

/// Records what the buttons ask of the installer; nothing is read or written.
final class FakeHookInstaller: HookInstalling {
    var calls: [String] = []
    var result: [String] = ["Stop: + command"]
    var failure: (any Error)?
    /// Makes putting the helper in place fail, as when the app has no helper.
    var helperFailure: (any Error)?

    func setup(in directory: URL, copy: @escaping (String) -> Void = { _ in }) -> HookSetup {
        HookSetup(
            installer: self, helperPath: "/app/mynotch-hook",
            installHelper: { [self] in
                calls.append("helper")
                if let helperFailure { throw helperFailure }
            },
            claudeSettingsURL: directory.appending(path: "claude-settings.json"),
            codexHooksURL: directory.appending(path: "codex-hooks.json"), copy: copy
        )
    }

    private func record(_ call: String, _ url: URL?, _ helperPath: String) throws -> [String] {
        calls.append("\(call) \(url?.lastPathComponent ?? "-") \(helperPath)")
        if let failure { throw failure }
        return result
    }

    func claudePlugin(at directory: URL, helperPath: String) throws -> [String] {
        _ = try record("plugin", directory, helperPath)
        return ["claude plugin marketplace add x", "claude plugin install y"]
    }

    func mergeClaudeSettings(settingsURL: URL, helperPath: String) throws -> [String] { try record("mergeClaude", settingsURL, helperPath) }
    func removeClaude(settingsURL: URL, helperPath: String) throws -> [String] { try record("removeClaude", settingsURL, helperPath) }
    func mergeCodexHooks(hooksURL: URL, helperPath: String) throws -> [String] { try record("mergeCodex", hooksURL, helperPath) }
    func removeCodex(hooksURL: URL, helperPath: String) throws -> [String] { try record("removeCodex", hooksURL, helperPath) }
}

@Suite struct HookSetupTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "HookSetupTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    let installer = FakeHookInstaller()
    let copies = Copies()

    final class Copies {
        var texts: [String] = []
        var installs = 0
    }

    func model() -> HookSetupModel {
        let copies = copies
        return HookSetupModel(
            setup: installer.setup(in: directory) { copies.texts.append($0) }, pluginDirectory: directory.appending(path: "claude-plugin"),
            didInstall: { copies.installs += 1 }
        )
    }

    @Test func theButtonsCallTheInstallerWithTheInjectedFilesAndTheHelper() {
        let model = model()
        model.merge(.claude)
        model.remove(.claude)
        model.merge(.codex)
        model.remove(.codex)
        #expect(installer.calls == [
            "helper",
            "mergeClaude claude-settings.json /app/mynotch-hook",
            "removeClaude claude-settings.json /app/mynotch-hook",
            "helper",
            "mergeCodex codex-hooks.json /app/mynotch-hook",
            "removeCodex codex-hooks.json /app/mynotch-hook",
        ])
    }

    @Test func thePluginIsWrittenIntoTheGivenFolderAndItsCommandsCanBeCopied() {
        let model = model()
        model.installClaudePlugin()
        #expect(installer.calls == ["helper", "plugin claude-plugin /app/mynotch-hook"])
        #expect(model.pluginCommands == ["claude plugin marketplace add x", "claude plugin install y"])
        model.copyPluginCommands()
        #expect(copies.texts == ["claude plugin marketplace add x\nclaude plugin install y"])
    }

    /// The Settings rows show it once, under the Codex buttons; the message of an action must not repeat it.
    @Test func theTrustNoteIsNotRepeatedInTheMessageOfAnAction() {
        let model = model()
        model.merge(.claude)
        model.merge(.codex)
        #expect(!model.message.contains(HookInstaller.codexTrustNote))
        installer.result = []
        model.merge(.codex)
        #expect(!model.message.contains(HookInstaller.codexTrustNote))
    }

    @Test func nothingToDoAndFailuresAreReported() {
        let model = model()
        installer.result = []
        model.merge(.claude)
        #expect(model.message.contains("không có gì thay đổi"))
        model.remove(.claude)
        #expect(model.message.contains("Không có hook"))
        installer.failure = HookInstaller.InstallError.notAJSONObject
        model.merge(.claude)
        #expect(model.message.hasPrefix("Không thêm được hook"))
        model.installClaudePlugin()
        #expect(model.pluginCommands.isEmpty)
        #expect(model.message.hasPrefix("Không tạo được plugin"))
    }

    // MARK: Helper

    @Test func noHookIsWrittenWhenTheHelperCannotBePutInPlace() {
        let model = model()
        installer.helperFailure = HookHelper.Unavailable(path: "/app/mynotch-hook")
        model.merge(.claude)
        model.merge(.codex)
        model.installClaudePlugin()
        #expect(installer.calls == ["helper", "helper", "helper"])
        #expect(model.pluginCommands.isEmpty)
        #expect(model.message.hasPrefix("Không tạo được plugin"))
        #expect(model.message.contains("/app/mynotch-hook"))
        #expect(copies.installs == 0)
    }

    @Test func removingNeedsNoHelperSoItWorksAfterTheAppWasTrashed() {
        let model = model()
        installer.helperFailure = HookHelper.Unavailable(path: "/app/mynotch-hook")
        model.remove(.claude)
        model.remove(.codex)
        #expect(installer.calls == ["removeClaude claude-settings.json /app/mynotch-hook", "removeCodex codex-hooks.json /app/mynotch-hook"])
        #expect(model.message.hasPrefix("Đã gỡ"))
    }

    // MARK: Telling the module

    @Test func anInstallTellsTheModuleEvenWhenItChangedNothing() {
        let model = model()
        model.merge(.claude)
        installer.result = []
        model.merge(.codex)
        model.installClaudePlugin()
        #expect(copies.installs == 3)
    }

    @Test func aFailedInstallAndARemovalDoNotTellTheModule() {
        let model = model()
        model.remove(.claude)
        installer.failure = HookInstaller.InstallError.notAJSONObject
        model.merge(.claude)
        model.installClaudePlugin()
        #expect(copies.installs == 0)
    }

    // MARK: Preview

    @Test func theConfirmationNamesTheEventsTheCommandAndTheBackup() {
        let model = model()
        let claude = model.preview(of: .claude)
        for event in HookInstaller.claudeEvents { #expect(claude.contains(event)) }
        #expect(claude.contains(HookInstaller.command(helperPath: "/app/mynotch-hook", source: "claude")))
        #expect(claude.contains("settings.json.mynotch-<thời gian>.bak"))
        let codex = model.preview(of: .codex)
        #expect(!codex.contains("StopFailure"))
        #expect(codex.contains("PermissionRequest"))
        #expect(codex.contains(HookInstaller.command(helperPath: "/app/mynotch-hook", source: "codex")))
        #expect(codex.contains("hooks.json.mynotch-<thời gian>.bak"))
    }

    @Test func thePluginRouteSaysHowToUninstallIt() {
        let model = model()
        model.installClaudePlugin()
        #expect(model.message.contains("claude plugin uninstall mynotch@mynotch-local"))
    }
}
