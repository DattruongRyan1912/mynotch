import AppKit
import Foundation

/// Brings the terminal a session runs in to the front. It selects the right tab in Terminal.app and iTerm2, opens the
/// folder in VS Code and Cursor, and only activates any other app. It never types into a terminal and never starts an app
/// that is not already running. All of what it does to the machine is behind closures, so tests run none of it.
struct TerminalJumper {
    enum Outcome: Equatable {
        /// The tab with the session's tty was selected and its app is in front.
        case selectedTab
        case activatedApp
        /// An editor opened the session's folder.
        case openedFolder
        /// The app is in front but its tab was not picked: macOS has not allowed MyNotch to control it.
        case activatedAppWithoutAutomation
        /// No terminal app was found for the session, so nothing was done.
        case notFound
    }

    var processTable: any ProcessTable
    var bundleIdentifier: (URL) -> String?
    var runner: any AppleScriptRunning
    var isRunning: (URL) -> Bool
    var activate: (URL) -> Void
    /// Opens a folder in an app.
    var open: (_ folder: URL, _ app: URL) -> Void

    /// - Parameters:
    ///   - pid: the agent's process.
    ///   - folder: the session's folder, if it exists, for an editor to open.
    func jump(pid: pid_t?, folder: URL?) async -> Outcome {
        guard let pid, let target = TerminalLocator.locate(pid: pid, table: processTable, bundleIdentifier: bundleIdentifier),
              isRunning(target.app)
        else { return .notFound }
        switch target.kind {
        case .terminal, .iTerm:
            guard let tty = target.tty, let script = TerminalScript.selectTab(of: target.kind, tty: tty) else {
                activate(target.app)
                return .activatedApp
            }
            let result = await runner.run(script)
            activate(target.app)
            switch result {
            case .value(TerminalScript.found): return .selectedTab
            case .notPermitted: return .activatedAppWithoutAutomation
            case .value, .failed: return .activatedApp
            }
        case .editor:
            guard let folder else {
                activate(target.app)
                return .activatedApp
            }
            open(folder, target.app)
            return .openedFolder
        case .other:
            activate(target.app)
            return .activatedApp
        }
    }

    /// Does nothing and finds nothing: what a module made for a test has, so no test touches the real process table or a real
    /// terminal.
    static let inert = TerminalJumper(
        processTable: EmptyProcessTable(), bundleIdentifier: { _ in nil }, runner: InertRunner(), isRunning: { _ in false },
        activate: { _ in }, open: { _, _ in }
    )

    /// The real machine: the process table, the bundle's identifier, `NSAppleScript`, and `NSWorkspace` for the apps.
    static let system = TerminalJumper(
        processTable: SystemProcessTable(),
        bundleIdentifier: { Bundle(url: $0)?.bundleIdentifier },
        runner: SystemAppleScriptRunner(),
        isRunning: { app in NSWorkspace.shared.runningApplications.contains { isSameApp($0.bundleURL, app) } },
        activate: { app in NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration()) { _, _ in } },
        open: { folder, app in NSWorkspace.shared.open([folder], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, _ in } }
    )
}

extension TerminalJumper {
    /// Two URLs of an app folder, with or without the closing slash and through links, are the same app.
    static func isSameApp(_ a: URL?, _ b: URL) -> Bool {
        guard let a else { return false }
        return a.resolvingSymlinksInPath().path == b.resolvingSymlinksInPath().path
    }
}

private nonisolated struct EmptyProcessTable: ProcessTable {
    func entry(pid: pid_t) -> ProcessEntry? { nil }
}

private nonisolated struct InertRunner: AppleScriptRunning {
    func run(_ source: String) async -> AppleScriptResult { .failed }
}
