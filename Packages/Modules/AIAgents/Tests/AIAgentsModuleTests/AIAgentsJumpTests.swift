import Foundation
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import AIAgentsModule

/// Clicking a session through the module: the terminal is found from the session's process and brought to the front, with the
/// machine replaced by fakes, so no process table is read, no AppleScript is run and no app is touched.
@Suite final class AIAgentsJumpTests {
    let sandbox: Sandbox
    let opener = FakeOpener()
    let machine = FakeMachine()
    let terminalApp = "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"
    let key = AgentSessionKey(source: .claude, sessionID: "s1")

    init() throws {
        sandbox = try Sandbox()
    }

    func table(app: String? = nil, tty: String? = "ttys003") -> FakeProcessTable {
        FakeProcessTable(
            process(500, parent: 400, tty: tty, path: "/bin/claude"), process(400, parent: 1, path: app ?? terminalApp)
        )
    }

    func start(table: FakeProcessTable) async -> (module: AIAgentsModule, harness: RegistryHarness) {
        let module = AIAgentsModule(
            fileSystem: FakeAgentFileSystem(), claudeRoot: sandbox.claude, codexRoot: sandbox.codex, opener: opener.opener,
            hookSetup: nil, socketPath: nil, alert: {}, jumper: machine.jumper(table: table)
        )
        let harness = RegistryHarness([module])
        await harness.registry.bootstrap()
        return (module, harness)
    }

    func session(_ module: AIAgentsModule, pid: pid_t? = 500, cwd: String? = nil) {
        let now = Date()
        module.store?.apply([
            AgentEvent(source: .claude, sessionID: "s1", timestamp: now, kind: .turnStarted, pid: pid),
            AgentEvent(source: .claude, sessionID: "s1", timestamp: now, kind: .sessionStarted(cwd: cwd ?? sandbox.directory.path, branch: nil)),
        ], fromHooks: true)
    }

    @Test func theSessionsTerminalComesToTheFrontAndTheNotchCloses() async {
        machine.running = ["/System/Applications/Utilities/Terminal.app"]
        let (module, _) = await start(table: table())
        session(module)
        #expect(await module.jump(to: key))
        #expect(machine.scripts.count == 1)
        #expect(machine.scripts.first?.contains("/dev/ttys003") == true)
        #expect(machine.steps.last == .activated("/System/Applications/Utilities/Terminal.app"))
        #expect(opener.terminal.isEmpty)
        #expect(module.jumpHint.message == nil)
    }

    @Test func anEditorOpensTheSessionsFolderInItself() async {
        machine.running = ["/Applications/Visual Studio Code.app"]
        let (module, _) = await start(table: table(app: "/Applications/Visual Studio Code.app/Contents/MacOS/Electron"))
        session(module)
        #expect(await module.jump(to: key))
        #expect(machine.steps == [.opened(folder: sandbox.directory.path, app: "/Applications/Visual Studio Code.app")])
        #expect(opener.terminal.isEmpty)
    }

    @Test func aFolderThatIsNotThereIsNotGivenToTheEditor() async {
        machine.running = ["/Applications/Visual Studio Code.app"]
        let (module, _) = await start(table: table(app: "/Applications/Visual Studio Code.app/Contents/MacOS/Electron"))
        session(module, cwd: sandbox.directory.appending(path: "gone").path)
        #expect(await module.jump(to: key))
        #expect(machine.steps == [.activated("/Applications/Visual Studio Code.app")])
    }

    @Test func whenNoTerminalIsFoundTheFolderOpensInTerminalAsBefore() async {
        let (module, _) = await start(table: FakeProcessTable())
        session(module)
        #expect(await module.jump(to: key))
        #expect(opener.terminal.map(\.path) == [sandbox.directory.path])
        #expect(machine.steps.isEmpty)
    }

    @Test func aSessionWithoutAProcessFallsBackTheSameWay() async {
        machine.running = ["/System/Applications/Utilities/Terminal.app"]
        let (module, _) = await start(table: table())
        session(module, pid: nil)
        #expect(await module.jump(to: key))
        #expect(opener.terminal.map(\.path) == [sandbox.directory.path])
        #expect(machine.steps.isEmpty)
    }

    @Test func aSessionWithNeitherTerminalNorFolderDoesNothingAndKeepsTheNotchOpen() async {
        let (module, _) = await start(table: FakeProcessTable())
        #expect(await module.jump(to: key) == false)
        session(module, pid: nil, cwd: sandbox.directory.appending(path: "gone").path)
        #expect(await module.jump(to: key) == false)
        #expect(opener.terminal.isEmpty)
        #expect(machine.steps.isEmpty)
    }

    @Test func theTabsClickGoesThroughTheSameJump() async {
        machine.running = ["/System/Applications/Utilities/Terminal.app"]
        let (module, _) = await start(table: table())
        session(module)
        #expect(await module.actions.jump(key))
        #expect(machine.scripts.count == 1)
    }

    // MARK: Automation denied

    @Test func aDeniedPermissionActivatesTheAppAndShowsAHintOnceThatKeepsTheNotchOpen() async throws {
        machine.running = ["/System/Applications/Utilities/Terminal.app"]
        machine.scriptResult = .notPermitted
        let (module, harness) = await start(table: table())
        session(module)
        let keys = AIAgentsSettingsKeys(try #require(harness.settingsEnvironment(for: "aiagents")).settings)
        #expect(!harness.settings.value(keys.terminalHintShown))

        #expect(await module.jump(to: key) == false)
        #expect(machine.steps.last == .activated("/System/Applications/Utilities/Terminal.app"))
        #expect(module.jumpHint.message == AgentJumpHint.automationDenied)
        #expect(harness.settings.value(keys.terminalHintShown))

        module.jumpHint.dismiss()
        #expect(module.jumpHint.message == nil)
        #expect(await module.jump(to: key))
        #expect(module.jumpHint.message == nil)
        #expect(machine.scripts.count == 2)
    }

    @Test func aHintAlreadyShownInAnEarlierRunIsNotShownAgain() async throws {
        machine.running = ["/System/Applications/Utilities/Terminal.app"]
        machine.scriptResult = .notPermitted
        let (module, harness) = await start(table: table())
        session(module)
        harness.settings.set(true, for: AIAgentsSettingsKeys(try #require(harness.settingsEnvironment(for: "aiagents")).settings).terminalHintShown)
        #expect(await module.jump(to: key))
        #expect(module.jumpHint.message == nil)
        #expect(machine.steps.last == .activated("/System/Applications/Utilities/Terminal.app"))
    }

    @Test func aRunningTerminalThatCannotBeAskedOpensTheFolderAsBeforeAndShowsTheHintOnce() async {
        machine.running = ["/Applications/iTerm.app", "/System/Applications/Utilities/Terminal.app"]
        machine.scriptQueue = [.notPermitted, .value("none"), .notPermitted, .value("none")]
        let tmux = FakeProcessTable(
            process(500, parent: 400, tty: "ttys005", path: "/bin/claude"), process(400, parent: 1, path: "/opt/homebrew/bin/tmux")
        )
        let (module, _) = await start(table: tmux)
        session(module)
        #expect(await module.jump(to: key) == false)
        #expect(opener.terminal.map(\.path) == [sandbox.directory.path])
        #expect(module.jumpHint.message == AgentJumpHint.automationDenied)

        module.jumpHint.dismiss()
        #expect(await module.jump(to: key))
        #expect(opener.terminal.count == 2)
        #expect(module.jumpHint.message == nil)
    }

    @Test func anITermSessionIsFoundThroughItsServerAndTheNotchCloses() async {
        machine.running = ["/Applications/iTerm.app"]
        let iTerm = FakeProcessTable(
            process(500, parent: 400, tty: "ttys011", path: "/bin/claude"), process(400, parent: 300, tty: "ttys011", path: "/bin/zsh"),
            process(300, parent: 200, tty: "ttys011", path: "/usr/bin/login"),
            process(200, parent: 1, path: "/Users/example/Library/Application Support/iTerm2/iTermServer-3.5.0")
        )
        let (module, _) = await start(table: iTerm)
        session(module)
        #expect(await module.jump(to: key))
        #expect(machine.scripts.first?.contains("com.googlecode.iterm2") == true)
        #expect(machine.steps.last == .activated("/Applications/iTerm.app"))
        #expect(opener.terminal.isEmpty)
    }

    @Test func theHintTellsWhereToAllowItAndNamesNoApp() {
        #expect(AgentJumpHint.automationDenied.contains("Tự động hóa"))
        #expect(AgentJumpHint.automationDenied.contains("Cài đặt hệ thống"))
    }

    @Test func aModuleMadeForATestHasAJumperThatFindsNothing() async {
        let module = AIAgentsModule(
            fileSystem: FakeAgentFileSystem(), claudeRoot: sandbox.claude, codexRoot: sandbox.codex, opener: opener.opener
        )
        #expect(await module.jump(to: key) == false)
    }

    // MARK: The tab

    @Test func theTabShowsTheHintUntilItIsDismissed() async throws {
        let (module, _) = await start(table: FakeProcessTable())
        let tab = try #require(module.makeTab())
        func height() -> CGFloat {
            let hosting = NSHostingView(rootView: tab.content.frame(width: 420))
            return hosting.fittingSize.height
        }
        let plain = height()
        module.jumpHint.message = AgentJumpHint.automationDenied
        #expect(height() > plain)
        module.jumpHint.dismiss()
        #expect(height() == plain)
    }
}
