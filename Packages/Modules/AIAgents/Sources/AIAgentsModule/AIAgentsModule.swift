import AgentHookKit
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
    /// Listens for the hook helper, which tells exactly when an agent waits for you.
    let preciseStatus: SettingKey<Bool>

    init(_ settings: ModuleSettings) {
        claudeEnabled = settings.key("claudeEnabled", default: true)
        codexEnabled = settings.key("codexEnabled", default: true)
        showWorkingActivity = settings.key("showWorkingActivity", default: true)
        finishedSeconds = settings.key("finishedSeconds", default: 5, clampedTo: Self.finishedSecondsRange)
        preciseStatus = settings.key("preciseStatus", default: false)
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
    /// Nil is the real installer, which needs the module's storage and so is made with the Settings rows.
    private let hookSetup: HookSetup?
    /// Where the hook socket is; nil is the standard place in the module's storage.
    private let socketPath: String?
    private var context: ModuleContext?
    /// One per agent that is turned on, so turning one off or on leaves the other alone.
    private var watchers: [AgentSource: AgentWatcher] = [:]
    /// Set while the setting `preciseStatus` is on and the socket could be opened.
    private var eventServer: AgentEventServer?
    /// The socket could not be opened; it is tried again only after the setting was switched off and on.
    private var listenFailed = false
    /// What the Settings rows say about that.
    let hookListenStatus = HookListenStatus()
    /// Kept here because the Settings rows are built again whenever the page refreshes, which would reset its message.
    private var hookModel: HookSetupModel?

    /// Reads the real `~/.claude` and `~/.codex`.
    public convenience init() {
        let roots = Self.defaultRoots(home: FileManager.default.homeDirectoryForCurrentUser)
        self.init(fileSystem: LocalAgentFileSystem(), claudeRoot: roots.claude, codexRoot: roots.codex, opener: .system)
    }

    /// For tests: a fake file system, temporary roots, an opener that opens nothing, and the socket and installer
    /// they use instead of the real ones.
    init(
        fileSystem: any AgentFileSystem, claudeRoot: URL, codexRoot: URL, opener: AgentOpener,
        hookSetup: HookSetup? = nil, socketPath: String? = nil
    ) {
        self.fileSystem = fileSystem
        self.claudeRoot = claudeRoot
        self.codexRoot = codexRoot
        self.opener = opener
        self.hookSetup = hookSetup
        self.socketPath = socketPath
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

    /// Stops reading the agents' files and listening for the hooks.
    func stopWatching() {
        for watcher in watchers.values { watcher.stop() }
        watchers = [:]
        eventServer?.stop()
        eventServer = nil
        listenFailed = false
        hookListenStatus.failure = nil
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
            finishedSeconds: environment.settings.binding(keys.finishedSeconds),
            preciseStatus: environment.settings.binding(keys.preciseStatus),
            hooks: hookSetupModel(for: environment),
            listenStatus: hookListenStatus
        ))
    }

    /// Installing hooks turns `preciseStatus` on, since hooks that nothing listens to do nothing.
    func hookSetupModel(for environment: ModuleSettingsEnvironment) -> HookSetupModel {
        if let hookModel { return hookModel }
        let storage = environment.storage.directory
        let settings = environment.settings
        let preciseStatus = AIAgentsSettingsKeys(settings).preciseStatus
        let model = HookSetupModel(
            setup: hookSetup ?? .system(storageDirectory: storage),
            pluginDirectory: storage.appending(path: "claude-plugin", directoryHint: .isDirectory),
            didInstall: { settings.set(true, for: preciseStatus) }
        )
        hookModel = model
        return model
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
        var preciseStatus: Bool
    }

    private static func inputs(store: AgentSessionStore, settings: ModuleSettings, keys: AIAgentsSettingsKeys) -> Inputs {
        Inputs(
            activity: AgentActivityContent(sessions: store.sessions.values, showWorking: settings.value(keys.showWorkingActivity)),
            claudeEnabled: settings.value(keys.claudeEnabled),
            codexEnabled: settings.value(keys.codexEnabled),
            finishedSeconds: settings.value(keys.finishedSeconds),
            preciseStatus: settings.value(keys.preciseStatus)
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
        listen(settings.value(keys.preciseStatus), store: store, context: context)
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

    /// Starts or stops the socket the hook helper sends to. Its events win over what the transcripts suggest.
    private func listen(_ enabled: Bool, store: AgentSessionStore, context: ModuleContext) {
        guard enabled else {
            eventServer?.stop()
            eventServer = nil
            listenFailed = false
            hookListenStatus.failure = nil
            return
        }
        guard eventServer == nil, !listenFailed else { return }
        let path = socketPath ?? AgentSocket.path(inStorageDirectory: context.storage.directory)
        let settings = context.settings
        let keys = AIAgentsSettingsKeys(settings)
        let server = AgentEventServer(directory: URL(filePath: path).deletingLastPathComponent()) { [weak store] payload in
            // Read when the event arrives, so an agent turned off since the socket opened stays quiet.
            let events = payload.agentEvents.filter { settings.value($0.source == .claude ? keys.claudeEnabled : keys.codexEnabled) }
            if !events.isEmpty { store?.apply(events, fromHooks: true) }
        }
        do {
            try server.start()
            eventServer = server
            hookListenStatus.failure = nil
        } catch {
            listenFailed = true
            hookListenStatus.failure = HookListenStatus.failureMessage
            context.logger.error("Cannot listen for agent hooks: \(String(describing: error), privacy: .public)")
        }
    }

    private func publish(_ content: AgentActivityContent?) {
        guard let context, content != publishedActivity else { return }
        publishedActivity = content
        guard let content else {
            context.activities.clear(id: Self.activityID)
            return
        }
        // The finished check is a notice: with an expiry it takes the notch for its few seconds and playing media steps
        // back in. The store's own timer stays, since it also ends the session's finished state; whichever of the two
        // comes first clears the activity.
        let lifetime: Duration? = content.kind == .finished
            ? .seconds(context.settings.value(AIAgentsSettingsKeys(context.settings).finishedSeconds)) : nil
        context.activities.set(LiveActivity(
            id: Self.activityID,
            priority: content.priority,
            expiresAfter: lifetime,
            leading: AnyView(AgentActivityLeading(content: content)),
            trailing: AnyView(AgentActivityTrailing(content: content))
        ))
    }
}
