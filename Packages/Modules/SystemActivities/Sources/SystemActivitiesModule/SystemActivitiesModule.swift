import ApplicationServices
import MyNotchCore
import Observation
import SwiftUI

/// The event sources one running module listens to.
struct SystemMonitors {
    var bluetooth: any BluetoothMonitoring
    var volume: any VolumeMonitoring
    var capsLock: any CapsLockMonitoring
    var network: any NetworkMonitoring
    var downloads: any DownloadsWatching
    var mediaKeys: MediaKeyHUD

    /// Creating them touches nothing; each only reaches the system when started.
    static func live(scheduler: any Scheduler) -> SystemMonitors {
        SystemMonitors(
            bluetooth: BluetoothMonitor(scheduler: scheduler), volume: VolumeMonitor(),
            capsLock: CapsLockMonitor(scheduler: scheduler),
            network: NetworkMonitor(source: NWPathSource(), scheduler: scheduler),
            downloads: DownloadsWatcher(scheduler: scheduler),
            mediaKeys: MediaKeyHUD(
                tap: SystemEventTap(), queue: SerialHardwareQueue(), changes: HardwareChangeNotifier(),
                volume: SystemVolumeControl(), brightness: DisplayServicesBrightness(),
                keyboardLight: CoreBrightnessKeyboardLight(), isTrusted: { AXIsProcessTrusted() }, scheduler: scheduler))
    }
}

/// Short live activities for system events: Bluetooth devices, network, Caps Lock, finished downloads and volume.
/// Each kind has its own switch, and its monitor runs only while the switch is on. A further switch, off by default,
/// takes over the volume, brightness and keyboard light keys so MyNotch's bar shows instead of the macOS one.
public final class SystemActivitiesModule: FeatureModule {
    public let descriptor = ModuleDescriptor(
        id: "system",
        displayName: "Hệ thống",
        systemImage: "gauge.with.dots.needle.33percent",
        defaultEnabled: true,
        optionalPermissions: [.bluetooth, .downloadsFolder, .accessibility],
        permissionReasons: [
            .bluetooth: "Hiện thiết bị Bluetooth vừa kết nối hoặc ngắt, kèm pin.",
            .downloadsFolder: "Báo khi file tải xong trong Downloads.",
            .accessibility: "Bắt phím âm lượng, độ sáng và đèn bàn phím để hiện thanh của MyNotch thay cho HUD của macOS.",
        ],
        order: 700
    )

    private struct Kind {
        let key: SettingKey<Bool>
        /// The activities this kind shows, dropped when it is turned off; its own id when nil.
        var shows: [String]?
        /// Returns false when the monitor could not start.
        let start: () -> Bool
        let stop: () -> Void
    }

    private let makeMonitors: (any Scheduler) -> SystemMonitors
    private var context: ModuleContext?
    private var monitors: SystemMonitors?
    /// Keys of the kinds whose monitor is running. Downloads count from the moment they are asked to start.
    private var running: Set<String> = []
    private var downloadsStart: Task<Void, Never>?
    /// Keys of the kinds whose monitor could not start: retried only after their own switch is turned off and on,
    /// not on every other settings change.
    private var failed: Set<String> = []

    public convenience init() {
        self.init(makeMonitors: { SystemMonitors.live(scheduler: $0) })
    }

    init(makeMonitors: @escaping (any Scheduler) -> SystemMonitors) {
        self.makeMonitors = makeMonitors
    }

    public func start(_ context: ModuleContext) async throws(ModuleError) {
        self.context = context
        monitors = makeMonitors(context.scheduler)
        reconcile()
        let settings = context.settings
        let keys = SystemActivitiesKeys(settings)
        context.run { [weak self] in
            for await _ in Observations({
                [keys.bluetooth, keys.network, keys.capsLock, keys.downloads, keys.volume, keys.replaceHUD].map { settings.value($0) }
            }) {
                self?.reconcile()
            }
        }
    }

    public func stop() async {
        stopAll()
        monitors = nil
        context = nil
    }

    public func makeTab() -> NotchTab? { nil }

    public func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView? {
        AnyView(SystemActivitiesSettingsView(
            keys: SystemActivitiesKeys(environment.settings), settings: environment.settings, permissions: environment.permissions))
    }

    /// Starts the monitors of enabled kinds and stops the others, dropping the activity of a kind that was turned off.
    private func reconcile() {
        guard let context, let kinds = kinds() else { return }
        for (activityID, kind) in kinds {
            let wanted = context.settings.value(kind.key)
            if wanted, !running.contains(activityID), !failed.contains(activityID) {
                if kind.start() { running.insert(activityID) } else { failed.insert(activityID) }
            } else if !wanted {
                failed.remove(activityID)
                if running.contains(activityID) {
                    kind.stop()
                    running.remove(activityID)
                    for id in kind.shows ?? [activityID] { context.activities.clear(id: id) }
                }
            }
        }
    }

    private func stopAll() {
        guard let kinds = kinds() else { return }
        for (activityID, kind) in kinds where running.contains(activityID) { kind.stop() }
        running = []
        failed = []
    }

    private func kinds() -> [String: Kind]? {
        guard let context, let monitors else { return nil }
        let keys = SystemActivitiesKeys(context.settings)
        return [
            "bluetooth": Kind(
                key: keys.bluetooth,
                start: { monitors.bluetooth.start { [weak self] in self?.publish(.bluetooth($0)) }; return true },
                stop: monitors.bluetooth.stop),
            "network": Kind(
                key: keys.network,
                start: { monitors.network.start { [weak self] in self?.publish(.network($0)) }; return true },
                stop: monitors.network.stop),
            "capslock": Kind(
                key: keys.capsLock,
                start: { monitors.capsLock.start { [weak self] in self?.publish(.capsLock($0)) }; return true },
                stop: monitors.capsLock.stop),
            "download": Kind(
                key: keys.downloads,
                start: { [weak self] in self?.startDownloads(monitors.downloads); return true },
                stop: { [weak self] in self?.stopDownloads(monitors.downloads) }),
            "volume": Kind(
                key: keys.volume,
                start: { monitors.volume.start { [weak self] in self?.volumeChanged($0) }; return true },
                stop: monitors.volume.stop),
            "mediaKeys": Kind(
                key: keys.replaceHUD,
                // The HUD has no activity of its own: it shows the same bars as the volume monitor, and two more.
                shows: ["volume", "brightness", "keyboardLight"],
                start: { [weak self] in self?.startMediaKeys(monitors.mediaKeys); return true },
                stop: monitors.mediaKeys.stop),
        ]
    }

    /// The HUD without Accessibility keeps the keys with the system and waits for the permission, so this never fails.
    private func startMediaKeys(_ mediaKeys: MediaKeyHUD) {
        guard let settings = context?.settings else { return }
        let keys = SystemActivitiesKeys(settings)
        mediaKeys.start(
            enabled: { keys.mediaKeySelection(settings) },
            onChange: { [weak self] in self?.publish($0, duration: MediaKeyHUD.displayDuration) })
    }

    /// The monitor also reports the change the HUD itself made a moment ago, which would only keep its bar up longer.
    private func volumeChanged(_ state: VolumeState) {
        guard monitors?.mediaKeys.isEcho(state) != true else { return }
        publish(.volume(state))
    }

    /// The first read of Downloads blocks until the user answers macOS's access prompt, so the watcher starts in a
    /// task that suspends instead of freezing the notch. A refusal arrives later, through `downloadsFailed()`.
    private func startDownloads(_ downloads: any DownloadsWatching) {
        downloadsStart?.cancel()
        downloadsStart = Task { [weak self] in
            let started = await downloads.start { [weak self] in self?.publish(.download($0)) }
            // A cancelled start belongs to an earlier switch position; its result says nothing about this one.
            guard !Task.isCancelled else { return }
            if !started { self?.downloadsFailed() }
        }
    }

    private func stopDownloads(_ downloads: any DownloadsWatching) {
        downloadsStart?.cancel()
        downloadsStart = nil
        downloads.stop()
    }

    /// Like a monitor that failed to start: retried only after its own switch is turned off and on.
    private func downloadsFailed() {
        guard running.remove("download") != nil else { return }
        failed.insert("download")
        context?.logger.error("Downloads folder cannot be watched")
    }

    /// Shown for `duration`, or for the time set in Settings.
    private func publish(_ content: SystemActivityContent, duration: Duration? = nil) {
        guard let context else { return }
        let seconds = context.settings.value(SystemActivitiesKeys(context.settings).durationSeconds)
        context.activities.set(content.liveActivity(duration: duration ?? .seconds(seconds)))
    }
}
