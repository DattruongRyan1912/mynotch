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
    /// Where the hooks run the helper from: a path that stays, unlike the app bundle's.
    var helperPath: String
    /// Puts the helper at `helperPath`, and throws when it cannot.
    var installHelper: () throws -> Void
    var claudeSettingsURL: URL
    var codexHooksURL: URL
    /// Puts text on the pasteboard.
    var copy: (String) -> Void

    /// The helper is copied from the app bundle to `bin` in the module's storage, under Application Support.
    static func system(storageDirectory: URL) -> HookSetup {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let bundled = Bundle.main.bundleURL.appending(path: "Contents/MacOS/mynotch-hook")
        let stable = storageDirectory.appending(path: "bin/mynotch-hook")
        return HookSetup(
            installer: HookInstaller(),
            helperPath: stable.path,
            installHelper: { try HookHelper.install(from: bundled, to: stable) },
            claudeSettingsURL: home.appending(path: ".claude/settings.json"),
            codexHooksURL: home.appending(path: ".codex/hooks.json"),
            copy: AgentOpener.system.copy
        )
    }
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
    /// Runs after the hooks, or the plugin that holds them, were written: they send to the module, which has to listen.
    @ObservationIgnored private let didInstall: () -> Void

    init(setup: HookSetup, pluginDirectory: URL, didInstall: @escaping () -> Void = {}) {
        self.setup = setup
        self.pluginDirectory = pluginDirectory
        self.didInstall = didInstall
    }

    func url(of target: Target) -> URL {
        target == .claude ? setup.claudeSettingsURL : setup.codexHooksURL
    }

    /// What "install" is about to write, for the confirmation before it touches the user's file.
    func preview(of target: Target) -> String {
        let events = target == .claude ? HookInstaller.claudeEvents : HookInstaller.codexEvents
        let command = HookInstaller.command(helperPath: setup.helperPath, source: target == .claude ? "claude" : "codex")
        return """
        Thêm một hook cho các sự kiện: \(events.joined(separator: ", ")).
        Lệnh: \(command)
        Một bản sao lưu \(target.fileName).mynotch-<thời gian>.bak được tạo cạnh file trước khi sửa. Hook của công cụ khác và mọi khoá khác được giữ nguyên.
        """
    }

    /// Writes the plugin; Claude Code installs it with the two commands, which the user runs.
    func installClaudePlugin() {
        do {
            try setup.installHelper()
            pluginCommands = try setup.installer.claudePlugin(at: pluginDirectory, helperPath: setup.helperPath)
            message = "Đã tạo plugin. Chạy hai lệnh bên dưới trong terminal để cài. Để gỡ: \(HookInstaller.pluginUninstallCommand)"
            didInstall()
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
            try setup.installHelper()
            let lines = switch target {
            case .claude: try setup.installer.mergeClaudeSettings(settingsURL: setup.claudeSettingsURL, helperPath: setup.helperPath)
            case .codex: try setup.installer.mergeCodexHooks(hooksURL: setup.codexHooksURL, helperPath: setup.helperPath)
            }
            didInstall()
            return lines
        } done: { lines in
            lines.isEmpty ? "Đã cài từ trước, không có gì thay đổi." : "Đã thêm \(lines.count) hook vào \(target.fileName)."
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
