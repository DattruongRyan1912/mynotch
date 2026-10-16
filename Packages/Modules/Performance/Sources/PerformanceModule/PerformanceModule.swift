import Foundation
import MyNotchCore
import NotchUI
import SwiftUI

/// What the Mac is doing: its temperatures and fan speeds, read-only. Reads only while something shows them (the tab, or
/// the strip beside the collapsed notch), every two seconds, and none of it on the main actor.
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

    let state = PerformanceState()
    private let thermal: any ThermalReading
    private let now: () -> Date
    private var context: ModuleContext?
    private var pollTimer: ScheduledAction?
    private var readTask: Task<Void, Never>?
    private var stripPublished = false
    /// Tabs on screen: each screen has its own notch, so more than one can show this tab at a time.
    private var visibleTabs = 0

    init(thermal: any ThermalReading, now: @escaping () -> Date) {
        self.thermal = thermal
        self.now = now
    }

    public convenience init() { self.init(thermal: SMCThermalReader(), now: { .now }) }

    /// Whether a read is on its way (for tests).
    var isReading: Bool { readTask != nil }

    var actions: PerformanceTabActions {
        PerformanceTabActions(appeared: { [weak self] in self?.tabAppeared() }, disappeared: { [weak self] in self?.tabDisappeared() })
    }

    public func start(_ context: ModuleContext) async throws(ModuleError) {
        guard await thermal.isAvailable() else {
            throw .unavailable(reason: "Không mở được cảm biến nhiệt độ của máy")
        }
        self.context = context
        settingsChanged()
        let settings = context.settings
        let keys = PerformanceSettingsKeys(settings)
        context.run { [weak self] in
            for await _ in Observations({ settings.value(keys.stripTemperature) }) {
                self?.settingsChanged()
            }
        }
    }

    public func stop() async {
        stopPolling()
        readTask?.cancel()
        readTask = nil
        context = nil
        stripPublished = false
        visibleTabs = 0
        state.thermal = nil
        state.history.removeAll()
        state.isTabVisible = false
        state.stripTemperature = false
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
        return AnyView(PerformanceSettingsView(stripTemperature: environment.settings.binding(keys.stripTemperature)))
    }

    // MARK: Visibility

    private func tabAppeared() {
        guard context != nil else { return }
        visibleTabs += 1
        state.isTabVisible = true
        updatePolling()
    }

    private func tabDisappeared() {
        visibleTabs = max(0, visibleTabs - 1)
        guard visibleTabs == 0 else { return }
        state.isTabVisible = false
        updatePolling()
    }

    private func settingsChanged() {
        guard let context else { return }
        state.stripTemperature = context.settings.value(PerformanceSettingsKeys(context.settings).stripTemperature)
        syncStrip(context)
        updatePolling()
    }

    /// The strip is published once, when it turns on, and its views follow the state; setting it at every read would make the
    /// notch redraw every two seconds.
    private func syncStrip(_ context: ModuleContext) {
        let wanted = state.stripTemperature
        guard wanted != stripPublished else { return }
        stripPublished = wanted
        if wanted {
            context.activities.set(PerformanceActivity.strip(state: state))
        } else {
            context.activities.clear(id: Self.activityID)
        }
    }

    // MARK: Polling

    private var needsPolling: Bool { visibleTabs > 0 || state.stripTemperature }

    /// Starts reading when something needs it and nothing is reading yet, and stops the next read from being scheduled when
    /// nothing does. A read that is already on its way finishes and is kept, but schedules nothing.
    private func updatePolling() {
        guard context != nil else { return }
        guard needsPolling else {
            stopPolling()
            return
        }
        if readTask == nil && pollTimer == nil { beginRead() }
    }

    private func stopPolling() {
        pollTimer?.cancel()
        pollTimer = nil
    }

    private func beginRead() {
        let reader = thermal
        readTask = Task { [weak self] in
            let snapshot = await reader.read()
            guard !Task.isCancelled else { return }
            self?.finishRead(snapshot)
        }
    }

    private func finishRead(_ snapshot: ThermalSnapshot?) {
        readTask = nil
        guard let context else { return }
        if let snapshot { apply(snapshot) }
        guard needsPolling else { return }
        pollTimer = context.scheduler.schedule(after: Self.pollInterval) { [weak self] in
            self?.pollTimer = nil
            self?.beginRead()
        }
    }

    private func apply(_ snapshot: ThermalSnapshot) {
        state.thermal = snapshot
        if let soc = snapshot.soc { state.history.append(soc, at: now()) }
    }
}
