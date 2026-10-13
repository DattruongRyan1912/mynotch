import Foundation
import Testing
@testable import AIAgentsModule

/// Records what the buttons ask of the installer; nothing is read or written.
final class FakeHookInstaller: HookInstalling {
    var calls: [String] = []
    var result: [String] = ["Stop: + command"]
    var failure: (any Error)?

    func setup(in directory: URL, copy: @escaping (String) -> Void = { _ in }) -> HookSetup {
        HookSetup(
            installer: self, helperPath: "/app/mynotch-hook", claudeSettingsURL: directory.appending(path: "claude-settings.json"),
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

    final class Copies { var texts: [String] = [] }

    func model() -> HookSetupModel {
        let copies = copies
        return HookSetupModel(setup: installer.setup(in: directory) { copies.texts.append($0) }, pluginDirectory: directory.appending(path: "claude-plugin"))
    }

    @Test func theButtonsCallTheInstallerWithTheInjectedFilesAndTheHelper() {
        let model = model()
        model.merge(.claude)
        model.remove(.claude)
        model.merge(.codex)
        model.remove(.codex)
        #expect(installer.calls == [
            "mergeClaude claude-settings.json /app/mynotch-hook",
            "removeClaude claude-settings.json /app/mynotch-hook",
            "mergeCodex codex-hooks.json /app/mynotch-hook",
            "removeCodex codex-hooks.json /app/mynotch-hook",
        ])
    }

    @Test func thePluginIsWrittenIntoTheGivenFolderAndItsCommandsCanBeCopied() {
        let model = model()
        model.installClaudePlugin()
        #expect(installer.calls == ["plugin claude-plugin /app/mynotch-hook"])
        #expect(model.pluginCommands == ["claude plugin marketplace add x", "claude plugin install y"])
        model.copyPluginCommands()
        #expect(copies.texts == ["claude plugin marketplace add x\nclaude plugin install y"])
    }

    @Test func onlyCodexIsToldToTrustTheNewHooks() {
        let model = model()
        model.merge(.claude)
        #expect(!model.message.contains(HookInstaller.codexTrustNote))
        model.merge(.codex)
        #expect(model.message.contains(HookInstaller.codexTrustNote))
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
}
