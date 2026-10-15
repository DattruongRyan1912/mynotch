import Foundation
import Testing
@testable import AIAgentsModule

/// A process table written by hand, so no test reads the real one.
struct FakeProcessTable: ProcessTable {
    var entries: [pid_t: ProcessEntry] = [:]

    init(_ entries: ProcessEntry...) {
        for entry in entries { self.entries[entry.pid] = entry }
    }

    func entry(pid: pid_t) -> ProcessEntry? { entries[pid] }
}

func process(_ pid: pid_t, parent: pid_t, tty: String? = nil, path: String? = nil) -> ProcessEntry {
    ProcessEntry(pid: pid, parentPID: parent, tty: tty, executablePath: path)
}

/// From the agent's process up to the terminal app it runs in.
@Suite struct TerminalLocatorTests {
    let bundleIDs: [String: String] = [
        "/System/Applications/Utilities/Terminal.app": "com.apple.Terminal",
        "/Applications/iTerm.app": "com.googlecode.iterm2",
        "/Applications/Visual Studio Code.app": "com.microsoft.VSCode",
        "/Applications/Cursor.app": "com.todesktop.230313mzl4w4u92",
        "/Applications/Ghostty.app": "com.mitchellh.ghostty",
        "/Applications/Warp.app": "dev.warp.Warp-Stable",
    ]

    func locate(_ pid: pid_t, _ table: FakeProcessTable) -> TerminalTarget? {
        TerminalLocator.locate(pid: pid, table: table) { bundleIDs[$0.path] }
    }

    @Test func terminalAppIsFoundThroughTheShellAndLogin() throws {
        let table = FakeProcessTable(
            process(500, parent: 400, tty: "ttys003", path: "/Users/x/.local/bin/claude"),
            process(400, parent: 300, tty: "ttys003", path: "/bin/zsh"),
            process(300, parent: 200, tty: "ttys003", path: "/usr/bin/login"),
            process(200, parent: 1, path: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal")
        )
        let target = try #require(locate(500, table))
        #expect(target.kind == .terminal)
        #expect(target.app.path == "/System/Applications/Utilities/Terminal.app")
        #expect(target.tty == "/dev/ttys003")
    }

    @Test func iTermIsFoundThroughItsServerProcess() throws {
        let table = FakeProcessTable(
            process(500, parent: 400, tty: "ttys011", path: "/opt/homebrew/bin/node"),
            process(400, parent: 350, tty: "ttys011", path: "/bin/zsh"),
            process(350, parent: 1, path: "/Applications/iTerm.app/Contents/MacOS/iTermServer-3.5.0")
        )
        let target = try #require(locate(500, table))
        #expect(target.kind == .iTerm)
        #expect(target.app.path == "/Applications/iTerm.app")
        #expect(target.tty == "/dev/ttys011")
    }

    @Test func anEditorsTerminalLeadsToTheEditorAppNotItsHelper() throws {
        let table = FakeProcessTable(
            process(500, parent: 400, tty: "ttys020", path: "/Users/x/.local/bin/claude"),
            process(400, parent: 300, tty: "ttys020", path: "/bin/zsh"),
            process(300, parent: 200, path: "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper (Plugin).app/Contents/MacOS/Code Helper (Plugin)"),
            process(200, parent: 1, path: "/Applications/Visual Studio Code.app/Contents/MacOS/Electron")
        )
        let target = try #require(locate(500, table))
        #expect(target.kind == .editor)
        #expect(target.app.path == "/Applications/Visual Studio Code.app")
    }

    @Test(arguments: [
        ("/Applications/Cursor.app/Contents/MacOS/Cursor", "/Applications/Cursor.app", TerminalTarget.Kind.editor),
        ("/Applications/Ghostty.app/Contents/MacOS/ghostty", "/Applications/Ghostty.app", .other),
        ("/Applications/Warp.app/Contents/MacOS/stable", "/Applications/Warp.app", .other),
        ("/Applications/Unknown Term.app/Contents/MacOS/term", "/Applications/Unknown Term.app", .other),
    ])
    func otherAppsAreFoundAndOnlyEditorsAreTold(path: String, app: String, kind: TerminalTarget.Kind) throws {
        let table = FakeProcessTable(process(500, parent: 400, tty: "ttys001", path: "/bin/codex"), process(400, parent: 1, path: path))
        let target = try #require(locate(500, table))
        #expect(target.app.path == app)
        #expect(target.kind == kind)
    }

    @Test func aSessionInsideTmuxOrAnyDaemonHasNoTerminalToFind() {
        let table = FakeProcessTable(
            process(500, parent: 400, tty: "ttys005", path: "/bin/claude"),
            process(400, parent: 300, tty: "ttys005", path: "/bin/zsh"),
            process(300, parent: 1, path: "/opt/homebrew/bin/tmux")
        )
        #expect(locate(500, table) == nil)
    }

    @Test func aMissingProcessOrNoPidFindsNothing() {
        let table = FakeProcessTable(process(500, parent: 400, path: "/bin/claude"))
        #expect(locate(500, table) == nil)
        #expect(locate(9, table) == nil)
        #expect(locate(1, table) == nil)
        #expect(locate(0, table) == nil)
        #expect(locate(-3, table) == nil)
    }

    @Test func aLoopInTheTableEndsTheSearch() {
        let table = FakeProcessTable(process(500, parent: 400, path: "/bin/a"), process(400, parent: 500, path: "/bin/b"))
        #expect(locate(500, table) == nil)
    }

    @Test func aChainLongerThanTheLimitEndsTheSearch() {
        var entries = (1...40).map { process(pid_t(1_000 + $0), parent: pid_t(1_001 + $0), path: "/bin/p\($0)") }
        entries.append(process(1_041, parent: 1, path: "/Applications/Ghostty.app/Contents/MacOS/ghostty"))
        var table = FakeProcessTable()
        for entry in entries { table.entries[entry.pid] = entry }
        #expect(locate(1_001, table) == nil)
        #expect(locate(pid_t(1_041 - TerminalLocator.maxDepth + 1), table) != nil)
    }

    @Test func theTtyIsTheNearestOnesAndANameThatIsNotADeviceIsIgnored() throws {
        let table = FakeProcessTable(
            process(500, parent: 400, tty: nil, path: "/bin/claude"),
            process(400, parent: 300, tty: "ttys007", path: "/bin/zsh"),
            process(300, parent: 200, tty: "ttys008", path: "/usr/bin/login"),
            process(200, parent: 1, path: "/Applications/iTerm.app/Contents/MacOS/iTerm2")
        )
        #expect(try #require(locate(500, table)).tty == "/dev/ttys007")
        for bad in ["ttys0\" & quit", "../../etc/passwd", "ttys 1", "", "console", "tty"] {
            let table = FakeProcessTable(
                process(500, parent: 400, tty: bad, path: "/bin/claude"),
                process(400, parent: 1, path: "/Applications/iTerm.app/Contents/MacOS/iTerm2")
            )
            #expect(try #require(locate(500, table)).tty == nil, "\(bad)")
        }
    }

    @Test func anAgentInsideAnAppIsThatAppsOwn() throws {
        let table = FakeProcessTable(process(500, parent: 1, path: "/Applications/Codex.app/Contents/Resources/codex"))
        #expect(try #require(locate(500, table)).app.path == "/Applications/Codex.app")
    }

    @Test func aFolderThatMerelyLooksLikeAnAppIsNotOne() {
        let table = FakeProcessTable(process(500, parent: 1, path: "/Users/x/Foo.app.bak/bin/claude"))
        #expect(locate(500, table) == nil)
        #expect(TerminalLocator.appBundle(containing: "/Users/x/NotAnApp/bin/x") == nil)
        #expect(TerminalLocator.appBundle(containing: "/x.app/y")?.path == "/x.app")
        #expect(TerminalLocator.appBundle(containing: nil) == nil)
    }

    @Test func theKindComesFromTheBundleIdentifier() {
        #expect(TerminalLocator.kind(of: "com.apple.Terminal") == .terminal)
        #expect(TerminalLocator.kind(of: "com.googlecode.iterm2") == .iTerm)
        #expect(TerminalLocator.kind(of: "com.microsoft.VSCode") == .editor)
        #expect(TerminalLocator.kind(of: "com.microsoft.VSCodeInsiders") == .editor)
        #expect(TerminalLocator.kind(of: "com.todesktop.230313mzl4w4u92") == .editor)
        #expect(TerminalLocator.kind(of: "com.mitchellh.ghostty") == .other)
        #expect(TerminalLocator.kind(of: nil) == .other)
    }
}

@Suite struct SystemProcessTableTests {
    /// Reads only the process running the tests and its parents.
    @Test func itKnowsTheRunningProcessAndItsParent() throws {
        let entry = try #require(SystemProcessTable().entry(pid: getpid()))
        #expect(entry.pid == getpid())
        #expect(entry.parentPID == getppid())
        #expect(entry.executablePath?.hasPrefix("/") == true)
    }

    @Test func aPidThatIsNotThereIsNoEntry() {
        #expect(SystemProcessTable().entry(pid: 0) == nil)
        #expect(SystemProcessTable().entry(pid: -1) == nil)
        #expect(SystemProcessTable().entry(pid: 2_000_000_000) == nil)
    }

    @Test func theChainFromTheTestProcessEndsAtTheInitProcessWithoutLooping() {
        var pid = getpid()
        var seen: Set<pid_t> = []
        while pid > 1, let entry = SystemProcessTable().entry(pid: pid), seen.insert(pid).inserted, seen.count < 64 { pid = entry.parentPID }
        #expect(seen.count < 64)
    }
}
