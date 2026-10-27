import Foundation
import MyNotchCore
import NotchUI
import SwiftUI

/// What the Mac is doing: its temperatures and fan speeds, its memory and the processes that hold the most, all read-only. Reads
/// only while something shows them (the tab, or the strip beside the collapsed notch), every two seconds, and none of it on the
/// main actor.
public final class PerformanceModule: FeatureModule {
    public let descriptor = ModuleDescriptor(
        id: "performance",
        displayName: "Hiệu năng",
        systemImage: "gauge.with.dots.needle.50percent",
        defaultEnabled: true,
        order: 870
    )

    static let activityID = "strip"
    /// Time between two reads while something is showing them.
    static let pollInterval = Duration.seconds(2)
    /// How many of the heaviest processes the tab lists.
    static let processCount = 5

    let state = PerformanceState()
    private let thermal: any ThermalReading
    private let memory: any MemoryReading
    private let cpu: any CPUReading
    private let helper: FanHelperManager
    private let curve: FanCurveRunner
    private let identity = ProcessIdentity()
    private let now: () -> Date
    private var context: ModuleContext?
    private var pollTimer: ScheduledAction?
    private var readTask: Task<Void, Never>?
    /// The runner's configuration and its steps are run one after the other, in the order they came.
    private var configureTask: Task<Void, Never>?
    private var curveStepTask: Task<Void, Never>?
    /// What the published strip shows; nil when there is none.
    private var stripShown: StripContent?
    /// Tabs on screen: each screen has its own notch, so more than one can show this tab at a time.
    private var visibleTabs = 0

    private struct StripContent: Equatable {
        var temperature: Bool
        var memory: Bool
    }

    /// What the next read has to ask for: nothing that nobody is looking at.
    private struct Demand {
        var thermal: Bool
        var memory: Bool
        var cpu: Bool
        var processes: Bool
    }

    /// The helper manager is passed in: the real one talks to the system's service manager and to a root daemon, which no test
    /// does, so the tests pass one built on fakes.
    init(
        thermal: any ThermalReading, memory: any MemoryReading, cpu: any CPUReading = SystemCPUReader(),
        helper: FanHelperManager, now: @escaping () -> Date,
        activity: any ActivityAssertion = SystemActivityAssertion()
    ) {
        self.thermal = thermal
        self.memory = memory
        self.cpu = cpu
        self.helper = helper
        self.now = now
        curve = FanCurveRunner(helper: helper, now: now, activity: activity)
        state.helper = helper
        state.curve = curve
    }

    public convenience init() {
        self.init(
            thermal: SMCThermalReader(), memory: SystemMemoryReader(), cpu: SystemCPUReader(),
            helper: FanHelperManager(
                registration: SMAppServiceRegistration(), client: XPCFanHelperClient(), bundled: { BundledFanHelper.current() },
                runningApps: { Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)) }
            ),
            now: { .now }
        )
    }

    /// Whether a read is on its way (for tests).
    var isReading: Bool { readTask != nil }

    var actions: PerformanceTabActions {
        PerformanceTabActions(appeared: { [weak self] in self?.tabAppeared() }, disappeared: { [weak self] in self?.tabDisappeared() })
    }

    public func start(_ context: ModuleContext) async throws(ModuleError) {
        state.hasThermal = await thermal.isAvailable()
        self.context = context
        settingsChanged()
        let settings = context.settings
        let keys = PerformanceSettingsKeys(settings)
        context.run { [weak self] in
            for await _ in Observations({ keys.values(settings) }) {
                self?.settingsChanged()
            }
        }
        // An installed helper that is not the one in this app is registered again; one that was never installed is left alone.
        let helper = helper
        context.run { await helper.checkAtLaunch() }
    }

    public func stop() async {
        stopPolling()
        readTask?.cancel()
        readTask = nil
        curveStepTask?.cancel()
        curveStepTask = nil
        await configureTask?.value
        configureTask = nil
        // The fans go back to Apple before the module goes.
        await curve.stop()
        state.curveWanted = false
        context = nil
        stripShown = nil
        visibleTabs = 0
        state.hasThermal = false
        state.thermal = nil
        state.history.removeAll()
        state.usage = nil
        state.processes = []
        state.cpuUsage = nil
        state.cpuProcesses = []
        state.isTabVisible = false
        state.stripTemperature = false
        state.stripMemory = false
        await thermal.shutdown()
    }

    public func makeTab() -> NotchTab? {
        NotchTab(
            id: descriptor.id, title: "Hiệu năng", systemImage: "gauge.with.dots.needle.50percent",
            preferredHeight: PerformanceTabView.preferredHeight,
            content: AnyView(PerformanceTabView(state: state, actions: actions))
        )
    }

    public func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView? {
        let keys = PerformanceSettingsKeys(environment.settings)
        let thermal = thermal
        return AnyView(PerformanceSettingsView(
            stripTemperature: environment.settings.binding(keys.stripTemperature),
            stripMemory: environment.settings.binding(keys.stripMemory),
            helper: helper,
            probe: environment.settings.binding(keys.fanProbe),
            fanMode: environment.settings.binding(keys.fanMode),
            curveStart: environment.settings.binding(keys.curveStart),
            curveFull: environment.settings.binding(keys.curveFull),
            curve: curve,
            readAppFans: { await thermal.read()?.fans ?? [] }
        ))
    }

    // MARK: Visibility

    private func tabAppeared() {
        guard context != nil else { return }
        visibleTabs += 1
        state.isTabVisible = true
        updatePolling()
        let helper = helper
        Task { await helper.refresh() }
    }

    private func tabDisappeared() {
        visibleTabs = max(0, visibleTabs - 1)
        guard visibleTabs == 0 else { return }
        state.isTabVisible = false
        updatePolling()
    }

    private func settingsChanged() {
        guard let context else { return }
        let values = PerformanceSettingsKeys(context.settings).values(context.settings)
        state.stripTemperature = state.hasThermal && values.stripTemperature
        state.stripMemory = values.stripMemory
        state.curveWanted = values.fanMode == .curve
        syncStrip(context)
        configureCurve(values)
        updatePolling()
    }

    /// The strip is published when it turns on and again when what it shows changes, and its views follow the state; setting it
    /// at every read would make the notch redraw every two seconds.
    private func syncStrip(_ context: ModuleContext) {
        let wanted = state.stripTemperature || state.stripMemory
            ? StripContent(temperature: state.stripTemperature, memory: state.stripMemory) : nil
        guard wanted != stripShown else { return }
        stripShown = wanted
        if let wanted {
            context.activities.set(PerformanceActivity.strip(state: state, temperature: wanted.temperature, memory: wanted.memory))
        } else {
            context.activities.clear(id: Self.activityID)
        }
    }

    private func configureCurve(_ values: PerformanceSettingsValues) {
        let previous = configureTask
        let curve = curve
        configureTask = Task {
            await previous?.value
            await curve.configure(mode: values.fanMode, curve: values.curve, mechanism: values.probe.mechanism)
        }
    }

    // MARK: Polling

    private var demand: Demand {
        let tab = visibleTabs > 0
        return Demand(
            thermal: state.hasThermal && (tab || state.stripTemperature || state.curveWanted),
            memory: tab || state.stripMemory,
            cpu: tab,
            processes: tab
        )
    }

    private var needsPolling: Bool { demand.thermal || demand.memory || demand.cpu }

    /// Starts reading when something needs it and nothing is reading yet, and stops the next read from being scheduled when
    /// nothing does. A read that is already on its way finishes, but schedules nothing.
    private func updatePolling() {
        guard context != nil else { return }
        dropWhatNobodyShows()
        guard needsPolling else {
            stopPolling()
            return
        }
        if readTask == nil && pollTimer == nil { beginRead() }
    }

    /// Numbers nobody is looking at are not kept: they would be old by the time the tab opens again, and shown as if they were
    /// current until the first new read.
    private func dropWhatNobodyShows() {
        let demand = demand
        if !demand.thermal { state.thermal = nil }
        if !demand.cpu { state.cpuUsage = nil }
        if !demand.memory { state.usage = nil }
        if !demand.processes { state.processes = []; state.cpuProcesses = [] }
    }

    private func stopPolling() {
        pollTimer?.cancel()
        pollTimer = nil
    }

    private func beginRead() {
        let (thermal, memory, cpu, demand) = (thermal, memory, cpu, demand)
        readTask = Task { [weak self] in
            let snapshot = demand.thermal ? await thermal.read() : nil
            let memorySnapshot = demand.memory ? await memory.read(topProcesses: demand.processes ? Self.processCount : 0) : nil
            let cpuSnapshot = demand.cpu ? await cpu.read(topProcesses: demand.processes ? Self.processCount : 0) : nil
            guard !Task.isCancelled else { return }
            self?.finishRead(thermal: snapshot, memory: memorySnapshot, cpu: cpuSnapshot, listedProcesses: demand.processes)
        }
    }

    /// Keeps what is still wanted now, which may be less than was asked for when the read began.
    private func finishRead(thermal: ThermalSnapshot?, memory: MemorySnapshot?, cpu: CPUSnapshot?, listedProcesses: Bool) {
        readTask = nil
        guard let context else { return }
        let demand = demand
        if demand.thermal, let thermal { apply(thermal) }
        if demand.memory, let memory { apply(memory, listedProcesses: listedProcesses && demand.processes) }
        if demand.cpu, let cpu { apply(cpu, listedProcesses: listedProcesses && demand.processes) }
        guard needsPolling else { return }
        // The user approving the helper in System Settings sends nothing; the tick is the chance to see it.
        if helper.phase == .needsApproval {
            let helper = helper
            Task { await helper.refresh() }
        }
        pollTimer = context.scheduler.schedule(after: Self.pollInterval) { [weak self] in
            self?.pollTimer = nil
            self?.beginRead()
        }
    }

    private func apply(_ snapshot: ThermalSnapshot) {
        state.thermal = snapshot
        if let soc = snapshot.soc { state.history.append(soc, at: now()) }
        // The curve is fed at every reading, one at a time: a step still running skips this one, and the next is two seconds away.
        if state.curveWanted, curveStepTask == nil {
            let curve = curve
            curveStepTask = Task { [weak self] in
                await curve.step(snapshot)
                self?.curveStepTask = nil
            }
        }
    }

    /// A read that failed keeps the last numbers; a list is replaced only by a read that asked for one.
    private func apply(_ snapshot: MemorySnapshot, listedProcesses: Bool) {
        if let usage = snapshot.usage { state.usage = usage }
        if listedProcesses { state.processes = identity.rows(for: snapshot.processes) }
    }

    private func apply(_ snapshot: CPUSnapshot, listedProcesses: Bool) {
        if let usage = snapshot.usagePercent { state.cpuUsage = usage }
        if listedProcesses && !snapshot.processes.isEmpty {
            state.cpuProcesses = identity.rows(for: snapshot.processes)
        }
    }
}
