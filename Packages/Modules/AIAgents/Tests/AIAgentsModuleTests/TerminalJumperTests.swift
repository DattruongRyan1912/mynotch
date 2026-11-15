import Foundation
import Testing
@testable import AIAgentsModule

/// Everything the jumper may do to the machine, recorded in order and never done.
@MainActor
final class FakeMachine {
    enum Step: Equatable {
        case script(String)
        case activated(String)
        case opened(folder: String, app: String)
    }

    var steps: [Step] = []
    /// What a script answers once `scriptQueue` is empty.
    var scriptResult = AppleScriptResult.value("found")
    /// Answers to the next scripts, in order.
    var scriptQueue: [AppleScriptResult] = []
    var running: Set<String> = []
    let bundleIDs: [String: String] = [
        "/System/Applications/Utilities/Terminal.app": "com.apple.Terminal",
        "/Applications/iTerm.app": "com.googlecode.iterm2",
        "/Applications/Visual Studio Code.app": "com.microsoft.VSCode",
        "/Applications/Ghostty.app": "com.mitchellh.ghostty",
        "/Applications/Claude.app": "com.anthropic.claudefordesktop",
    ]

    var scripts: [String] { steps.compactMap { if case let .script(text) = $0 { text } else { nil } } }

    func jumper(table: FakeProcessTable) -> TerminalJumper {
        TerminalJumper(
            processTable: table, bundleIdentifier: { [bundleIDs] in bundleIDs[$0.path] }, runner: FakeRunner(machine: self),
            isRunning: { [self] in running.contains($0.path) },
            runningApp: { [self] id in bundleIDs.first { running.contains($0.key) && $0.value == id }.map { URL(filePath: $0.key, directoryHint: .isDirectory) } },
            activate: { [self] in steps.append(.activated($0.path)) },
            open: { [self] in steps.append(.opened(folder: $0.path, app: $1.path)) }
        )
    }

    func nextScriptResult() -> AppleScriptResult {
        scriptQueue.isEmpty ? scriptResult : scriptQueue.removeFirst()
    }
}

struct FakeRunner: AppleScriptRunning {
    let machine: FakeMachine

    func run(_ source: String) async -> AppleScriptResult {
        await MainActor.run {
            machine.steps.append(.script(source))
            return machine.nextScriptResult()
        }
    }
}

@MainActor
@Suite struct TerminalJumperTests {
    let machine = FakeMachine()
    let folder = URL(filePath: "/Users/example/Projects/demo", directoryHint: .isDirectory)

    func table(app: String, tty: String? = "ttys003") -> FakeProcessTable {
        FakeProcessTable(
            process(500, parent: 400, tty: tty, path: "/bin/claude"), process(400, parent: 1, path: app)
        )
    }

    let terminalApp = "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"
    let iTermApp = "/Applications/iTerm.app/Contents/MacOS/iTerm2"

    func jump(_ table: FakeProcessTable, pid: pid_t? = 500, folder: URL? = nil) async -> TerminalJumper.Outcome {
        await machine.jumper(table: table).jump(pid: pid, folder: folder)
    }

    // MARK: Terminal.app and iTerm2

    @Test func terminalSelectsTheTabByItsTtyAndThenComesToTheFront() async {
        machine.running = ["/System/Applications/Utilities/Terminal.app"]
        let outcome = await jump(table(app: terminalApp))
        #expect(outcome == .selectedTab)
        #expect(machine.scripts.count == 1)
        #expect(machine.scripts.first?.contains("/dev/ttys003") == true)
        #expect(machine.scripts.first?.contains("com.apple.Terminal") == true)
        #expect(machine.steps.last == .activated("/System/Applications/Utilities/Terminal.app"))
    }

    @Test func iTermIsAskedTheSameWay() async {
        machine.running = ["/Applications/iTerm.app"]
        let outcome = await jump(table(app: iTermApp, tty: "ttys011"))
        #expect(outcome == .selectedTab)
        #expect(machine.scripts.first?.contains("com.googlecode.iterm2") == true)
        #expect(machine.scripts.first?.contains("/dev/ttys011") == true)
        #expect(machine.steps.last == .activated("/Applications/iTerm.app"))
    }

    @Test func noTabWithThatTtyStillBringsTheAppToTheFront() async {
        machine.running = ["/Applications/iTerm.app"]
        machine.scriptResult = .value("none")
        #expect(await jump(table(app: iTermApp)) == .activatedApp)
        #expect(machine.steps.last == .activated("/Applications/iTerm.app"))
    }

    @Test func aDeniedAutomationPermissionFallsBackToTheAppAndSaysSo() async {
        machine.running = ["/System/Applications/Utilities/Terminal.app"]
        machine.scriptResult = .notPermitted
        #expect(await jump(table(app: terminalApp)) == .activatedAppWithoutAutomation)
        #expect(machine.steps.last == .activated("/System/Applications/Utilities/Terminal.app"))
        #expect(machine.scripts.count == 1)
    }

    @Test func aScriptThatFailsForAnyOtherReasonFallsBackToTheApp() async {
        machine.running = ["/System/Applications/Utilities/Terminal.app"]
        machine.scriptResult = .failed
        #expect(await jump(table(app: terminalApp)) == .activatedApp)
        #expect(machine.steps.last == .activated("/System/Applications/Utilities/Terminal.app"))
    }

    @Test func withoutATtyThereIsNothingToSelectSoOnlyTheAppComesToTheFront() async {
        machine.running = ["/System/Applications/Utilities/Terminal.app"]
        #expect(await jump(table(app: terminalApp, tty: nil)) == .activatedApp)
        #expect(machine.scripts.isEmpty)
        #expect(machine.steps == [.activated("/System/Applications/Utilities/Terminal.app")])
    }

    // MARK: Editors and other terminals

    @Test func anEditorOpensTheFolderInItselfAndRunsNoScript() async {
        machine.running = ["/Applications/Visual Studio Code.app"]
        let editor = table(app: "/Applications/Visual Studio Code.app/Contents/MacOS/Electron")
        #expect(await jump(editor, folder: folder) == .openedFolder)
        #expect(machine.steps == [.opened(folder: folder.path, app: "/Applications/Visual Studio Code.app")])
    }

    @Test func anEditorWithoutAFolderIsJustActivated() async {
        machine.running = ["/Applications/Visual Studio Code.app"]
        let editor = table(app: "/Applications/Visual Studio Code.app/Contents/MacOS/Electron")
        #expect(await jump(editor) == .activatedApp)
        #expect(machine.steps == [.activated("/Applications/Visual Studio Code.app")])
    }

    @Test func otherTerminalsAreJustActivatedEvenWhenAFolderIsKnown() async {
        machine.running = ["/Applications/Ghostty.app"]
        #expect(await jump(table(app: "/Applications/Ghostty.app/Contents/MacOS/ghostty"), folder: folder) == .activatedApp)
        #expect(machine.steps == [.activated("/Applications/Ghostty.app")])
    }

    // MARK: Nothing to jump to

    @Test func noPidMeansNothingWasFound() async {
        machine.running = ["/System/Applications/Utilities/Terminal.app"]
        #expect(await jump(table(app: terminalApp), pid: nil) == .notFound)
        #expect(machine.steps.isEmpty)
    }

    @Test func aProcessWithoutATerminalAppAboveItMeansNothingWasFound() async {
        let tmux = FakeProcessTable(process(500, parent: 300, tty: "ttys005", path: "/bin/claude"), process(300, parent: 1, path: "/opt/homebrew/bin/tmux"))
        #expect(await jump(tmux) == .notFound)
        #expect(machine.steps.isEmpty)
    }

    @Test func anAppThatIsNotRunningIsNeverLaunchedOrScripted() async {
        #expect(await jump(table(app: terminalApp), folder: folder) == .notFound)
        #expect(await jump(table(app: "/Applications/Visual Studio Code.app/Contents/MacOS/Electron"), folder: folder) == .notFound)
        #expect(machine.steps.isEmpty)
    }

    // MARK: iTerm2's server, and a chain that ends without an app

    let iTermServer = "/Users/example/Library/Application Support/iTerm2/iTermServer-3.5.0"
    let iTermFolder = "/Applications/iTerm.app"
    let terminalFolder = "/System/Applications/Utilities/Terminal.app"

    /// claude -> zsh -> login -> iTermServer -> launchd, the jobs of an iTerm2 session, none of them inside the app.
    func iTermTable(tty: String? = "ttys011") -> FakeProcessTable {
        FakeProcessTable(
            process(500, parent: 400, tty: tty, path: "/bin/claude"), process(400, parent: 300, tty: tty, path: "/bin/zsh"),
            process(300, parent: 200, tty: tty, path: "/usr/bin/login"), process(200, parent: 1, path: iTermServer)
        )
    }

    /// claude -> zsh -> tmux server -> launchd, which no terminal app is above.
    func tmuxTable() -> FakeProcessTable {
        FakeProcessTable(
            process(500, parent: 400, tty: "ttys005", path: "/bin/claude"), process(400, parent: 300, tty: "ttys005", path: "/bin/zsh"),
            process(300, parent: 1, path: "/opt/homebrew/bin/tmux")
        )
    }

    @Test func anITermSessionIsFoundThroughItsServerAndItsTabSelectedByTty() async {
        machine.running = [iTermFolder]
        let outcome = await jump(iTermTable())
        #expect(outcome == .selectedTab)
        #expect(machine.scripts.count == 1)
        #expect(machine.scripts.first?.contains("com.googlecode.iterm2") == true)
        #expect(machine.scripts.first?.contains("/dev/ttys011") == true)
        #expect(machine.steps.last == .activated(iTermFolder))
    }

    @Test func anITermThatIsNotRunningIsNeitherScriptedNorLaunched() async {
        #expect(await jump(iTermTable(), folder: folder) == .notFound)
        #expect(machine.steps.isEmpty)
    }

    @Test func whenNoAppIsAboveTheAgentTheRunningTerminalsAreAskedAboutItsTty() async {
        machine.running = [iTermFolder, terminalFolder]
        machine.scriptQueue = [.value("none"), .value("found")]
        #expect(await jump(tmuxTable()) == .selectedTab)
        #expect(machine.scripts.count == 2)
        #expect(machine.scripts[0].contains("com.googlecode.iterm2") && machine.scripts[0].contains("/dev/ttys005"))
        #expect(machine.scripts[1].contains("com.apple.Terminal") && machine.scripts[1].contains("/dev/ttys005"))
        #expect(machine.steps.last == .activated(terminalFolder))
    }

    @Test func anITermThatHasTheTtyIsTheOnlyOneAsked() async {
        machine.running = [iTermFolder, terminalFolder]
        #expect(await jump(tmuxTable()) == .selectedTab)
        #expect(machine.scripts.count == 1)
        #expect(machine.scripts[0].contains("com.googlecode.iterm2"))
        #expect(machine.steps.last == .activated(iTermFolder))
    }

    @Test func aTtyNeitherTerminalHasLikeTmuxsOwnMeansNothingWasFound() async {
        machine.running = [iTermFolder, terminalFolder]
        machine.scriptResult = .value("none")
        #expect(await jump(tmuxTable(), folder: folder) == .notFound)
        #expect(machine.scripts.count == 2)
        #expect(machine.steps.allSatisfy { if case .script = $0 { true } else { false } })
    }

    @Test func onlyTheTerminalsThatRunAreAsked() async {
        machine.running = [terminalFolder]
        machine.scriptResult = .value("none")
        #expect(await jump(tmuxTable()) == .notFound)
        #expect(machine.scripts.count == 1)
        #expect(machine.scripts[0].contains("com.apple.Terminal"))
        machine.steps = []
        machine.running = []
        #expect(await jump(tmuxTable()) == .notFound)
        #expect(machine.steps.isEmpty)
    }

    @Test func aTerminalThatMacOSWillNotLetUsAskIsSkippedAndSaidSoOnlyWhenNoOtherHasTheTab() async {
        machine.running = [iTermFolder, terminalFolder]
        machine.scriptQueue = [.notPermitted, .value("found")]
        #expect(await jump(tmuxTable()) == .selectedTab)
        machine.steps = []
        machine.scriptQueue = [.notPermitted, .value("none")]
        #expect(await jump(tmuxTable()) == .notFoundWithoutAutomation)
        #expect(machine.steps.allSatisfy { if case .script = $0 { true } else { false } })
        machine.steps = []
        machine.scriptQueue = [.failed, .value("none")]
        #expect(await jump(tmuxTable()) == .notFound)
    }

    @Test func withoutATtyThereIsNothingToAskAbout() async {
        machine.running = [iTermFolder, terminalFolder]
        let noTty = FakeProcessTable(process(500, parent: 300, path: "/bin/claude"), process(300, parent: 1, path: "/opt/homebrew/bin/tmux"))
        #expect(await jump(noTty) == .notFound)
        #expect(machine.steps.isEmpty)
    }

    @Test func aTerminalAppIsNeverAskedAboutTheTtyWhenTheChainLeadsToAnotherApp() async {
        machine.running = [iTermFolder, terminalFolder, "/Applications/Ghostty.app"]
        #expect(await jump(table(app: "/Applications/Ghostty.app/Contents/MacOS/ghostty"), folder: folder) == .activatedApp)
        #expect(machine.steps == [.activated("/Applications/Ghostty.app")])
    }

    /// The `claude` that the desktop app downloads is in an `.app` folder but is no running app: the Claude app above is the terminal.
    @Test func aToolInsideAnAppFolderIsNotTheAppToActivate() async {
        machine.running = ["/Applications/Claude.app"]
        let desktop = FakeProcessTable(
            process(500, parent: 480, path: "/Users/example/Library/Application Support/Claude/claude-code/2.1.295/abc/claude.app/Contents/MacOS/claude"),
            process(480, parent: 1, path: "/Applications/Claude.app/Contents/MacOS/Claude")
        )
        #expect(await jump(desktop, folder: folder) == .activatedApp)
        #expect(machine.steps == [.activated("/Applications/Claude.app")])
    }

    @Test func anAppFolderIsTheSameWithOrWithoutTheSlashAndThroughALink() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "TerminalJumperTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let app = directory.appending(path: "Real.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let link = directory.appending(path: "Link.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: app)
        #expect(TerminalJumper.isSameApp(URL(filePath: app.path), URL(filePath: app.path + "/")))
        #expect(TerminalJumper.isSameApp(link, app))
        #expect(!TerminalJumper.isSameApp(directory, app))
        #expect(!TerminalJumper.isSameApp(nil, app))
    }

    @Test func theInertJumperDoesNothingAndFindsNothing() async {
        #expect(await TerminalJumper.inert.jump(pid: getpid(), folder: folder) == .notFound)
    }
}
