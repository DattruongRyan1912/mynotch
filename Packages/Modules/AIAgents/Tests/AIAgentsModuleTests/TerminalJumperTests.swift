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
    var scriptResult = AppleScriptResult.value("found")
    var running: Set<String> = []
    let bundleIDs: [String: String] = [
        "/System/Applications/Utilities/Terminal.app": "com.apple.Terminal",
        "/Applications/iTerm.app": "com.googlecode.iterm2",
        "/Applications/Visual Studio Code.app": "com.microsoft.VSCode",
        "/Applications/Ghostty.app": "com.mitchellh.ghostty",
    ]

    var scripts: [String] { steps.compactMap { if case let .script(text) = $0 { text } else { nil } } }

    func jumper(table: FakeProcessTable) -> TerminalJumper {
        TerminalJumper(
            processTable: table, bundleIdentifier: { [bundleIDs] in bundleIDs[$0.path] }, runner: FakeRunner(machine: self),
            isRunning: { [self] in running.contains($0.path) }, activate: { [self] in steps.append(.activated($0.path)) },
            open: { [self] in steps.append(.opened(folder: $0.path, app: $1.path)) }
        )
    }
}

struct FakeRunner: AppleScriptRunning {
    let machine: FakeMachine

    func run(_ source: String) async -> AppleScriptResult {
        await MainActor.run {
            machine.steps.append(.script(source))
            return machine.scriptResult
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
