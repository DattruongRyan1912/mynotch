import EqualizerAudio
import Foundation
import MyNotchCore
import NotchUI
import SwiftUI

/// An equalizer for everything the Mac plays: ten bands and a preamp, per profile, applied to each output device that is
/// playing. This module owns the tab, the Settings rows and the life of the engine; the profiles and the switch are
/// `EqualizerState`, which the Nhạc tab shares.
///
/// The engine runs only while the switch is on, and never in the user's way: a tap without the system-audio permission mutes
/// its device, so on `.permissionLikelyDenied` the engine is stopped at once and the original sound plays. A device that cannot
/// be set up is reported and left alone while the others keep their EQ; only when no device works is the engine stopped. The
/// switch stays as the user set it. Only "Thử lại" and switching the EQ off and on start the engine again: opening the tab
/// does not, because with the permission still off that would silence a device for ten seconds each time.
public final class EqualizerModule: FeatureModule {
    /// On by default, like the other modules: nothing runs until the user switches the EQ on, and the Nhạc tab's EQ row
    /// exists only while this module does.
    public let descriptor = ModuleDescriptor(
        id: "equalizer",
        displayName: "Âm thanh",
        systemImage: "slider.vertical.3",
        defaultEnabled: true,
        optionalPermissions: [.systemAudio],
        permissionReasons: [.systemAudio: "Để chỉnh âm thanh của cả máy"],
        order: 210
    )

    /// Made here, not in `start`: the Settings rows read it whether or not the module runs.
    let status = EqualizerStatus()
    private let state: EqualizerState
    private let engine: any EqualizerEngine
    private let isEqMacRunning: () -> Bool
    private var context: ModuleContext?
    private var engineRunning = false
    /// The curve the engine last got, so a change that leaves it as it was does not reach the audio thread's state again.
    private var applied: EQProfile?

    init(state: EqualizerState, engine: any EqualizerEngine, isEqMacRunning: @escaping () -> Bool) {
        self.state = state
        self.engine = engine
        self.isEqMacRunning = isEqMacRunning
    }

    public convenience init(state: EqualizerState) {
        self.init(state: state, engine: PipelineManager(scheduler: TaskScheduler()), isEqMacRunning: { EqMacDetector.isRunning() })
    }

    var actions: EqualizerTabActions {
        EqualizerTabActions(
            appeared: { [weak self] in self?.tabAppeared() },
            openSettings: { [weak self] in self?.openSystemSettings() },
            retry: { [weak self] in self?.retry() }
        )
    }

    public func start(_ context: ModuleContext) async throws(ModuleError) {
        self.context = context
        state.isAvailable = true
        state.openEditor = { [weak context] in context?.presenter.open() }
        engine.onEvent = { [weak self] in self?.handle($0) }
        status.eqMacRunning = isEqMacRunning()
        syncEngine()
        let state = state
        context.run { [weak self] in
            for await _ in Observations({ state.activeProfile }) {
                self?.syncEngine()
            }
        }
    }

    public func stop() async {
        // Unconditionally: the original sound must be back whatever this module thinks the engine is doing.
        engineRunning = false
        engine.stop()
        engine.onEvent = nil
        status.reset()
        status.eqMacRunning = false
        applied = nil
        state.isAvailable = false
        state.openEditor = nil
        context = nil
    }

    public func makeTab() -> NotchTab? {
        NotchTab(
            id: descriptor.id, title: "Âm thanh", systemImage: "slider.vertical.3",
            preferredHeight: EqualizerTabView.preferredHeight, acceptsKeyboard: true,
            content: AnyView(EqualizerTabView(state: state, status: status, actions: actions))
        )
    }

    public func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView? {
        let permissions = environment.permissions
        return AnyView(EqualizerSettingsView(
            state: state, status: status, isRunning: environment.isRunning,
            openSettings: { permissions.openSystemSettings(for: .systemAudio) },
            retry: { [weak self] in self?.retry() }
        ))
    }

    // MARK: The engine

    /// Brings the engine to what the switch and the profile ask for. Safe to run again and again.
    func syncEngine() {
        guard context != nil else { return }
        guard let profile = state.activeProfile else {
            status.reset()
            stopEngine()
            return
        }
        if status.phase == .off { status.phase = .waiting }
        // Also while paused, so a restart starts with the curve the user has now.
        if profile != applied {
            applied = profile
            engine.apply(profile)
        }
        guard !status.isPaused, !engineRunning else { return }
        engineRunning = true
        engine.start()
    }

    private func stopEngine() {
        guard engineRunning else { return }
        engineRunning = false
        engine.stop()
    }

    /// The engine's reports, which arrive inside its own calls (`start`, `stop`, a timer of its own).
    ///
    /// Stopping from inside `.permissionLikelyDenied` or `.failed` is safe with `PipelineManager`: its `stop()` is complete
    /// whenever it is called, and the one thing the manager does after the event (it schedules its next silence check) ends in
    /// a check that finds the manager stopped. What `stop()` itself reports (`.devices([])`) comes back here, so the status is
    /// set first and ignores every report once the engine is not running.
    private func handle(_ event: EqualizerEngineEvent) {
        guard status.isRunning else { return }
        switch event {
        case .devices(let names):
            status.phase = names.isEmpty ? .waiting : .processing(names)
            // A device that is tuned has no failure any more. The reason starts with "<device>: ", which is the manager's own form.
            status.failures.removeAll { failure in names.contains { failure.hasPrefix($0 + ": ") } }
        case .failed(let reason):
            // `.devices` came first, so what is tuned now is what works. With nothing working every device has failed: stop,
            // and show the first reason still standing. Otherwise the others keep their EQ and the failure is only shown.
            let nothingWorks = status.tunedDevices.isEmpty
            status.failures.append(reason)
            if nothingWorks {
                status.phase = .failed(status.failures[0])
                stopEngine()
            }
        case .permissionLikelyDenied:
            status.phase = .needsPermission
            stopEngine()
        }
    }

    /// "Thử lại": a stop and a start, which also gives a device that was given up on a fresh set of tries. Devices that work
    /// are rebuilt with it, which is a gap of a moment in their sound.
    func retry() {
        guard context != nil, status.canRetry else { return }
        stopEngine()
        status.failures = []
        status.phase = .waiting
        syncEngine()
    }

    /// Each time the tab opens: looks for eqMac again and nothing else. An engine paused for the permission is not tried again
    /// by looking at the tab: with the permission still off, the new try would mute a device for ten seconds and take the hint
    /// away, so the user starts it (Thử lại, or the switch off and on).
    func tabAppeared() {
        guard context != nil else { return }
        status.eqMacRunning = isEqMacRunning()
    }

    func openSystemSettings() {
        context?.permissions.openSystemSettings(for: .systemAudio)
    }
}
