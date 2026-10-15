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
    /// A short sound when an agent asks for permission and waits for you.
    let soundOnRequest: SettingKey<Bool>
    /// The hint about Automation permission has been shown; it is shown only once.
    let terminalHintShown: SettingKey<Bool>

    init(_ settings: ModuleSettings) {
        claudeEnabled = settings.key("claudeEnabled", default: true)
        codexEnabled = settings.key("codexEnabled", default: true)
        showWorkingActivity = settings.key("showWorkingActivity", default: true)
        finishedSeconds = settings.key("finishedSeconds", default: 5, clampedTo: Self.finishedSecondsRange)
        preciseStatus = settings.key("preciseStatus", default: false)
        soundOnRequest = settings.key("soundOnRequest", default: true)
        terminalHintShown = settings.key("terminalHintShown", default: false)
    }
}

/// What the tab does with a session, without handing the views the module.
struct AgentTabActions {
    /// Brings the session's terminal to the front. True when the notch may close: something was opened, and there is no
    /// hint left to read.
    var jump: (AgentSessionKey) async -> Bool
    var openFolder: (String?) -> Void
    var copyPath: (String?) -> Void
    /// Answers the permission request with this id.
    var decide: (String, PermissionAnswer) -> Void
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
    /// How much later than the store's timer the finished check expires on the center, so the store's timer, which the
    /// module follows, always acts first.
    static let finishedExpiryMargin = Duration.seconds(1)

    /// Set while running.
    private(set) var store: AgentSessionStore?
    /// What the published activity shows, nil while there is none. Compared before publishing, so the activity is
    /// set once per change instead of with every event.
    private(set) var publishedActivity: AgentActivityContent?

    private let fileSystem: any AgentFileSystem
    private let claudeRoot: URL
    private let codexRoot: URL
    private let opener: AgentOpener
    /// Finds a session's terminal and brings it to the front.
    private let jumper: TerminalJumper
    /// What the tab says after a click could not do all it should; shown once.
    let jumpHint = AgentJumpHint()
    /// Nil is the real installer, which needs the module's storage and so is made with the Settings rows.
    private let hookSetup: HookSetup?
    /// Where the hook socket is; nil is the standard place in the module's storage.
    private let socketPath: String?
    private var context: ModuleContext?
    /// One per agent that is turned on, so turning one off or on leaves the other alone.
    private var watchers: [AgentSource: AgentWatcher] = [:]
    /// Set while the setting `preciseStatus` is on and the socket could be opened.
    private var eventServer: AgentEventServer?
    /// Opened with `eventServer`: where the helper asks for permission and waits for the answer.
    private var permissionServer: PermissionServer?
    /// The requests waiting for the user. Set while running.
    private(set) var permissions: PermissionQueue?
    /// Plays the short sound of a request; tests give one that is silent.
    private let alert: @MainActor () -> Void
    /// The socket could not be opened; it is tried again only after the setting was switched off and on.
    private var listenFailed = false
    /// What the Settings rows say about that.
    let hookListenStatus = HookListenStatus()
    /// Kept here because the Settings rows are built again whenever the page refreshes, which would reset its message.
    private var hookModel: HookSetupModel?

    /// Reads the real `~/.claude` and `~/.codex`.
    public convenience init() {
        let roots = Self.defaultRoots(home: FileManager.default.homeDirectoryForCurrentUser)
        self.init(fileSystem: LocalAgentFileSystem(), claudeRoot: roots.claude, codexRoot: roots.codex, opener: .system, jumper: .system)
    }

    /// For tests: a fake file system, temporary roots, an opener that opens nothing, the socket and installer
    /// they use instead of the real ones, a sound that is not played, and a jumper that finds no terminal unless the test
    /// gives it a table and a fake machine.
    init(
        fileSystem: any AgentFileSystem, claudeRoot: URL, codexRoot: URL, opener: AgentOpener,
        hookSetup: HookSetup? = nil, socketPath: String? = nil, alert: @escaping @MainActor () -> Void = { AgentAlertSound.play() },
        jumper: TerminalJumper = .inert
    ) {
        self.fileSystem = fileSystem
        self.claudeRoot = claudeRoot
        self.codexRoot = codexRoot
        self.opener = opener
        self.jumper = jumper
        self.hookSetup = hookSetup
        self.socketPath = socketPath
        self.alert = alert
    }

    static func defaultRoots(home: URL) -> (claude: URL, codex: URL) {
        (home.appending(path: ".claude", directoryHint: .isDirectory), home.appending(path: ".codex", directoryHint: .isDirectory))
    }

    public func start(_ context: ModuleContext) async throws(ModuleError) {
        let settings = context.settings
        let keys = AIAgentsSettingsKeys(settings)
        let store = AgentSessionStore(scheduler: context.scheduler, finishedSeconds: settings.value(keys.finishedSeconds))
        let permissions = PermissionQueue(scheduler: context.scheduler)
        self.store = store
        self.permissions = permissions
        self.context = context
        publishedActivity = nil
        refresh()
        context.run { [weak self] in
            for await _ in Observations({ Self.inputs(store: store, permissions: permissions, settings: settings, keys: keys) }) { self?.refresh() }
        }
    }

    public func stop() async {
        stopWatching()
        store = nil
        permissions = nil
        context = nil
        publishedActivity = nil
    }

    /// Stops reading the agents' files and listening for the hooks.
    func stopWatching() {
        for watcher in watchers.values { watcher.stop() }
        watchers = [:]
        stopListening()
    }

    /// Closes both sockets. Requests still waiting are told to let the agent ask in its terminal, first: once the
    /// socket is closed there is no way to tell them.
    private func stopListening() {
        permissions?.cancelAll()
        permissionServer?.stop()
        permissionServer = nil
        eventServer?.stop()
        eventServer = nil
        listenFailed = false
        hookListenStatus.failure = nil
    }

    public func makeTab() -> NotchTab? {
        guard let store, let permissions else { return nil }
        return NotchTab(
            id: descriptor.id, title: "AI", systemImage: "sparkles", preferredHeight: 200,
            content: AnyView(AIAgentsTabView(store: store, permissions: permissions, actions: actions, hint: jumpHint))
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
            soundOnRequest: environment.settings.binding(keys.soundOnRequest),
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
            jump: { [weak self] in await self?.jump(to: $0) ?? false },
            openFolder: { [weak self] in self?.openFolder(cwd: $0) },
            copyPath: { [weak self] in self?.copyPath(cwd: $0) },
            decide: { [weak self] in self?.decide($0, $1) }
        )
    }

    /// Brings the terminal the session runs in to the front: the tab in Terminal.app and iTerm2, the folder in an editor, the app
    /// for any other. When none is found (the session has no known process, or runs under tmux) the folder opens in Terminal as it
    /// always did. True when the notch may close; false when nothing could be opened, or when a hint was just put in the tab.
    func jump(to key: AgentSessionKey) async -> Bool {
        let session = store?.sessions[key]
        switch await jumper.jump(pid: session?.pid, folder: AgentOpener.directory(for: session?.cwd)) {
        case .notFound: return openInTerminal(cwd: session?.cwd)
        case .notFoundWithoutAutomation:
            // A running terminal could not be asked: the folder opens as for any session that has none, and the hint says why.
            let opened = openInTerminal(cwd: session?.cwd)
            return showAutomationHint() ? false : opened
        case .activatedAppWithoutAutomation: return !showAutomationHint()
        case .selectedTab, .activatedApp, .openedFolder: return true
        }
    }

    /// Shown the first time only: without the Automation permission the app comes to the front but not the right tab.
    private func showAutomationHint() -> Bool {
        guard let context else { return false }
        let shown = AIAgentsSettingsKeys(context.settings).terminalHintShown
        guard !context.settings.value(shown) else { return false }
        context.settings.set(true, for: shown)
        jumpHint.message = AgentJumpHint.automationDenied
        return true
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

    // MARK: Permission requests

    /// The user's answer to the request with this id: it goes to the helper that asked, and the session shows what it
    /// does next. An id that is not pending (already answered, or gone) changes nothing.
    func decide(_ id: String, _ answer: PermissionAnswer) {
        guard let permissions, let request = permissions.pending.first(where: { $0.id == id }), permissions.decide(id, answer) else { return }
        // Allowed, the tool runs; denied, the agent goes on thinking. Asked in the terminal, the session still waits, for
        // the answer there. Without this the card would be gone while the session still said "waiting" until the next hook.
        guard answer != .ask, let store, store.sessions[request.key] != nil else { return }
        let kind: AgentEvent.Kind = answer == .allow ? .toolStarted(name: request.tool, summary: request.summary) : .toolFinished
        store.apply([AgentEvent(source: request.source, sessionID: request.key.sessionID, timestamp: nil, kind: kind)], fromHooks: true)
    }

    /// A helper asks for permission. The agent must be one that is turned on; the card and the sound come with the request.
    private func receive(_ payload: HookPayload, over connection: PermissionConnection) {
        guard let store, let permissions, let context, let source = AgentSource(rawValue: payload.source) else {
            connection.reply(.ask)
            return
        }
        let keys = AIAgentsSettingsKeys(context.settings)
        guard context.settings.value(source == .claude ? keys.claudeEnabled : keys.codexEnabled),
              let request = permissions.add(payload, respond: { connection.reply($0) })
        else {
            connection.reply(.ask)
            return
        }
        // The helper leaves when the user answers in the terminal or the agent stops: the card has no one to answer.
        connection.onPeerClosed { [weak permissions] in permissions?.withdraw(request.id) }
        store.apply(payload.agentEvents, fromHooks: true)
        if context.settings.value(keys.soundOnRequest) { alert() }
    }

    /// The session went on, so its requests that still wait on the notch are over.
    private func settlePermissions(after payload: HookPayload) {
        guard payload.settlesPermissionRequests, let source = AgentSource(rawValue: payload.source) else { return }
        permissions?.settle(AgentSessionKey(source: source, sessionID: payload.sessionID), tool: payload.event == "PostToolUse" ? payload.tool : nil)
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

    private static func inputs(store: AgentSessionStore, permissions: PermissionQueue, settings: ModuleSettings, keys: AIAgentsSettingsKeys) -> Inputs {
        Inputs(
            activity: AgentActivityContent(
                sessions: store.sessions.values, showWorking: settings.value(keys.showWorkingActivity), pending: permissions.pending
            ),
            claudeEnabled: settings.value(keys.claudeEnabled),
            codexEnabled: settings.value(keys.codexEnabled),
            finishedSeconds: settings.value(keys.finishedSeconds),
            preciseStatus: settings.value(keys.preciseStatus)
        )
    }

    /// Brings the watchers and the activity in line with the settings and the sessions as they are now.
    private func refresh() {
        guard let context, let store, let permissions else { return }
        let settings = context.settings
        let keys = AIAgentsSettingsKeys(settings)
        store.finishedSeconds = settings.value(keys.finishedSeconds)
        follow(.claude, settings.value(keys.claudeEnabled), store: store)
        follow(.codex, settings.value(keys.codexEnabled), store: store)
        listen(settings.value(keys.preciseStatus), store: store, context: context)
        publish(AgentActivityContent(
            sessions: store.sessions.values, showWorking: settings.value(keys.showWorkingActivity), pending: permissions.pending
        ))
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
            stopListening()
            return
        }
        guard eventServer == nil, !listenFailed else { return }
        let path = socketPath ?? AgentSocket.path(inStorageDirectory: context.storage.directory)
        let settings = context.settings
        let keys = AIAgentsSettingsKeys(settings)
        let directory = URL(filePath: path).deletingLastPathComponent()
        let server = AgentEventServer(directory: directory) { [weak store, weak self] payload in
            // Read when the event arrives, so an agent turned off since the socket opened stays quiet.
            let events = payload.agentEvents.filter { settings.value($0.source == .claude ? keys.claudeEnabled : keys.codexEnabled) }
            if !events.isEmpty { store?.apply(events, fromHooks: true) }
            self?.settlePermissions(after: payload)
        }
        do {
            try server.start()
            eventServer = server
            hookListenStatus.failure = nil
        } catch {
            listenFailed = true
            hookListenStatus.failure = HookListenStatus.failureMessage
            context.logger.error("Cannot listen for agent hooks: \(String(describing: error), privacy: .public)")
            return
        }
        // The status works without it, so a failure here costs only the buttons.
        let permissionServer = PermissionServer(directory: directory) { [weak self] payload, connection in
            self?.receive(payload, over: connection)
        }
        do {
            try permissionServer.start()
            self.permissionServer = permissionServer
        } catch {
            hookListenStatus.failure = HookListenStatus.permissionFailureMessage
            context.logger.error("Cannot listen for agent permission requests: \(String(describing: error), privacy: .public)")
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
        // back in. The store's timer, armed when the turn ended, ends the session's finished state first and this module
        // then clears the activity, so `publishedActivity` never outlives what the center shows; the expiry is a margin
        // later, only what marks the activity as a notice and a backstop.
        let lifetime: Duration? = content.kind == .finished
            ? .seconds(context.settings.value(AIAgentsSettingsKeys(context.settings).finishedSeconds)) + Self.finishedExpiryMargin : nil
        // A request shows as a card in a strip under the notch, with its buttons; its summary names it in the list of
        // activities and for VoiceOver.
        let card = content.ask.flatMap { ask in
            permissions.map { queue in
                AnyView(PermissionCard(request: ask.request, others: ask.others, queue: queue) { [weak self] in self?.decide($0, $1) })
            }
        }
        context.activities.set(LiveActivity(
            id: Self.activityID,
            priority: content.priority,
            expiresAfter: lifetime,
            leading: AnyView(AgentActivityLeading(content: content)),
            trailing: AnyView(AgentActivityTrailing(content: content)),
            bottom: card,
            bottomHeight: card == nil ? 0 : PermissionCard.stripHeight,
            summary: content.ask == nil ? nil : content.accessibilityLabel
        ))
    }
}
