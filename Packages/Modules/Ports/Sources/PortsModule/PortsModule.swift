import AppKit
import MyNotchCore
import NotchUI
import Observation
import SwiftUI

/// What the tab asks of the module.
struct PortsActions {
    var appeared: () -> Void
    var disappeared: () -> Void
    var open: (PortEntry) -> Void
    var copy: (PortEntry) -> Void
    var canStop: (PortEntry) -> Bool
    var requestStop: (PortEntry) -> Void
    var confirmStop: (Int32) -> Void
    var cancelStop: (Int32) -> Void
    var forceStop: (Int32) -> Void
    var quickChanged: () -> Void

    static let none = PortsActions(
        appeared: {}, disappeared: {}, open: { _ in }, copy: { _ in }, canStop: { _ in true }, requestStop: { _ in },
        confirmStop: { _ in }, cancelStop: { _ in }, forceStop: { _ in }, quickChanged: {}
    )
}

/// What the module does to the outside world besides signals: opening a page and copying a line.
struct PortsEnvironment {
    var openURL: (URL) -> Void
    var copy: (String) -> Void

    static let system = PortsEnvironment(
        openURL: { NSWorkspace.shared.open($0) },
        copy: { text in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    )
}

/// "Cổng": which process holds which port, and a way to free one. The list is read only while a tab is on screen.
public final class PortsModule: FeatureModule {
    public let descriptor = ModuleDescriptor(
        id: "ports",
        displayName: "Cổng",
        systemImage: "network",
        defaultEnabled: true,
        order: 920
    )

    /// How often the open tab reads the ports again: a server starting or stopping sends the app no notification.
    static let pollInterval = Duration.seconds(2)
    /// How long "Đã dừng node" stays up.
    static let noticeLifetime = Duration.seconds(4)
    /// The area below the notch, tab bar and inner padding included.
    static let tabHeight: CGFloat = 230

    static func showUDPKey(_ settings: ModuleSettings) -> SettingKey<Bool> { settings.key("showUDP", default: false) }

    let state = PortsState()
    private let source: any PortSource
    private let control: any ProcessControl
    private let probe: any PortProbe
    private let policy: StopPolicy
    private let environment: PortsEnvironment
    private let interface: NotchInterface
    private var context: ModuleContext?
    /// Bumped when the module stops, so an answer that arrives afterwards is dropped.
    private var generation = 0
    /// Tabs on screen: each screen has its own notch, so more than one can show this tab at a time.
    private var visibleTabs = 0
    private var isReading = false
    private var pollTimer: ScheduledAction?
    private var stopTimers: [Int32: ScheduledAction] = [:]
    private var noticeTimer: ScheduledAction?
    private var pending: [Int: Task<Void, Never>] = [:]
    private var nextTask = 0

    /// Nothing here has a default on purpose: a test that built the module without saying what signals go to could reach a real
    /// process. Only `init()` wires the real ones.
    init(
        source: any PortSource, control: any ProcessControl, probe: any PortProbe, policy: StopPolicy, environment: PortsEnvironment,
        interface: NotchInterface
    ) {
        self.source = source
        self.control = control
        self.probe = probe
        self.policy = policy
        self.environment = environment
        self.interface = interface
    }

    public convenience init() {
        self.init(
            source: LibprocPortSource(), control: LibprocProcessControl(), probe: LoopbackBindProbe(), policy: .current,
            environment: .system, interface: .shared
        )
    }

    /// Whether a row may show the arguments of its process. They can hold what the user would not want seen (the secrets that
    /// `SecretMask` does not know), so when the user keeps MyNotch out of recordings and shared screens, which says that a
    /// recording or a share is in the picture, a row is the name alone. macOS has no call that says whether a capture is running
    /// right now, so the user's setting is what stands for it.
    static func showsCommandLines(under hiding: CaptureHiding) -> Bool { hiding == .never }

    public func start(_ context: ModuleContext) async throws(ModuleError) {
        self.context = context
        generation += 1
        let settings = context.settings
        let key = Self.showUDPKey(settings)
        state.showUDP = settings.value(key)
        state.showsCommandLines = Self.showsCommandLines(under: interface.captureHiding)
        context.run { [weak self] in
            for await _ in Observations({ settings.value(key) }) { self?.state.showUDP = settings.value(key) }
        }
        let interface = interface
        context.run { [weak self] in
            for await hiding in Observations({ interface.captureHiding }) {
                self?.state.showsCommandLines = Self.showsCommandLines(under: hiding)
            }
        }
    }

    public func stop() async {
        generation += 1
        pollTimer?.cancel()
        pollTimer = nil
        stopTimers.values.forEach { $0.cancel() }
        stopTimers = [:]
        noticeTimer?.cancel()
        noticeTimer = nil
        context = nil
        visibleTabs = 0
        isReading = false
        state.showsCommandLines = true
        state.entries = []
        state.hasLoaded = false
        state.filter = ""
        state.quickQuery = ""
        state.probe = nil
        state.flows = [:]
        state.notice = nil
        state.isTabVisible = false
    }

    /// Takes the keyboard: the two fields.
    public func makeTab() -> NotchTab? {
        NotchTab(
            id: descriptor.id, title: "Cổng", systemImage: "network", preferredHeight: Self.tabHeight, acceptsKeyboard: true,
            content: AnyView(PortsTabView(state: state, actions: actions))
        )
    }

    public func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView? {
        AnyView(PortsSettingsView(showUDP: environment.settings.binding(Self.showUDPKey(environment.settings))))
    }

    var actions: PortsActions {
        PortsActions(
            appeared: { [weak self] in self?.tabAppeared() },
            disappeared: { [weak self] in self?.tabDisappeared() },
            open: { [weak self] in self?.open($0) },
            copy: { [weak self] in self?.copy($0) },
            canStop: { [weak self] in self?.policy.refusal(for: $0.process.identity) == nil },
            requestStop: { [weak self] in self?.requestStop($0) },
            confirmStop: { [weak self] pid in self?.track { await self?.confirmStop(pid: pid) } },
            cancelStop: { [weak self] in self?.cancelStop(pid: $0) },
            forceStop: { [weak self] pid in self?.track { await self?.forceStop(pid: pid) } },
            quickChanged: { [weak self] in self?.quickQueryChanged() }
        )
    }

    // MARK: Reading

    /// Opening the tab shows the ports at once, and from then on they are read again every `pollInterval`.
    func tabAppeared() {
        guard context != nil else { return }
        visibleTabs += 1
        state.isTabVisible = true
        readNow()
    }

    /// With no tab left on screen nothing is read, and a question the user did not answer is not left for the next time.
    func tabDisappeared() {
        visibleTabs = max(0, visibleTabs - 1)
        guard visibleTabs == 0 else { return }
        state.isTabVisible = false
        pollTimer?.cancel()
        pollTimer = nil
        for (pid, flow) in state.flows where !flow.phase.isBusy { state.flows[pid] = nil }
    }

    private func readNow() {
        guard context != nil, !isReading else { return }
        isReading = true
        let generation = generation
        let source = source
        track { [weak self] in
            let snapshot = await Self.offMain { source.read() }
            guard let self, self.generation == generation else { return }
            isReading = false
            apply(PortEntry.entries(from: snapshot))
            // The next read is timed from the end of this one, so a slow read never has another piled on it.
            if visibleTabs > 0 { schedulePoll() }
        }
    }

    private func schedulePoll() {
        pollTimer?.cancel()
        pollTimer = context?.scheduler.schedule(after: Self.pollInterval) { [weak self] in self?.readNow() }
    }

    private func apply(_ entries: [PortEntry]) {
        if state.entries != entries { state.entries = entries }
        state.hasLoaded = true
        for (pid, flow) in state.flows where !flow.phase.isBusy && !entries.contains(where: { $0.id == flow.entry.id }) {
            state.flows[pid] = nil
        }
        // A port that no row of the user's has is asked about again, so "trống" is what the system says now.
        if let port = PortQuickCheck.port(from: state.quickQuery), !entries.contains(where: { $0.port == port }) {
            probeQuick(port)
        }
    }

    // MARK: Quick check

    func quickQueryChanged() {
        guard let port = PortQuickCheck.port(from: state.quickQuery) else {
            state.probe = nil
            return
        }
        if !state.entries.contains(where: { $0.port == port }) { probeQuick(port) }
    }

    private func probeQuick(_ port: UInt16) {
        guard context != nil else { return }
        let generation = generation
        let probe = probe
        track { [weak self] in
            let result = await Self.offMain { probe.probe(port: port) }
            // Typing goes on while the system answers; only the answer for what is in the field now is kept.
            guard let self, self.generation == generation, PortQuickCheck.port(from: state.quickQuery) == port else { return }
            state.probe = PortProbeOutcome(port: port, result: result)
        }
    }

    // MARK: Row actions

    func open(_ entry: PortEntry) {
        guard entry.proto == .tcp, let url = URL(string: "http://localhost:\(entry.port)") else { return }
        environment.openURL(url)
    }

    func copy(_ entry: PortEntry) {
        environment.copy("localhost:\(entry.port)")
    }

    // MARK: Stopping

    /// Starts asking: nothing is sent until `confirmStop`. A process that may not be stopped gets its reason instead.
    func requestStop(_ entry: PortEntry) {
        guard context != nil, state.flows[entry.pid]?.phase.isBusy != true else { return }
        if let refusal = policy.refusal(for: entry.process.identity) {
            state.flows[entry.pid] = StopFlow(entry: entry, phase: .refused(refusal))
        } else {
            state.flows[entry.pid] = StopFlow(entry: entry, phase: .confirming)
        }
    }

    func cancelStop(pid: Int32) {
        guard state.flows[pid]?.phase.isBusy == false else { return }
        state.flows[pid] = nil
    }

    /// The user said yes: SIGTERM, and a look after `StopFlow.grace` at whether the process left.
    func confirmStop(pid: Int32) async {
        await deliver(.terminate, to: pid, from: .confirming, becoming: .stopping) { [weak self] in
            self?.schedule(after: StopFlow.grace, for: pid) { await self?.afterTerminate(pid: pid) }
        }
    }

    /// The user said yes to "Buộc dừng": SIGKILL, and a look after `StopFlow.killGrace`.
    func forceStop(pid: Int32) async {
        await deliver(.kill, to: pid, from: .stillRunning, becoming: .forcing) { [weak self] in
            self?.schedule(after: StopFlow.killGrace, for: pid) { await self?.afterKill(pid: pid) }
        }
    }

    /// Sends `signal` to the process of the flow, if the flow is still at `expected`. The phase moves first, so a second click on
    /// the same button cannot send twice. The process is read again right before the signal: if the pid now belongs to another
    /// process, or to one that may not be stopped, nothing is sent.
    private func deliver(
        _ signal: StopSignal, to pid: Int32, from expected: StopPhase, becoming next: StopPhase, sent: @MainActor () -> Void
    ) async {
        guard context != nil, let flow = state.flows[pid], flow.phase == expected else { return }
        state.flows[pid]?.phase = next
        let generation = generation
        let control = control
        let live = await Self.offMain { control.identity(of: pid) }
        guard self.generation == generation, state.flows[pid]?.phase == next else { return }
        guard let live else {
            finish(flow)
            return
        }
        let shown = flow.entry.process.identity
        guard live.startTime == shown.startTime, live.path == shown.path else {
            state.flows[pid]?.phase = .failed(.changed)
            return
        }
        if let refusal = policy.refusal(for: live) {
            state.flows[pid]?.phase = .refused(refusal)
            return
        }
        let result = await Self.offMain { control.send(signal, to: pid) }
        guard self.generation == generation, state.flows[pid]?.phase == next else { return }
        switch result {
        case .sent: sent()
        case .gone: finish(flow)
        case .denied: state.flows[pid]?.phase = .failed(.denied)
        }
    }

    private func schedule(after delay: Duration, for pid: Int32, _ check: @escaping @MainActor () async -> Void) {
        stopTimers[pid]?.cancel()
        stopTimers[pid] = context?.scheduler.schedule(after: delay) { [weak self] in
            self?.stopTimers[pid] = nil
            self?.track(check)
        }
    }

    private func afterTerminate(pid: Int32) async {
        guard let flow = state.flows[pid], flow.phase == .stopping else { return }
        switch await liveness(of: flow) {
        case .stale: return
        case .alive:
            // With the tab gone nobody is there to answer the offer.
            state.flows[pid]?.phase = .stillRunning
            if visibleTabs == 0 { state.flows[pid] = nil }
        case .gone: finish(flow)
        }
    }

    private func afterKill(pid: Int32) async {
        guard let flow = state.flows[pid], flow.phase == .forcing else { return }
        switch await liveness(of: flow) {
        case .stale: return
        case .alive: state.flows[pid]?.phase = .failed(.stuck)
        case .gone: finish(flow)
        }
    }

    private enum Liveness { case alive, gone, stale }

    /// Whether the very process of the flow is alive: a later one with the same pid does not count. `stale` when the module
    /// stopped, or the flow moved on, while the system was being asked.
    private func liveness(of flow: StopFlow) async -> Liveness {
        let control = control
        let generation = generation
        let pid = flow.entry.pid
        let live = await Self.offMain { control.identity(of: pid) }
        guard self.generation == generation, state.flows[pid]?.phase == flow.phase else { return .stale }
        return live?.startTime == flow.entry.process.identity.startTime ? .alive : .gone
    }

    private func finish(_ flow: StopFlow) {
        state.flows[flow.entry.pid] = nil
        state.notice = "Đã dừng \(flow.entry.process.fullName) (cổng \(flow.entry.port))"
        noticeTimer?.cancel()
        noticeTimer = context?.scheduler.schedule(after: Self.noticeLifetime) { [weak self] in self?.state.notice = nil }
        if visibleTabs > 0 { readNow() }
    }

    // MARK: Work

    private nonisolated static func offMain<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await Task.detached(priority: .userInitiated, operation: work).value
    }

    private func track(_ work: @escaping @MainActor () async -> Void) {
        nextTask += 1
        let id = nextTask
        pending[id] = Task { [weak self] in
            await work()
            self?.pending[id] = nil
        }
    }

    /// Waits for the reads, probes and stop checks started so far (for tests).
    func idle() async {
        while let task = pending.values.first { await task.value }
    }
}
