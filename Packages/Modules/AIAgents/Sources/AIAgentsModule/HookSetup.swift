import Foundation
import Observation

/// What the Settings buttons ask of the installer, so tests can use a fake.
protocol HookInstalling {
    func claudePlugin(at directory: URL, helperPath: String) throws -> [String]
    func mergeClaudeSettings(settingsURL: URL, helperPath: String) throws -> [String]
    func removeClaude(settingsURL: URL, helperPath: String) throws -> [String]
    func mergeCodexHooks(hooksURL: URL, helperPath: String) throws -> [String]
    func removeCodex(hooksURL: URL, helperPath: String) throws -> [String]
}

extension HookInstaller: HookInstalling {}

/// Which files and which helper the buttons work on. The real `~/.claude` and `~/.codex` files are only named
/// here; they are read or written when a button is pressed.
struct HookSetup {
    var installer: any HookInstalling
    var helperPath: String
    var claudeSettingsURL: URL
    var codexHooksURL: URL
    /// Puts text on the pasteboard.
    var copy: (String) -> Void

    static let system: HookSetup = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return HookSetup(
            installer: HookInstaller(),
            helperPath: Bundle.main.bundleURL.appending(path: "Contents/MacOS/mynotch-hook").path,
            claudeSettingsURL: home.appending(path: ".claude/settings.json"),
            codexHooksURL: home.appending(path: ".codex/hooks.json"),
            copy: AgentOpener.system.copy
        )
    }()
}

/// The state behind the install buttons: what the last action did, and the commands to run for the plugin.
@Observable
final class HookSetupModel {
    enum Target {
        case claude, codex

        var fileName: String { self == .claude ? "settings.json" : "hooks.json" }
    }

    private(set) var message = ""
    private(set) var pluginCommands: [String] = []

    @ObservationIgnored private let setup: HookSetup
    @ObservationIgnored private let pluginDirectory: URL

    init(setup: HookSetup, pluginDirectory: URL) {
        self.setup = setup
        self.pluginDirectory = pluginDirectory
    }

    func url(of target: Target) -> URL {
        target == .claude ? setup.claudeSettingsURL : setup.codexHooksURL
    }

    /// Writes the plugin; Claude Code installs it with the two commands, which the user runs.
    func installClaudePlugin() {
        do {
            pluginCommands = try setup.installer.claudePlugin(at: pluginDirectory, helperPath: setup.helperPath)
            message = "Đã tạo plugin. Chạy hai lệnh bên dưới trong terminal để cài."
        } catch {
            pluginCommands = []
            message = "Không tạo được plugin: \(error.localizedDescription)"
        }
    }

    func copyPluginCommands() {
        setup.copy(pluginCommands.joined(separator: "\n"))
    }

    func merge(_ target: Target) {
        report("thêm") {
            switch target {
            case .claude: try setup.installer.mergeClaudeSettings(settingsURL: setup.claudeSettingsURL, helperPath: setup.helperPath)
            case .codex: try setup.installer.mergeCodexHooks(hooksURL: setup.codexHooksURL, helperPath: setup.helperPath)
            }
        } done: { lines in
            let summary = lines.isEmpty ? "Đã cài từ trước, không có gì thay đổi." : "Đã thêm \(lines.count) hook vào \(target.fileName)."
            return target == .codex ? summary + " " + HookInstaller.codexTrustNote : summary
        }
    }

    func remove(_ target: Target) {
        report("gỡ") {
            switch target {
            case .claude: try setup.installer.removeClaude(settingsURL: setup.claudeSettingsURL, helperPath: setup.helperPath)
            case .codex: try setup.installer.removeCodex(hooksURL: setup.codexHooksURL, helperPath: setup.helperPath)
            }
        } done: { lines in
            lines.isEmpty ? "Không có hook của MyNotch trong \(target.fileName)." : "Đã gỡ hook khỏi \(target.fileName)."
        }
    }

    private func report(_ verb: String, work: () throws -> [String], done: ([String]) -> String) {
        do {
            message = done(try work())
        } catch {
            message = "Không \(verb) được hook: \(error.localizedDescription)"
        }
    }
}
