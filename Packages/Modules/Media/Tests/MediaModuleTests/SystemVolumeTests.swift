import Foundation
import Testing
@testable import MediaModule

/// Stands in for the default output device: no test reads or changes the real volume.
final class FakeVolumeDevice: VolumeDevice {
    var current: Float?
    /// A device whose volume cannot be set.
    var refusesWrites = false
    private(set) var writes: [Float] = []
    private var observers: [Int: @MainActor () -> Void] = [:]
    private var nextID = 0

    init(level: Float? = 0.5) { current = level }

    var observerCount: Int { observers.count }

    func level() -> Float? { current }

    func setLevel(_ level: Float) -> Bool {
        writes.append(level)
        guard !refusesWrites, current != nil else { return false }
        current = level
        return true
    }

    func observe(_ onChange: @escaping @MainActor () -> Void) -> () -> Void {
        let id = nextID
        nextID += 1
        observers[id] = onChange
        return { [weak self] in self?.observers[id] = nil }
    }

    /// The system says the volume or the default device changed.
    func fireChange() {
        for observer in observers.values { observer() }
    }
}

@Suite struct VolumeModelTests {
    let device = FakeVolumeDevice(level: 0.5)

    @Test func theLevelIsWhatTheDeviceSaysOnceRefreshed() {
        let model = VolumeModel(device: device)
        #expect(model.level == nil, "nothing is read before a view asks")
        model.refresh()
        #expect(model.level == 0.5)
        #expect(model.isAvailable)
        device.current = 0.8
        model.refresh()
        #expect(model.level == 0.8)
    }

    @Test func aDeviceWithoutAVolumeIsUnavailable() {
        let model = VolumeModel(device: FakeVolumeDevice(level: nil))
        model.refresh()
        #expect(model.level == nil)
        #expect(!model.isAvailable)
        model.set(0.5)
        #expect(model.level == nil)
    }

    @Test func theSlidersPositionIsTheDevicesScalarAndPercentIsItRounded() {
        let model = VolumeModel(device: device)
        model.refresh()
        model.set(0.25)
        #expect(device.writes == [0.25])
        #expect(model.level == 0.25)
        #expect(model.percent == 25)
        device.current = 0.504
        model.refresh()
        #expect(model.percent == 50)
        device.current = 0.506
        model.refresh()
        #expect(model.percent == 51)
        #expect(VolumeModel(device: FakeVolumeDevice(level: nil)).percent == nil)
    }

    @Test func aPositionOutsideTheSliderIsClampedToSilenceAndFull() {
        let model = VolumeModel(device: device)
        model.refresh()
        model.set(1.7)
        model.set(-0.2)
        #expect(device.writes == [1, 0])
        #expect(model.level == 0)
    }

    @Test func notANumberIsNeverWritten() {
        let model = VolumeModel(device: device)
        model.refresh()
        model.set(.nan)
        model.set(.infinity)
        #expect(device.writes.isEmpty)
        #expect(model.level == 0.5)
    }

    @Test func theSameLevelIsNotWrittenAgain() {
        let model = VolumeModel(device: device)
        model.refresh()
        model.set(0.5)
        #expect(device.writes.isEmpty, "a drag reports the same position many times")
        model.set(0.6)
        model.set(0.6)
        #expect(device.writes == [0.6])
    }

    @Test func aWriteTheDeviceRefusesIsReadBackSoTheSliderShowsTheTruth() {
        device.refusesWrites = true
        let model = VolumeModel(device: device)
        model.refresh()
        model.set(0.9)
        #expect(device.writes == [0.9])
        #expect(model.level == 0.5)
    }

    @Test func whileWatchingTheLevelFollowsTheKeysAndTheDevice() {
        let model = VolumeModel(device: device)
        #expect(device.observerCount == 0)
        model.startWatching()
        #expect(model.level == 0.5, "it reads once as it starts")
        device.current = 0.2
        device.fireChange()
        #expect(model.level == 0.2)
        device.current = nil
        device.fireChange()
        #expect(!model.isAvailable, "the default output moved to a device without a volume")
        model.stopWatching()
        #expect(device.observerCount == 0)
        device.current = 0.9
        device.fireChange()
        #expect(model.level == nil)
    }

    @Test func watchingTwiceKeepsOneObserver() {
        let model = VolumeModel(device: device)
        model.startWatching()
        model.startWatching()
        #expect(device.observerCount == 1)
        model.stopWatching()
        model.stopWatching()
        #expect(device.observerCount == 0)
    }

    @Test func theInertDeviceTheTestsUseByDefaultHasNoVolume() {
        let model = VolumeModel(device: NoVolumeDevice())
        model.refresh()
        #expect(!model.isAvailable)
        model.set(0.5)
        #expect(model.level == nil)
    }
}
