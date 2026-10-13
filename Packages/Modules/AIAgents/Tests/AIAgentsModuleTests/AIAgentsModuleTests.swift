import AgentHookKit
import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import AIAgentsModule

/// Records what the tab asked the system to do, so no test opens Terminal or touches the pasteboard.
final class FakeOpener {
    var terminal: [URL] = []
    var folders: [URL] = []
    var copied: [String] = []

    var opener: AgentOpener {
        AgentOpener(
            openInTerminal: { [self] in terminal.append($0) },
            openFolder: { [self] in folders.append($0) },
            copy: { [self] in copied.append($0) }
        )
    }
}

/// The module under a real `ModuleRegistry`, with the machine replaced by a fake file system, a temporary
/// `~/.claude` and `~/.codex`, and a manual scheduler. Sessions come either from events given to the store or
/// from hand-written transcript lines.
@Suite final class AIAgentsModuleTests {
    let sandbox: Sandbox
    let fileSystem = FakeAgentFileSystem()
    let opener = FakeOpener()
    let hookInstaller = FakeHookInstaller()
    let module: AIAgentsModule
    let harness: RegistryHarness
    /// Unix socket paths are short, so this is outside the sandboxed temporary directory.
    let socketDirectory = URL(filePath: "/tmp/mn-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
    var socketPath: String { socketDirectory.appending(path: "agent.sock").path }
    let session = "11111111-2222-4333-8444-555555555555"
    let codexID = "0199aaaa-bbbb-7ccc-8ddd-eeeeeeeeeeee"

    init() throws {
        sandbox = try Sandbox()
        fileSystem.setAlive(4242)
        module = AIAgentsModule(
            fileSystem: fileSystem, claudeRoot: sandbox.claude, codexRoot: sandbox.codex, opener: opener.opener,
            hookSetup: hookInstaller.setup(in: sandbox.directory), socketPath: socketDirectory.appending(path: "agent.sock").path
        )
        harness = RegistryHarness([module])
    }

    isolated deinit {
        module.stopWatching()
        try? FileManager.default.removeItem(at: socketDirectory)
    }

    var keys: AIAgentsSettingsKeys { AIAgentsSettingsKeys(harness.settingsEnvironment(for: "aiagents")!.settings) }
    var store: AgentSessionStore { module.store! }
    var current: ActivityCenter.Entry? { harness.activities.current }

    func start() async {
        await harness.registry.bootstrap()
    }

    /// Lets the observation loop run after a change to the store or the settings.
    func settle(until condition: () -> Bool) async {
        for _ in 0..<100 where !condition() { await Task.yield() }
    }

    /// Polls, for what has to come through the watcher's own queue.
    func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    /// `at` nil means now.
    func send(_ kind: AgentEvent.Kind, _ source: AgentSource = .claude, id: String = "s1", at: Date? = nil, usage: AgentUsage? = nil) {
        store.apply(AgentEvent(source: source, sessionID: id, timestamp: at, kind: kind, usage: usage))
    }

    func key(_ id: String = "s1", _ source: AgentSource = .claude) -> AgentSessionKey {
        AgentSessionKey(source: source, sessionID: id)
    }

    func liveClaudeSession() throws {
        try sandbox.writeRegistry(pid: 4242, sessionID: session)
        try sandbox.write(Line.prompt(session) + Line.tool(session), to: sandbox.transcript(session))
    }

    func codexRollout() throws {
        try sandbox.write(Line.codexMeta() + Line.codexContext + Line.codexTurn(), to: sandbox.rollout(codexID))
    }

    // MARK: Module

    @Test func descriptor() {
        let descriptor = module.descriptor
        #expect(descriptor.id == "aiagents")
        #expect(descriptor.displayName == "AI agents")
        #expect(descriptor.systemImage == "sparkles")
        #expect(descriptor.defaultEnabled)
        #expect(descriptor.order == 500)
        #expect(descriptor.permissions.isEmpty)
        #expect(descriptor.optionalPermissions.isEmpty)
    }

    @Test func theRealRootsAreTheClaudeAndCodexFoldersOfTheHomeDirectory() {
        let home = URL(filePath: "/Users/example", directoryHint: .isDirectory)
        let roots = AIAgentsModule.defaultRoots(home: home)
        #expect(roots.claude.path == "/Users/example/.claude")
        #expect(roots.codex.path == "/Users/example/.codex")
    }

    @Test func startsQuietly() async {
        await start()
        #expect(harness.registry.state(of: "aiagents") == .running)
        #expect(current == nil)
        #expect(store.sessions.isEmpty)
        #expect(module.publishedActivity == nil)
    }

    @Test func tab() async throws {
        await start()
        let tab = try #require(harness.registry.tabs.first)
        #expect(harness.registry.tabs.count == 1)
        #expect(tab.id == "aiagents")
        #expect(tab.title == "AI")
        #expect(tab.systemImage == "sparkles")
        #expect(tab.preferredHeight == 200)
        #expect(!tab.acceptsKeyboard)
    }

    @Test func noTabBeforeTheModuleHasStarted() {
        #expect(module.makeTab() == nil)
        #expect(harness.registry.tabs.isEmpty)
    }

    // MARK: Activity

    @Test func aWorkingSessionShowsTheActivityWithTheTurnsStartTime() async {
        await start()
        let began = Date().addingTimeInterval(-42)
        send(.turnStarted, at: began)
        await settle { current != nil }
        #expect(current?.id == "aiagents/agent")
        #expect(current?.activity.priority == .normal)
        #expect(module.publishedActivity == AgentActivityContent(kind: .working(since: began), source: .claude))
    }

    @Test func aCodexSessionShowsItsOwnGlyph() async {
        await start()
        send(.turnStarted, .codex, id: "x")
        await settle { current != nil }
        #expect(module.publishedActivity?.source == .codex)
        #expect(AgentSource.claude.systemImage == "sparkle")
        #expect(AgentSource.codex.systemImage == "chevron.left.forwardslash.chevron.right")
    }

    @Test func waitingForInputRaisesThePriority() async {
        await start()
        send(.turnStarted)
        await settle { current != nil }
        send(.waitingForInput)
        await settle { current?.activity.priority == .high }
        #expect(current?.activity.priority == .high)
        #expect(module.publishedActivity?.kind == .waitingForInput)
        // Back to work once the user has answered.
        send(.toolFinished)
        await settle { current?.activity.priority == .normal }
        #expect(current?.activity.priority == .normal)
    }

    @Test func aWaitingSessionOutranksOtherAgentsActivities() async {
        await start()
        send(.turnStarted, id: "busy")
        send(.waitingForInput, .codex, id: "asking")
        await settle { current?.activity.priority == .high }
        #expect(module.publishedActivity == AgentActivityContent(kind: .waitingForInput, source: .codex))
    }

    @Test func theActivityIsOneEntryUpdatedInPlace() async {
        await start()
        send(.turnStarted)
        await settle { current != nil }
        send(.waitingForInput)
        await settle { module.publishedActivity?.kind == .waitingForInput }
        send(.turnFinished)
        await settle { module.publishedActivity?.kind == .finished }
        #expect(harness.activities.entries.map(\.id) == ["aiagents/agent"])
    }

    @Test func aFinishedTurnShowsACheckmarkThenClears() async {
        await start()
        send(.turnStarted)
        await settle { current != nil }
        send(.turnFinished)
        await settle { module.publishedActivity?.kind == .finished }
        #expect(current?.activity.priority == .normal)
        harness.scheduler.advance(by: .milliseconds(4900))
        #expect(module.publishedActivity?.kind == .finished)
        #expect(current != nil)
        harness.scheduler.advance(by: .milliseconds(100))
        await settle { current == nil }
        #expect(current == nil)
        #expect(module.publishedActivity == nil)
    }

    @Test func theCheckmarkLastsAsLongAsTheSettingSays() async {
        harness.settings.set(10, for: keys.finishedSeconds)
        await start()
        send(.turnStarted)
        send(.turnFinished)
        await settle { module.publishedActivity?.kind == .finished }
        harness.scheduler.advance(by: .milliseconds(9900))
        #expect(module.publishedActivity?.kind == .finished)
        harness.scheduler.advance(by: .milliseconds(100))
        await settle { current == nil }
        #expect(current == nil)
    }

    @Test func changingTheDurationAppliesToTheNextFinishedTurn() async {
        await start()
        harness.settings.set(3, for: keys.finishedSeconds)
        await settle { store.finishedSeconds == 3 }
        send(.turnStarted)
        send(.turnFinished)
        await settle { module.publishedActivity?.kind == .finished }
        harness.scheduler.advance(by: .seconds(3))
        await settle { current == nil }
        #expect(current == nil)
    }

    @Test func theDurationIsKeptBetweenTwoAndThirtySeconds() {
        let settings = harness.settingsEnvironment(for: "aiagents")!.settings
        #expect(settings.value(keys.finishedSeconds) == 5)
        settings.set(1, for: keys.finishedSeconds)
        #expect(settings.value(keys.finishedSeconds) == 2)
        settings.set(99, for: keys.finishedSeconds)
        #expect(settings.value(keys.finishedSeconds) == 30)
        #expect(AIAgentsSettingsKeys.finishedSecondsRange == 2...30)
    }

    @Test func anAbortedTurnClearsTheActivity() async {
        await start()
        send(.turnStarted)
        await settle { current != nil }
        send(.turnAborted)
        await settle { current == nil }
        #expect(current == nil)
    }

    @Test func theActivityKeepsGoingWhileAnotherSessionStillWorks() async {
        await start()
        let first = Date().addingTimeInterval(-100)
        let second = Date().addingTimeInterval(-10)
        send(.turnStarted, id: "a", at: first)
        send(.turnStarted, .codex, id: "b", at: second)
        await settle { current != nil }
        #expect(module.publishedActivity == AgentActivityContent(kind: .working(since: first), source: .claude))
        send(.sessionEnded, id: "a")
        await settle { module.publishedActivity?.source == .codex }
        #expect(module.publishedActivity == AgentActivityContent(kind: .working(since: second), source: .codex))
        send(.sessionEnded, .codex, id: "b")
        await settle { current == nil }
        #expect(current == nil)
    }

    @Test func workingActivityCanBeSwitchedOff() async {
        harness.settings.set(false, for: keys.showWorkingActivity)
        await start()
        send(.turnStarted)
        await settle { current != nil }
        #expect(current == nil)
        // Still told when the agent waits or is done.
        send(.waitingForInput)
        await settle { current != nil }
        #expect(current?.activity.priority == .high)
        send(.turnFinished)
        await settle { module.publishedActivity?.kind == .finished }
        #expect(module.publishedActivity?.kind == .finished)
    }

    @Test func switchingWorkingActivityOnAndOffWhileWorking() async {
        await start()
        send(.turnStarted)
        await settle { current != nil }
        harness.settings.set(false, for: keys.showWorkingActivity)
        await settle { current == nil }
        #expect(current == nil)
        harness.settings.set(true, for: keys.showWorkingActivity)
        await settle { current != nil }
        #expect(current?.id == "aiagents/agent")
    }

    // MARK: Tab state

    @Test func theTabStateOfAFreshModuleIsEmpty() async {
        await start()
        let state = AgentTabState(store: store, now: Date())
        #expect(state.isEmpty)
        #expect(state.usage.isEmpty)
        #expect(state.limits.isEmpty)
    }

    @Test func theTabListsSessionsNewestFirstWithTodaysUsage() async {
        await start()
        let now = Date()
        send(.sessionStarted(cwd: "/Users/example/Projects/demo", branch: "main"), id: "a", at: now - 20)
        send(.toolStarted(name: "Bash", summary: "git status"), id: "a", at: now - 10)
        send(.usageUpdated, id: "a", at: now - 10, usage: AgentUsage(output: 2_000, model: "claude-opus-4-1", messageID: "m1"))
        send(.sessionStarted(cwd: "/Users/example/Projects/tool", branch: nil), .codex, id: "b", at: now - 5)
        send(.turnStarted, .codex, id: "b", at: now - 5)
        let state = AgentTabState(store: store, now: now)
        #expect(state.rows.map(\.title) == ["tool", "demo • main"])
        #expect(state.rows.map(\.source) == [.codex, .claude])
        #expect(state.rows.last?.detail == "Bash · git status")
        #expect(state.usage.map(\.source) == [.claude])
        #expect(state.usage.first?.tokens == "2K")
        #expect(state.usage.first?.cost == "$0.15")
        #expect(state.usage.first?.isEstimated == true)
    }

    // MARK: Opening

    @Test func clickingASessionOpensItsFolderInTerminal() async {
        await start()
        module.openInTerminal(cwd: sandbox.directory.path)
        #expect(opener.terminal.map(\.path) == [sandbox.directory.path])
        #expect(opener.folders.isEmpty)
    }

    @Test func theMenuOpensTheFolderAndCopiesThePath() async {
        await start()
        module.openFolder(cwd: sandbox.directory.path)
        module.copyPath(cwd: sandbox.directory.path)
        #expect(opener.folders.map(\.path) == [sandbox.directory.path])
        #expect(opener.copied == [sandbox.directory.path])
        #expect(opener.terminal.isEmpty)
    }

    @Test func onlyAnExistingFolderIsOpened() throws {
        let file = sandbox.directory.appending(path: "script.sh")
        try sandbox.write("#!/bin/sh\n", to: file)
        for cwd in [nil, "", "relative/path", "~/Projects", sandbox.directory.appending(path: "missing").path, file.path] {
            module.openInTerminal(cwd: cwd)
            module.openFolder(cwd: cwd)
        }
        #expect(opener.terminal.isEmpty)
        #expect(opener.folders.isEmpty)
    }

    @Test func aPathIsCopiedAsLongAsThereIsOne() {
        module.copyPath(cwd: nil)
        module.copyPath(cwd: "")
        #expect(opener.copied.isEmpty)
        module.copyPath(cwd: "/Users/example/Projects/gone")
        #expect(opener.copied == ["/Users/example/Projects/gone"])
    }

    // MARK: Files

    @Test func aLiveClaudeSessionShowsFromItsFiles() async throws {
        try liveClaudeSession()
        await start()
        #expect(await waitUntil { module.publishedActivity != nil })
        #expect(module.publishedActivity?.source == .claude)
        let row = AgentTabState(store: store, now: Date()).rows.first
        #expect(row?.title == "demo • main")
        #expect(row?.detail == "Bash · git status")
        #expect(current?.id == "aiagents/agent")
    }

    @Test func aCodexRolloutShowsFromItsFiles() async throws {
        try codexRollout()
        await start()
        #expect(await waitUntil { module.publishedActivity != nil })
        #expect(module.publishedActivity?.source == .codex)
        #expect(AgentTabState(store: store, now: Date()).rows.first?.title == "tool • feature/x")
    }

    @Test func turningClaudeOffRemovesItsSessionsAndStopsFollowingIt() async throws {
        try liveClaudeSession()
        try codexRollout()
        await start()
        #expect(await waitUntil { store.sessions.count == 2 })
        harness.settings.set(false, for: keys.claudeEnabled)
        await settle { store.sessions[key(session)] == nil }
        #expect(store.sessions.keys.map(\.source) == [.codex])
        // What Claude writes from now on is not read.
        try sandbox.append(Line.finish(session), to: sandbox.transcript(session))
        fileSystem.fire()
        try await Task.sleep(for: .milliseconds(300))
        #expect(store.sessions[key(session)] == nil)
        // On again, it is picked up from the files.
        harness.settings.set(true, for: keys.claudeEnabled)
        #expect(await waitUntil { store.sessions[key(session)] != nil })
        #expect(store.sessions[key(codexID, .codex)] != nil)
    }

    @Test func turningCodexOffRemovesItsSessionsAndStopsFollowingIt() async throws {
        try liveClaudeSession()
        try codexRollout()
        await start()
        #expect(await waitUntil { store.sessions.count == 2 })
        harness.settings.set(false, for: keys.codexEnabled)
        await settle { store.sessions[key(codexID, .codex)] == nil }
        #expect(store.sessions.keys.map(\.source) == [.claude])
        harness.settings.set(true, for: keys.codexEnabled)
        #expect(await waitUntil { store.sessions[key(codexID, .codex)] != nil })
    }

    @Test func aCodexRolloutIsCountedOnceHoweverOftenCodexIsTurnedOffAndOn() async throws {
        try sandbox.write(
            Line.codexMeta() + Line.codexContext + Line.codexTurn() + Line.codexTokens(input: 1_000, output: 0) + Line.codexTokens(input: 1_500, output: 0),
            to: sandbox.rollout(codexID)
        )
        await start()
        #expect(await waitUntil { store.todayUsage[.codex]?.tokens.input == 1_500 })
        for _ in 0..<3 {
            harness.settings.set(false, for: keys.codexEnabled)
            await settle { store.sessions[key(codexID, .codex)] == nil }
            #expect(store.sessions[key(codexID, .codex)] == nil)
            // The rollout is read again from its first line, whose total is lower than the last one seen.
            harness.settings.set(true, for: keys.codexEnabled)
            #expect(await waitUntil { store.sessions[key(codexID, .codex)] != nil })
        }
        #expect(store.todayUsage[.codex]?.tokens.input == 1_500)
    }

    @Test func nothingIsWatchedWhileBothAgentsAreOff() async throws {
        try liveClaudeSession()
        try codexRollout()
        harness.settings.set(false, for: keys.claudeEnabled)
        harness.settings.set(false, for: keys.codexEnabled)
        await start()
        #expect(!fileSystem.isWatching)
        try await Task.sleep(for: .milliseconds(100))
        #expect(store.sessions.isEmpty)
        harness.settings.set(true, for: keys.codexEnabled)
        #expect(await waitUntil { fileSystem.isWatching && store.sessions.count == 1 })
    }

    @Test func eachAgentHasOneWatchHoweverOftenTheSettingsChange() async throws {
        try sandbox.createDirectory(sandbox.claude)
        try sandbox.createDirectory(sandbox.codex)
        await start()
        #expect(await waitUntil { fileSystem.activeWatchCount == 2 })
        harness.settings.set(7, for: keys.finishedSeconds)
        harness.settings.set(false, for: keys.showWorkingActivity)
        await settle { store.finishedSeconds == 7 }
        harness.settings.set(false, for: keys.codexEnabled)
        #expect(await waitUntil { fileSystem.activeWatchCount == 1 })
        harness.settings.set(true, for: keys.codexEnabled)
        #expect(await waitUntil { fileSystem.activeWatchCount == 2 })
        harness.settings.set(8, for: keys.finishedSeconds)
        await settle { store.finishedSeconds == 8 }
        try await Task.sleep(for: .milliseconds(100))
        #expect(fileSystem.activeWatchCount == 2)
        await harness.registry.setEnabled(false, for: "aiagents")
        #expect(await waitUntil { fileSystem.activeWatchCount == 0 })
    }

    @Test func turningAnAgentOffClearsItsActivity() async throws {
        try liveClaudeSession()
        await start()
        #expect(await waitUntil { current != nil })
        harness.settings.set(false, for: keys.claudeEnabled)
        await settle { current == nil }
        #expect(current == nil)
    }

    // MARK: Lifecycle

    @Test func disablingTheModuleStopsWatchingAndClearsEverything() async throws {
        try liveClaudeSession()
        await start()
        #expect(await waitUntil { current != nil })
        await harness.registry.setEnabled(false, for: "aiagents")
        #expect(current == nil)
        #expect(harness.registry.tabs.isEmpty)
        // The watchers cancel their watch on their own queues.
        #expect(await waitUntil { !fileSystem.isWatching })
        #expect(module.store == nil)
        #expect(harness.scheduler.pendingCount == 0)
    }

    @Test func startingAgainBeginsWithoutTheEarlierSessions() async {
        await start()
        send(.turnStarted)
        await settle { current != nil }
        await harness.registry.setEnabled(false, for: "aiagents")
        await harness.registry.setEnabled(true, for: "aiagents")
        #expect(store.sessions.isEmpty)
        #expect(current == nil)
        send(.turnStarted)
        await settle { current != nil }
        #expect(current != nil)
    }

    // MARK: Precise status

    func sendHook(_ event: String, source: String = "claude", id: String = "s1") throws {
        let payload = HookPayload(source: source, event: event, sessionID: id, tool: event == "PreToolUse" ? "Bash" : nil, timestamp: Date())
        HookDatagramSender.send(try #require(payload.encodedDatagram()), to: socketPath)
    }

    @Test func preciseStatusIsOffByDefaultAndListensToNothing() async {
        #expect(!harness.settingsEnvironment(for: "aiagents")!.settings.value(keys.preciseStatus))
        await start()
        #expect(!FileManager.default.fileExists(atPath: socketPath))
    }

    @Test func turningPreciseStatusOnListensAndHookEventsReachTheStore() async throws {
        await start()
        harness.settings.set(true, for: keys.preciseStatus)
        #expect(await waitUntil { FileManager.default.fileExists(atPath: socketPath) })
        try sendHook("PermissionRequest")
        #expect(await waitUntil { store.sessions[key()]?.state == .waitingForInput })
        // The transcript only sees a tool that was asked for; the hook knows it waits.
        send(.toolStarted(name: "Bash", summary: nil))
        #expect(store.sessions[key()]?.state == .waitingForInput)
    }

    @Test func aSettingThatIsAlreadyOnListensFromTheStart() async throws {
        harness.settings.set(true, for: keys.preciseStatus)
        await start()
        #expect(FileManager.default.fileExists(atPath: socketPath))
        try sendHook("UserPromptSubmit")
        #expect(await waitUntil { store.sessions[key()] != nil })
    }

    @Test func turningPreciseStatusOffStopsListening() async throws {
        harness.settings.set(true, for: keys.preciseStatus)
        await start()
        harness.settings.set(false, for: keys.preciseStatus)
        #expect(await waitUntil { !FileManager.default.fileExists(atPath: socketPath) })
        try sendHook("UserPromptSubmit")
        try await Task.sleep(for: .milliseconds(100))
        #expect(store.sessions.isEmpty)
    }

    @Test func hookEventsOfAnAgentThatIsTurnedOffAreIgnored() async throws {
        harness.settings.set(false, for: keys.claudeEnabled)
        harness.settings.set(true, for: keys.preciseStatus)
        await start()
        try sendHook("PermissionRequest")
        try sendHook("UserPromptSubmit", source: "codex", id: "c1")
        // The datagrams are delivered in order, so the Codex session shows once the Claude one was dealt with.
        #expect(await waitUntil { store.sessions[key("c1", .codex)] != nil })
        #expect(store.sessions[key()] == nil)
        await settle { module.publishedActivity != nil }
        #expect(module.publishedActivity?.source == .codex)
        // On again, its hooks count; off again, they stop, though the socket keeps listening for Codex.
        harness.settings.set(true, for: keys.claudeEnabled)
        try sendHook("UserPromptSubmit", id: "on")
        #expect(await waitUntil { store.sessions[key("on")] != nil })
        harness.settings.set(false, for: keys.claudeEnabled)
        await settle { store.sessions[key("on")] == nil }
        try sendHook("UserPromptSubmit", id: "off")
        try sendHook("UserPromptSubmit", source: "codex", id: "c2")
        #expect(await waitUntil { store.sessions[key("c2", .codex)] != nil })
        #expect(store.sessions[key("off")] == nil)
    }

    @Test func installingHooksTurnsPreciseStatusOnSoTheyGoSomewhere() throws {
        let environment = try #require(harness.settingsEnvironment(for: "aiagents"))
        let hooks = module.hookSetupModel(for: environment)
        #expect(!environment.settings.value(keys.preciseStatus))
        hookInstaller.helperFailure = HookHelper.Unavailable(path: "/app/mynotch-hook")
        hooks.merge(.claude)
        #expect(!environment.settings.value(keys.preciseStatus))
        hookInstaller.helperFailure = nil
        hooks.merge(.codex)
        #expect(environment.settings.value(keys.preciseStatus))
        environment.settings.set(false, for: keys.preciseStatus)
        hooks.installClaudePlugin()
        #expect(environment.settings.value(keys.preciseStatus))
    }

    @Test func theInstallButtonsKeepTheirModelWhenTheSettingsRowsAreBuiltAgain() throws {
        let environment = try #require(harness.settingsEnvironment(for: "aiagents"))
        let hooks = module.hookSetupModel(for: environment)
        hooks.merge(.claude)
        #expect(module.hookSetupModel(for: environment) === hooks)
        #expect(!module.hookSetupModel(for: environment).message.isEmpty)
    }

    @Test func aSocketThatCannotBeOpenedIsNotRetriedWithEveryChange() async throws {
        // A file where the socket's folder should be.
        try Data().write(to: socketDirectory)
        harness.settings.set(true, for: keys.preciseStatus)
        await start()
        try FileManager.default.removeItem(at: socketDirectory)
        harness.settings.set(7, for: keys.finishedSeconds)
        await settle { store.finishedSeconds == 7 }
        #expect(store.finishedSeconds == 7)
        #expect(!FileManager.default.fileExists(atPath: socketPath))
        // Switching the setting off and on tries again.
        // The finished-seconds change shows that a refresh has run with the setting off.
        harness.settings.set(false, for: keys.preciseStatus)
        harness.settings.set(8, for: keys.finishedSeconds)
        await settle { store.finishedSeconds == 8 }
        harness.settings.set(true, for: keys.preciseStatus)
        #expect(await waitUntil { FileManager.default.fileExists(atPath: socketPath) })
    }

    @Test func aSocketThatCannotBeOpenedIsToldInTheSettingsUntilItWorks() async throws {
        try Data().write(to: socketDirectory)
        harness.settings.set(true, for: keys.preciseStatus)
        await start()
        let message = try #require(module.hookListenStatus.failure)
        #expect(message.contains("socket"))
        try FileManager.default.removeItem(at: socketDirectory)
        harness.settings.set(false, for: keys.preciseStatus)
        await settle { module.hookListenStatus.failure == nil }
        #expect(module.hookListenStatus.failure == nil)
        harness.settings.set(true, for: keys.preciseStatus)
        #expect(await waitUntil { FileManager.default.fileExists(atPath: socketPath) })
        #expect(module.hookListenStatus.failure == nil)
    }

    @Test func theFailureIsForgottenWhenTheModuleStops() async throws {
        try Data().write(to: socketDirectory)
        harness.settings.set(true, for: keys.preciseStatus)
        await start()
        #expect(module.hookListenStatus.failure != nil)
        await harness.registry.setEnabled(false, for: "aiagents")
        #expect(module.hookListenStatus.failure == nil)
    }

    @Test func disablingTheModuleStopsListening() async {
        harness.settings.set(true, for: keys.preciseStatus)
        await start()
        await harness.registry.setEnabled(false, for: "aiagents")
        #expect(!FileManager.default.fileExists(atPath: socketPath))
    }

    // MARK: Settings

    @Test func settingsRowsExistWhetherOrNotTheModuleRuns() async {
        #expect(harness.registry.settingsView(for: "aiagents") != nil)
        await start()
        #expect(harness.registry.settingsView(for: "aiagents") != nil)
    }

    @Test func settingsDefaults() {
        let settings = harness.settingsEnvironment(for: "aiagents")!.settings
        #expect(settings.value(keys.claudeEnabled))
        #expect(settings.value(keys.codexEnabled))
        #expect(settings.value(keys.showWorkingActivity))
        #expect(settings.value(keys.finishedSeconds) == 5)
        #expect(keys.claudeEnabled.name == "module.aiagents.claudeEnabled")
        #expect(keys.codexEnabled.name == "module.aiagents.codexEnabled")
        #expect(keys.showWorkingActivity.name == "module.aiagents.showWorkingActivity")
        #expect(keys.finishedSeconds.name == "module.aiagents.finishedSeconds")
        #expect(keys.preciseStatus.name == "module.aiagents.preciseStatus")
    }
}
