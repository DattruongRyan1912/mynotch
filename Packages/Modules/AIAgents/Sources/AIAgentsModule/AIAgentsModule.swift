import Foundation
import MyNotchCore
import NotchUI
import Observation
import SwiftUI

/// Setting names and defaults in one place, shared by the running module and the Settings rows.
struct AIAgentsSettingsKeys {
    static let finishedSecondsRange = 2...30

    let claudeEnabled: SettingKey<Bool>
    let codexEnabled: SettingKey<Bool>
    /// Only the working activity: being asked something or told it is done always shows.
    let showWorkingActivity: SettingKey<Bool>
    /// How long the check mark of a finished turn stays.
    let finishedSeconds: SettingKey<Int>

    init(_ settings: ModuleSettings) {
        claudeEnabled = settings.key("claudeEnabled", default: true)
        codexEnabled = settings.key("codexEnabled", default: true)
        showWorkingActivity = settings.key("showWorkingActivity", default: true)
        finishedSeconds = settings.key("finishedSeconds", default: 5, clampedTo: Self.finishedSecondsRange)
    }
}

/// What the tab does with a session, without handing the views the module.
struct AgentTabActions {
    /// True when there was a folder to open.
    var openInTerminal: (String?) -> Bool
    var openFolder: (String?) -> Void
    var copyPath: (String?) -> Void
}

/// Claude Code and Codex in the notch: an activity while an agent works, waits for you or finishes, and an "AI"
/// tab that lists the sessions with today's usage. Everything comes from the agents' own files, read-only.
public final class AIAgentsModule: FeatureModule {
    public let descriptor = ModuleDescriptor(
        id: "aiagents",
        displayName: "AI agents",
        systemImage: "sparkles",
        defaultEnabled: true,
        order: 500
    )

    static let activityID = "agent"

    /// Set while running.
    private(set) var store: AgentSessionStore?
    /// What the published activity shows, nil while there is none. Compared before publishing, so the activity is
    /// set once per change instead of with every event.
    private(set) var publishedActivity: AgentActivityContent?

    private let fileSystem: any AgentFileSystem
    private let claudeRoot: URL
    private let codexRoot: URL
    private let opener: AgentOpener
    private var context: ModuleContext?
    /// One per agent that is turned on, so turning one off or on leaves the other alone.
    private var watchers: [AgentSource: AgentWatcher] = [:]

    /// Reads the real `~/.claude` and `~/.codex`.
    public convenience init() {
        let roots = Self.defaultRoots(home: FileManager.default.homeDirectoryForCurrentUser)
        self.init(fileSystem: LocalAgentFileSystem(), claudeRoot: roots.claude, codexRoot: roots.codex, opener: .system)
    }

    /// For tests: a fake file system, temporary roots and an opener that opens nothing.
    init(fileSystem: any AgentFileSystem, claudeRoot: URL, codexRoot: URL, opener: AgentOpener) {
        self.fileSystem = fileSystem
        self.claudeRoot = claudeRoot
        self.codexRoot = codexRoot
        self.opener = opener
    }

    static func defaultRoots(home: URL) -> (claude: URL, codex: URL) {
        (home.appending(path: ".claude", directoryHint: .isDirectory), home.appending(path: ".codex", directoryHint: .isDirectory))
    }

    public func start(_ context: ModuleContext) async throws(ModuleError) {
        let settings = context.settings
        let keys = AIAgentsSettingsKeys(settings)
        let store = AgentSessionStore(scheduler: context.scheduler, finishedSeconds: settings.value(keys.finishedSeconds))
        self.store = store
        self.context = context
        publishedActivity = nil
        refresh()
        context.run { [weak self] in
            for await _ in Observations({ Self.inputs(store: store, settings: settings, keys: keys) }) { self?.refresh() }
        }
    }

    public func stop() async {
        stopWatching()
        store = nil
        context = nil
        publishedActivity = nil
    }

    func stopWatching() {
        for watcher in watchers.values { watcher.stop() }
        watchers = [:]
    }

    public func makeTab() -> NotchTab? {
        guard let store else { return nil }
        return NotchTab(
            id: descriptor.id, title: "AI", systemImage: "sparkles", preferredHeight: 200,
            content: AnyView(AIAgentsTabView(store: store, actions: actions))
        )
    }

    public func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView? {
        let keys = AIAgentsSettingsKeys(environment.settings)
        return AnyView(AIAgentsSettingsView(
            claudeEnabled: environment.settings.binding(keys.claudeEnabled),
            codexEnabled: environment.settings.binding(keys.codexEnabled),
            showWorkingActivity: environment.settings.binding(keys.showWorkingActivity),
            finishedSeconds: environment.settings.binding(keys.finishedSeconds)
        ))
    }

    var actions: AgentTabActions {
        AgentTabActions(
            openInTerminal: { [weak self] in self?.openInTerminal(cwd: $0) ?? false },
            openFolder: { [weak self] in self?.openFolder(cwd: $0) },
            copyPath: { [weak self] in self?.copyPath(cwd: $0) }
        )
    }

    /// Opens a session's folder in Terminal; false when the session has no folder that exists.
    @discardableResult
    func openInTerminal(cwd: String?) -> Bool {
        guard let folder = AgentOpener.directory(for: cwd) else { return false }
        opener.openInTerminal(folder)
        return true
    }

    func openFolder(cwd: String?) {
        guard let folder = AgentOpener.directory(for: cwd) else { return }
        opener.openFolder(folder)
    }

    func copyPath(cwd: String?) {
        guard let cwd, !cwd.isEmpty else { return }
        opener.copy(cwd)
    }

    // MARK: Reacting

    /// What the module acts on. Read inside `Observations`, so a change to any of it runs `refresh`.
    private struct Inputs: Equatable, Sendable {
        var activity: AgentActivityContent?
        var claudeEnabled: Bool
        var codexEnabled: Bool
        var finishedSeconds: Int
    }

    private static func inputs(store: AgentSessionStore, settings: ModuleSettings, keys: AIAgentsSettingsKeys) -> Inputs {
        Inputs(
            activity: AgentActivityContent(sessions: store.sessions.values, showWorking: settings.value(keys.showWorkingActivity)),
            claudeEnabled: settings.value(keys.claudeEnabled),
            codexEnabled: settings.value(keys.codexEnabled),
            finishedSeconds: settings.value(keys.finishedSeconds)
        )
    }

    /// Brings the watchers and the activity in line with the settings and the sessions as they are now.
    private func refresh() {
        guard let context, let store else { return }
        let settings = context.settings
        let keys = AIAgentsSettingsKeys(settings)
        store.finishedSeconds = settings.value(keys.finishedSeconds)
        follow(.claude, settings.value(keys.claudeEnabled), store: store)
        follow(.codex, settings.value(keys.codexEnabled), store: store)
        publish(AgentActivityContent(sessions: store.sessions.values, showWorking: settings.value(keys.showWorkingActivity)))
    }

    /// Starts or stops reading one agent's files. Stopping also forgets its sessions, so they leave the tab and
    /// the activity at once; today's usage stays, since turning the agent on again reads its files again.
    private func follow(_ source: AgentSource, _ enabled: Bool, store: AgentSessionStore) {
        if enabled, watchers[source] == nil {
            let watcher = AgentWatcher(
                store: store, claudeRoot: source == .claude ? claudeRoot : nil, codexRoot: source == .codex ? codexRoot : nil,
                fileSystem: fileSystem
            )
            watchers[source] = watcher
            watcher.start()
        } else if !enabled, let watcher = watchers.removeValue(forKey: source) {
            watcher.stop()
            store.removeSessions(of: source)
        }
    }

    private func publish(_ content: AgentActivityContent?) {
        guard let context, content != publishedActivity else { return }
        publishedActivity = content
        guard let content else {
            context.activities.clear(id: Self.activityID)
            return
        }
        context.activities.set(LiveActivity(
            id: Self.activityID,
            priority: content.priority,
            leading: AnyView(AgentActivityLeading(content: content)),
            trailing: AnyView(AgentActivityTrailing(content: content))
        ))
    }
}
