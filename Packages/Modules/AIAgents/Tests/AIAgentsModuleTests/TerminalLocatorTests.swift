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
        "/Applications/WezTerm.app": "com.github.wez.wezterm",
        "/Applications/Claude.app": "com.anthropic.claudefordesktop",
        "/Applications/Codex.app": "com.openai.codex",
    ]
    let iTermServer = "/Users/x/Library/Application Support/iTerm2/iTermServer-3.5.0"

    /// `running` are the app folders that are running apps; all the known ones unless a test says which.
    func find(_ pid: pid_t, _ table: FakeProcessTable, running: Set<String>? = nil) -> TerminalLocator.Found {
        let running = running ?? Set(bundleIDs.keys)
        let ids = bundleIDs
        return TerminalLocator(
            table: table, bundleIdentifier: { ids[$0.path] }, isRunning: { running.contains($0.path) },
            runningApp: { id in ids.first { running.contains($0.key) && $0.value == id }.map { URL(filePath: $0.key, directoryHint: .isDirectory) } }
        ).find(pid: pid)
    }

    func locate(_ pid: pid_t, _ table: FakeProcessTable, running: Set<String>? = nil) -> TerminalTarget? {
        find(pid, table, running: running).target
    }

    // MARK: Terminal.app and iTerm2

    /// The shape of a real Terminal.app tab, read from the process table: zsh on the tab's tty, the root-owned `login` and the app.
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

    /// iTerm2 runs the jobs of its sessions in `iTermServer`, a copy in its Application Support folder, outside the app bundle and
    /// outliving it (its parent is launchd): the chain from the agent never meets the `.app`.
    @Test func iTermIsFoundThroughItsServerThatLivesOutsideTheApp() throws {
        let table = FakeProcessTable(
            process(500, parent: 400, tty: "ttys011", path: "/opt/homebrew/bin/node"),
            process(400, parent: 300, tty: "ttys011", path: "/bin/zsh"),
            process(300, parent: 200, tty: "ttys011", path: "/usr/bin/login"),
            process(200, parent: 1, path: iTermServer)
        )
        let target = try #require(locate(500, table))
        #expect(target.kind == .iTerm)
        #expect(target.app.path == "/Applications/iTerm.app")
        #expect(target.tty == "/dev/ttys011")
    }

    @Test func iTermIsFoundWhicheverWayTheServerSitsBetweenTheShellAndLaunchd() throws {
        for chain in [
            [process(500, parent: 400, tty: "ttys011", path: "/bin/claude"), process(400, parent: 200, tty: "ttys011", path: "/bin/zsh"), process(200, parent: 1, path: iTermServer)],
            [process(500, parent: 400, tty: "ttys011", path: "/bin/claude"), process(400, parent: 300, tty: "ttys011", path: "/bin/zsh"), process(300, parent: 200, path: iTermServer), process(200, parent: 1, path: "/Applications/iTerm.app/Contents/MacOS/iTerm2")],
        ] {
            var table = FakeProcessTable()
            for entry in chain { table.entries[entry.pid] = entry }
            let target = try #require(locate(500, table))
            #expect(target.kind == .iTerm)
            #expect(target.tty == "/dev/ttys011")
        }
    }

    @Test func aServerOfAnITermThatIsNotRunningIsNotATerminalToFind() {
        let table = FakeProcessTable(process(500, parent: 400, tty: "ttys011", path: "/bin/claude"), process(400, parent: 1, path: iTermServer))
        let found = find(500, table, running: [])
        #expect(found.target == nil)
        #expect(found.tty == "/dev/ttys011")
    }

    @Test func theServerIsRecognisedByItsNameWhereverItLives() {
        #expect(TerminalLocator.isITermServer("/Users/x/Library/Application Support/iTerm2/iTermServer-3.5.0"))
        #expect(TerminalLocator.isITermServer("/Applications/iTerm.app/Contents/MacOS/iTermServer-3.4.20"))
        #expect(TerminalLocator.isITermServer("/tmp/iTermServer"))
        #expect(!TerminalLocator.isITermServer("/usr/bin/login"))
        #expect(!TerminalLocator.isITermServer("/tmp/myiTermServer"))
        #expect(!TerminalLocator.isITermServer("/tmp/iTermServer/inside/zsh"))
        #expect(!TerminalLocator.isITermServer(nil))
        #expect(!TerminalLocator.isITermServer(""))
    }

    // MARK: Editors and other terminals

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
        ("/Applications/WezTerm.app/Contents/MacOS/wezterm-gui", "/Applications/WezTerm.app", .other),
        ("/Applications/Unknown Term.app/Contents/MacOS/term", "/Applications/Unknown Term.app", .other),
    ])
    func otherAppsAreFoundAndOnlyEditorsAreTold(path: String, app: String, kind: TerminalTarget.Kind) throws {
        let table = FakeProcessTable(process(500, parent: 400, tty: "ttys001", path: "/bin/codex"), process(400, parent: 1, path: path))
        let target = try #require(locate(500, table, running: [app]))
        #expect(target.app.path == app)
        #expect(target.kind == kind)
    }

    /// Ghostty on macOS starts the shell through `login` (its configuration reference says so), like Terminal.app does.
    @Test func ghosttyIsFoundThroughLogin() throws {
        let table = FakeProcessTable(
            process(500, parent: 400, tty: "ttys002", path: "/bin/claude"), process(400, parent: 300, tty: "ttys002", path: "/bin/zsh"),
            process(300, parent: 200, tty: "ttys002", path: "/usr/bin/login"),
            process(200, parent: 1, path: "/Applications/Ghostty.app/Contents/MacOS/ghostty")
        )
        let target = try #require(locate(500, table))
        #expect(target.app.path == "/Applications/Ghostty.app")
        #expect(target.kind == .other)
    }

    /// Warp, WezTerm and any terminal that runs its jobs in a helper or a daemon from inside its own bundle are found by that
    /// bundle, as long as the app is running; their process trees are not documented, so only where the binaries live is used.
    @Test func aJobHostInsideTheBundleOfARunningAppIsThatApp() throws {
        for (host, app) in [
            ("/Applications/Warp.app/Contents/MacOS/stable", "/Applications/Warp.app"),
            ("/Applications/WezTerm.app/Contents/MacOS/wezterm-mux-server", "/Applications/WezTerm.app"),
        ] {
            let table = FakeProcessTable(
                process(500, parent: 400, tty: "ttys004", path: "/bin/claude"), process(400, parent: 300, tty: "ttys004", path: "/bin/zsh"),
                process(300, parent: 1, path: host)
            )
            #expect(try #require(locate(500, table)).app.path == app)
            #expect(locate(500, table, running: []) == nil)
        }
    }

    /// The shape of a real session of the Claude desktop app, read from the process table: the `claude` it downloads is itself in
    /// an `.app` folder, but it is not a running app, so the walk goes on to the app above it.
    @Test func aToolInsideAnAppFolderThatIsNotARunningAppDoesNotStandInForTheTerminal() throws {
        let table = FakeProcessTable(
            process(500, parent: 480, path: "/Users/x/Library/Application Support/Claude/claude-code/2.1.295/9d6405864fdc/claude.app/Contents/MacOS/claude"),
            process(480, parent: 470, path: "/Applications/Claude.app/Contents/Helpers/disclaimer"),
            process(470, parent: 1, path: "/Applications/Claude.app/Contents/MacOS/Claude")
        )
        let target = try #require(locate(500, table))
        #expect(target.app.path == "/Applications/Claude.app")
        #expect(target.kind == .other)
        #expect(target.tty == nil)
    }

    @Test func theTerminalInsideAnotherAppIsThatApp() throws {
        let table = FakeProcessTable(
            process(500, parent: 400, tty: "ttys001", path: "/bin/claude"), process(400, parent: 300, tty: "ttys001", path: "/bin/zsh"),
            process(300, parent: 200, path: "/Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper"),
            process(200, parent: 1, path: "/Applications/Claude.app/Contents/MacOS/Claude")
        )
        let target = try #require(locate(500, table))
        #expect(target.app.path == "/Applications/Claude.app")
        #expect(target.tty == "/dev/ttys001")
    }

    // MARK: No app above the agent

    @Test func aSessionInsideTmuxOrAnyDaemonHasNoAppButKeepsItsTty() {
        let table = FakeProcessTable(
            process(500, parent: 400, tty: "ttys005", path: "/bin/claude"),
            process(400, parent: 300, tty: "ttys005", path: "/bin/zsh"),
            process(300, parent: 1, path: "/opt/homebrew/bin/tmux")
        )
        let found = find(500, table)
        #expect(found.target == nil)
        #expect(found.tty == "/dev/ttys005")
    }

    @Test func aMissingProcessOrNoPidFindsNothing() {
        let table = FakeProcessTable(process(500, parent: 400, path: "/bin/claude"))
        #expect(find(500, table) == TerminalLocator.Found(target: nil, tty: nil))
        #expect(find(9, table) == TerminalLocator.Found(target: nil, tty: nil))
        #expect(find(1, table) == TerminalLocator.Found(target: nil, tty: nil))
        #expect(find(0, table) == TerminalLocator.Found(target: nil, tty: nil))
        #expect(find(-3, table) == TerminalLocator.Found(target: nil, tty: nil))
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
            let found = find(500, table)
            #expect(try #require(found.target).tty == nil, "\(bad)")
            #expect(found.tty == nil, "\(bad)")
        }
    }

    @Test func anAgentInsideARunningAppIsThatAppsOwn() throws {
        let table = FakeProcessTable(process(500, parent: 1, path: "/Applications/Codex.app/Contents/Resources/codex"))
        #expect(try #require(locate(500, table, running: ["/Applications/Codex.app"])).app.path == "/Applications/Codex.app")
        #expect(locate(500, table, running: []) == nil)
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

    /// `login` between a terminal app and the shell belongs to root, and `proc_pidinfo` refuses it; the kernel's process list, which
    /// `ps` reads, does not. The init process is root's too.
    @Test func aProcessOfAnotherUserIsReadableToo() throws {
        let launchd = try #require(SystemProcessTable().entry(pid: 1))
        #expect(launchd.parentPID == 0)
        #expect(launchd.executablePath == "/sbin/launchd")
        #expect(launchd.tty == nil)
    }

    @Test func aPidThatIsNotThereIsNoEntry() {
        #expect(SystemProcessTable().entry(pid: 0) == nil)
        #expect(SystemProcessTable().entry(pid: -1) == nil)
        #expect(SystemProcessTable().entry(pid: 2_000_000_000) == nil)
    }

    @Test func theChainFromTheTestProcessReachesTheInitProcessWithoutLooping() {
        var pid = getpid()
        var seen: Set<pid_t> = []
        var reachedInit = false
        while let entry = SystemProcessTable().entry(pid: pid), seen.insert(pid).inserted, seen.count < 64 {
            if pid == 1 { reachedInit = true }
            pid = entry.parentPID
        }
        #expect(reachedInit)
    }

    /// A pseudo-terminal of the test's own, which no terminal app owns: the name of its device is what the table would report.
    @Test func aTerminalDeviceIsNamedLikeTheTabsTty() throws {
        let master = posix_openpt(O_RDWR | O_NOCTTY)
        try #require(master >= 0)
        defer { close(master) }
        try #require(grantpt(master) == 0 && unlockpt(master) == 0)
        let path = String(cString: try #require(ptsname(master)))
        var status = stat()
        try #require(stat(path, &status) == 0)
        #expect("/dev/" + (SystemProcessTable.ttyName(of: status.st_rdev) ?? "") == path)
        #expect(TerminalScript.isDevicePath(path))
        #expect(SystemProcessTable.ttyName(of: -1) == nil)
    }
}
