import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import SystemActivitiesModule

@Suite struct SystemActivitiesModuleTests {
    final class Fakes {
        let bluetooth = FakeBluetoothMonitor()
        let volume = FakeVolumeMonitor()
        let capsLock = FakeCapsLockMonitor()
        let network = FakeNetworkMonitor()
        let downloads = FakeDownloadsWatcher()

        var monitors: SystemMonitors {
            SystemMonitors(bluetooth: bluetooth, volume: volume, capsLock: capsLock, network: network, downloads: downloads)
        }
    }

    static let wifi = NetworkStatus(isConnected: true, interface: .wifi, isExpensive: false)
    static let offline = NetworkStatus(isConnected: false, interface: .none, isExpensive: false)

    let fakes = Fakes()
    let harness: RegistryHarness

    init() {
        let fakes = fakes
        harness = RegistryHarness([SystemActivitiesModule(makeMonitors: { _ in fakes.monitors })])
    }

    /// Downloads start after the module has: the folder probe runs off the main thread.
    func start() async {
        await harness.registry.bootstrap()
        await settle { fakes.downloads.startCount > 0 }
    }

    func setting(_ name: String, _ value: Bool) {
        harness.settings.set(value, for: SettingKey("module.system.\(name)", default: true))
    }

    func settle(until condition: () -> Bool) async {
        for _ in 0..<100 where !condition() { await Task.yield() }
    }

    var entries: [ActivityCenter.Entry] { harness.activities.entries }

    @Test func describesItself() {
        let descriptor = SystemActivitiesModule().descriptor
        #expect(descriptor.id == "system")
        #expect(descriptor.displayName == "Hệ thống")
        #expect(descriptor.systemImage == "gauge.with.dots.needle.33percent")
        #expect(descriptor.order == 700)
        #expect(descriptor.permissions.isEmpty)
        #expect(descriptor.optionalPermissions == [.bluetooth])
        #expect(descriptor.defaultEnabled)
    }

    @Test func startsEveryMonitorAndStopsThemAll() async {
        await start()
        #expect(harness.registry.state(of: "system") == .running)
        #expect([fakes.bluetooth.isRunning, fakes.volume.isRunning, fakes.capsLock.isRunning, fakes.network.isRunning, fakes.downloads.isRunning] == Array(repeating: true, count: 5))
        await harness.registry.setEnabled(false, for: "system")
        #expect([fakes.bluetooth.isRunning, fakes.volume.isRunning, fakes.capsLock.isRunning, fakes.network.isRunning, fakes.downloads.isRunning] == Array(repeating: false, count: 5))
    }

    @Test func eachKindPublishesItsOwnActivityThatExpires() async {
        await start()
        fakes.bluetooth.send(BluetoothEvent(name: "Buds", kind: .headphones, connected: true, battery: .single(80)))
        fakes.capsLock.send(true)
        fakes.downloads.send(DownloadEvent(url: URL(fileURLWithPath: "/d/a.zip"), name: "a.zip"))
        fakes.volume.send(level: 0.4)
        fakes.network.send(Self.wifi)
        #expect(Set(entries.map(\.id)) == ["system/bluetooth", "system/capslock", "system/download", "system/volume", "system/network"])
        #expect(entries.allSatisfy { $0.activity.priority == .normal && $0.activity.expiresAfter == .seconds(2.5) })
        harness.scheduler.advance(by: .milliseconds(2_499))
        #expect(entries.count == 5)
        harness.scheduler.advance(by: .milliseconds(1))
        #expect(entries.isEmpty)
    }

    @Test func durationSecondsSetsTheExpiryAndIsClamped() async {
        await start()
        harness.settings.set(4.0, for: SettingKey("module.system.durationSeconds", default: 2.5, clampedTo: 1...6))
        fakes.capsLock.send(true)
        #expect(entries.first?.activity.expiresAfter == .seconds(4))
        harness.settings.set(30.0, for: SettingKey("module.system.durationSeconds", default: 2.5, clampedTo: 1...6))
        fakes.capsLock.send(false)
        #expect(entries.first?.activity.expiresAfter == .seconds(6))
    }

    @Test func rapidVolumeChangesUpdateOneActivityInPlace() async {
        await start()
        fakes.volume.send(level: 0.2)
        harness.scheduler.advance(by: .seconds(2))
        fakes.volume.send(level: 0.3)
        harness.scheduler.advance(by: .seconds(2))
        #expect(entries.map(\.id) == ["system/volume"])
        harness.scheduler.advance(by: .seconds(1))
        #expect(entries.isEmpty)
    }

    @Test func networkLostStaysUntilReconnected() async {
        await start()
        fakes.network.send(Self.offline)
        #expect(entries.map(\.id) == ["system/network"])
        #expect(entries.first?.activity.priority == .high)
        #expect(entries.first?.activity.expiresAfter == nil)
        harness.scheduler.advance(by: .seconds(60))
        #expect(entries.count == 1)
        fakes.network.send(Self.wifi)
        #expect(entries.count == 1)
        #expect(entries.first?.activity.priority == .normal)
        harness.scheduler.advance(by: .seconds(3))
        #expect(entries.isEmpty)
    }

    @Test func aBatteryReadLaterUpdatesTheBluetoothActivityInPlace() async {
        await start()
        fakes.bluetooth.send(BluetoothEvent(name: "Buds", kind: .headphones, connected: true, battery: nil))
        let nameOnly = entries.first
        fakes.bluetooth.send(BluetoothEvent(name: "Buds", kind: .headphones, connected: true, battery: .single(60)))
        #expect(entries.map(\.id) == ["system/bluetooth"])
        // `Entry` equality includes the revision, which every `set` bumps, so this shows the entry was replaced.
        #expect(entries.first != nameOnly)
    }

    /// The monitor reads a late battery on `BluetoothBatteryRetry`'s schedule, so use it with the same clock as the activities.
    @Test(arguments: [(seconds: 2.5, readableAt: 1.2), (seconds: 1.0, readableAt: 0.2)])
    func aLateBatteryReadUpdatesTheVisibleBluetoothActivityBeforeItExpires(seconds: Double, readableAt: Double) async {
        await start()
        harness.settings.set(seconds, for: SettingKey("module.system.durationSeconds", default: 2.5, clampedTo: 1...6))
        let bluetooth = fakes.bluetooth
        final class Reading { var battery: BluetoothBattery? }
        let reading = Reading()
        func event(_ battery: BluetoothBattery?) -> BluetoothEvent {
            BluetoothEvent(name: "Buds", kind: .headphones, connected: true, battery: battery)
        }
        let retry = BluetoothBatteryRetry(scheduler: harness.scheduler)
        bluetooth.send(event(nil))
        retry.start(key: "aa", read: { reading.battery }, deliver: { bluetooth.send(event($0)) })
        harness.scheduler.advance(by: .seconds(readableAt))
        reading.battery = .single(60)
        harness.scheduler.advance(by: .seconds(seconds + 0.05 - readableAt))
        // Past the name-only activity's own expiry: only an update in place keeps the entry.
        #expect(entries.map(\.id) == ["system/bluetooth"])
    }

    @Test func aDownloadsStartWaitingOnAPromptDoesNotHoldBackTheModuleOrTheOtherMonitors() async {
        fakes.downloads.holdsStart = true
        await start()
        #expect(harness.registry.state(of: "system") == .running)
        #expect(fakes.network.isRunning)
        #expect(fakes.downloads.startCount == 1)
        #expect(!fakes.downloads.isRunning)
        fakes.capsLock.send(true)
        #expect(entries.map(\.id) == ["system/capslock"])

        fakes.downloads.finishStarts()
        await settle { fakes.downloads.isRunning }
        #expect(fakes.downloads.isRunning)
        fakes.downloads.send(DownloadEvent(url: URL(fileURLWithPath: "/d/a.zip"), name: "a.zip"))
        #expect(Set(entries.map(\.id)) == ["system/capslock", "system/download"])
    }

    @Test func aRefusalThatArrivesAfterTheKindWasTurnedOffAndOnIsNotHeldAgainstTheNewStart() async {
        fakes.downloads.holdsStart = true
        fakes.downloads.canStart = false
        await start()
        setting("downloads", false)
        setting("network", false)
        // The network monitor stopping shows the module has seen the settings with downloads already off.
        await settle { !fakes.network.isRunning }
        fakes.downloads.canStart = true
        setting("downloads", true)
        await settle { fakes.downloads.startCount == 2 }
        #expect(fakes.downloads.startCount == 2)

        fakes.downloads.finishStarts()
        await settle { fakes.downloads.isRunning }
        #expect(fakes.downloads.isRunning)
        // Had the first start's refusal counted, the module would think downloads never ran and leave this watcher on.
        setting("downloads", false)
        await settle { !fakes.downloads.isRunning }
        #expect(!fakes.downloads.isRunning)
    }

    @Test func aFailedDownloadWatcherDoesNotBreakTheOthers() async {
        fakes.downloads.canStart = false
        await start()
        #expect(harness.registry.state(of: "system") == .running)
        fakes.capsLock.send(true)
        #expect(entries.map(\.id) == ["system/capslock"])
    }

    @Test func aKindThatFailedToStartIsOnlyRetriedWhenItsOwnToggleChanges() async {
        fakes.downloads.canStart = false
        await start()
        #expect(fakes.downloads.startCount == 1)
        setting("volume", false)
        await settle { !fakes.volume.isRunning }
        #expect(!fakes.volume.isRunning)
        #expect(fakes.downloads.startCount == 1)
        fakes.downloads.canStart = true
        setting("downloads", false)
        setting("network", false)
        // The network monitor stopping shows the module has seen the settings with downloads already off.
        await settle { !fakes.network.isRunning }
        setting("downloads", true)
        await settle { fakes.downloads.isRunning }
        #expect(fakes.downloads.isRunning)
        #expect(fakes.downloads.startCount == 2)
    }

    @Test(arguments: [
        ("bluetooth", "bluetooth"), ("network", "network"), ("capsLock", "capslock"),
        ("downloads", "download"), ("volume", "volume"),
    ])
    func turningAKindOffStopsItsMonitorAndClearsItsActivity(setting name: String, activity: String) async {
        await start()
        send(activity)
        #expect(entries.map(\.id) == ["system/\(activity)"])
        setting(name, false)
        await settle { entries.isEmpty }
        #expect(entries.isEmpty)
        #expect(running(name) == false)
        #expect(Set(allRunning.filter { $0.value }.keys) == Set(allRunning.keys).subtracting([name]))
        send(activity)
        #expect(entries.isEmpty)
        setting(name, true)
        await settle { running(name) }
        #expect(running(name))
        send(activity)
        #expect(entries.map(\.id) == ["system/\(activity)"])
    }

    @Test func monitorsOfDisabledKindsNeverStart() async {
        setting("bluetooth", false)
        setting("downloads", false)
        await start()
        #expect(!fakes.bluetooth.isRunning)
        #expect(!fakes.downloads.isRunning)
        #expect(fakes.network.isRunning)
        // Starting Bluetooth is what raises its permission prompt, so a start followed by a stop is not good enough.
        #expect(fakes.bluetooth.startCount == 0)
        #expect(fakes.downloads.startCount == 0)
    }

    @Test func settingsRowsExistBeforeTheModuleStarts() {
        #expect(harness.registry.settingsView(for: "system") != nil)
    }

    func send(_ activity: String) {
        switch activity {
        case "bluetooth": fakes.bluetooth.send(BluetoothEvent(name: "Buds", kind: .headphones, connected: false, battery: nil))
        case "network": fakes.network.send(Self.wifi)
        case "capslock": fakes.capsLock.send(true)
        case "download": fakes.downloads.send(DownloadEvent(url: URL(fileURLWithPath: "/d/a"), name: "a"))
        default: fakes.volume.send(level: 0.5)
        }
    }

    var allRunning: [String: Bool] {
        ["bluetooth": fakes.bluetooth.isRunning, "network": fakes.network.isRunning, "capsLock": fakes.capsLock.isRunning,
         "downloads": fakes.downloads.isRunning, "volume": fakes.volume.isRunning]
    }

    func running(_ name: String) -> Bool { allRunning[name] ?? false }
}
