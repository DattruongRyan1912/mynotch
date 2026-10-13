import Foundation
import Testing
@testable import SystemActivitiesModule

@Suite struct SystemActivityContentTests {
    @Test func bluetoothConnectedShowsBatteryOrTheShortName() {
        let withBattery = SystemActivityContent.bluetooth(
            BluetoothEvent(name: "AirPods Pro", kind: .headphones, connected: true, battery: .pods(left: 70, right: 55, case: 90)))
        #expect(withBattery.id == "bluetooth")
        #expect(withBattery.glyph == .symbol("headphones"))
        #expect(withBattery.trailing == .text("55%"))

        let noBattery = SystemActivityContent.bluetooth(
            BluetoothEvent(name: "Magic Keyboard", kind: .keyboard, connected: true, battery: nil))
        #expect(noBattery.glyph == .symbol("keyboard"))
        #expect(noBattery.trailing == .text("Magic Ke"))
    }

    @Test func bluetoothDisconnectedSaysSo() {
        let content = SystemActivityContent.bluetooth(BluetoothEvent(name: "Mouse", kind: .mouse, connected: false, battery: nil))
        #expect(content.glyph == .symbol("computermouse"))
        #expect(content.trailing == .text("Đã ngắt"))
    }

    @Test func networkConnectedNamesTheInterface() {
        let wifi = SystemActivityContent.network(NetworkStatus(isConnected: true, interface: .wifi, isExpensive: false))
        #expect((wifi.glyph, wifi.trailing, wifi.priority, wifi.expires) == (.symbol("wifi"), .text("Đã kết nối"), .normal, true))
        let wired = SystemActivityContent.network(NetworkStatus(isConnected: true, interface: .ethernet, isExpensive: false))
        #expect(wired.glyph == .symbol("cable.connector"))
    }

    @Test func networkLostIsHighPriorityAndStays() {
        let lost = SystemActivityContent.network(NetworkStatus(isConnected: false, interface: .none, isExpensive: false))
        #expect((lost.glyph, lost.trailing, lost.priority, lost.expires) == (.symbol("wifi.slash"), .text("Mất mạng"), .high, false))
    }

    @Test func capsLockShowsTheGlyphAndState() {
        #expect(SystemActivityContent.capsLock(true).glyph == .text("⇪"))
        #expect(SystemActivityContent.capsLock(true).trailing == .text("Bật"))
        #expect(SystemActivityContent.capsLock(false).trailing == .text("Tắt"))
    }

    @Test func downloadShowsTheFileName() {
        let content = SystemActivityContent.download(DownloadEvent(url: URL(fileURLWithPath: "/d/report.pdf"), name: "report.pdf"))
        #expect((content.id, content.glyph, content.trailing) == ("download", .symbol("arrow.down.circle"), .text("report.pdf")))
    }

    @Test func volumePicksTheSpeakerAndShowsTheLevel() {
        #expect(SystemActivityContent.volume(VolumeState(level: 0.8, muted: false)).glyph == .symbol("speaker.wave.3.fill"))
        #expect(SystemActivityContent.volume(VolumeState(level: 0.5, muted: false)).glyph == .symbol("speaker.wave.2.fill"))
        #expect(SystemActivityContent.volume(VolumeState(level: 0.1, muted: false)).glyph == .symbol("speaker.wave.1.fill"))
        #expect(SystemActivityContent.volume(VolumeState(level: 0.8, muted: false)).trailing == .level(0.8))
        let muted = SystemActivityContent.volume(VolumeState(level: 0.8, muted: true))
        #expect((muted.glyph, muted.trailing) == (.symbol("speaker.slash.fill"), .level(0)))
        #expect(SystemActivityContent.volume(VolumeState(level: 0, muted: false)).glyph == .symbol("speaker.slash.fill"))
    }
}
