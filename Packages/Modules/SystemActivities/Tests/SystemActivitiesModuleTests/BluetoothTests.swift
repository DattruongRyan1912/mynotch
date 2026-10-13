import Foundation
import Testing
@testable import SystemActivitiesModule

@Suite struct BluetoothKindTests {
    @Test func audioDevicesMapToHeadphones() {
        #expect(BluetoothDeviceKind(major: 4, minor: 1) == .headphones)  // wearable headset
        #expect(BluetoothDeviceKind(major: 4, minor: 2) == .headphones)  // hands-free
        #expect(BluetoothDeviceKind(major: 4, minor: 6) == .headphones)  // headphones
        #expect(BluetoothDeviceKind(major: 4, minor: 5) == .other)  // loudspeaker
    }

    @Test func peripheralsMapByTheirUpperMinorBits() {
        #expect(BluetoothDeviceKind(major: 5, minor: 0x10) == .keyboard)
        #expect(BluetoothDeviceKind(major: 5, minor: 0x20) == .mouse)
        #expect(BluetoothDeviceKind(major: 5, minor: 0x25) == .mouse)
        #expect(BluetoothDeviceKind(major: 5, minor: 0x30) == .keyboard)  // keyboard/pointing combo
        #expect(BluetoothDeviceKind(major: 5, minor: 0x00) == .other)
    }

    @Test func otherClassesMapToOther() {
        #expect(BluetoothDeviceKind(major: 1, minor: 1) == .other)
        #expect(BluetoothDeviceKind(major: 0, minor: 0) == .other)
    }
}

@Suite struct BluetoothBatteryTests {
    @Test func aSingleValueIsUsedWhenThereAreNoPods() {
        #expect(BluetoothBattery.select(single: 80, left: nil, right: nil, case: nil) == .single(80))
    }

    @Test func leftRightAndCaseWinOverSingle() {
        #expect(BluetoothBattery.select(single: 50, left: 70, right: 60, case: 90)
            == .pods(left: 70, right: 60, case: 90))
    }

    @Test func missingPartsStayNil() {
        #expect(BluetoothBattery.select(single: nil, left: 70, right: nil, case: nil)
            == .pods(left: 70, right: nil, case: nil))
    }

    @Test func valuesOutsideOneToHundredAreNil() {
        #expect(BluetoothBattery.select(single: 0, left: 0, right: 101, case: -1) == nil)
        #expect(BluetoothBattery.select(single: 100, left: 0, right: nil, case: nil) == .single(100))
        #expect(BluetoothBattery.select(single: nil, left: 1, right: 255, case: nil)
            == .pods(left: 1, right: nil, case: nil))
    }

    @Test func aLoneCaseValueIsNotABatteryReading() {
        #expect(BluetoothBattery.select(single: nil, left: nil, right: nil, case: 80) == nil)
    }

    @Test func readsOnlySelectorsTheObjectRespondsTo() {
        #expect(BluetoothBattery.read(from: NSObject()) == nil)
        #expect(BluetoothBattery.read(from: SingleBatteryObject()) == .single(42))
        #expect(BluetoothBattery.read(from: PodsBatteryObject()) == .pods(left: 30, right: 40, case: 90))
    }
}

private final class SingleBatteryObject: NSObject {
    @objc let batteryPercentSingle: Int = 42
}

private final class PodsBatteryObject: NSObject {
    @objc let batteryPercentSingle: Int = 0
    @objc let batteryPercentLeft: Int = 30
    @objc let batteryPercentRight: Int = 40
    @objc let batteryPercentCase: Int = 90
}

@Suite struct BluetoothConnectionTrackerTests {
    @Test func devicesConnectedAtStartAreNotAnnouncedAgain() {
        let tracker = BluetoothConnectionTracker(connectedAtStart: ["aa"])
        #expect(!tracker.announcesConnection(of: "aa"))
        #expect(tracker.announcesConnection(of: "bb"))
    }

    @Test func aDeviceThatDisconnectedAndReconnectsIsAnnounced() {
        var tracker = BluetoothConnectionTracker(connectedAtStart: ["aa"])
        tracker.disconnected("aa")
        #expect(tracker.announcesConnection(of: "aa"))
    }
}

@Suite struct BluetoothBatteryDisplayTests {
    @Test func singleShowsItsValue() {
        #expect(BluetoothBattery.single(80).displayPercent == 80)
    }

    @Test func podsShowTheLowerEarbud() {
        #expect(BluetoothBattery.pods(left: 70, right: 55, case: 90).displayPercent == 55)
        #expect(BluetoothBattery.pods(left: nil, right: 55, case: nil).displayPercent == 55)
    }
}
