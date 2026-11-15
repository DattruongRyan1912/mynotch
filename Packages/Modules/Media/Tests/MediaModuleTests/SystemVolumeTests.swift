import Foundation
import Testing
@testable import MediaModule

/// Stands in for the default output device: no test reads or changes the real volume. Only ever called through a queue.
nonisolated final class FakeVolumeHardware: VolumeHardware, @unchecked Sendable {
    var reading: VolumeReading?
    /// A device whose level cannot be set.
    var refusesLevelWrites = false
    /// A device with no mute property.
    var canMute = true
    private(set) var reads = 0
    private(set) var levelWrites: [Float] = []
    private(set) var muteWrites: [Bool] = []
    private var observers: [Int: @Sendable () -> Void] = [:]
    private var nextID = 0

    init(level: Float? = 0.5, muted: Bool = false) {
        reading = level.map { VolumeReading(level: $0, isMuted: muted) }
    }

    var observerCount: Int { observers.count }

    func read() -> VolumeReading? {
        reads += 1
        return reading
    }

    func writeLevel(_ level: Float) -> Bool {
        levelWrites.append(level)
        guard !refusesLevelWrites, reading != nil else { return false }
        reading?.level = level
        return true
    }

    func writeMuted(_ muted: Bool) -> Bool {
        muteWrites.append(muted)
        guard canMute, reading != nil else { return false }
        reading?.isMuted = muted
        return true
    }

    func observe(_ onChange: @escaping @Sendable () -> Void) -> any VolumeObservation {
        let id = nextID
        nextID += 1
        observers[id] = onChange
        return Observation { [weak self] in self?.observers[id] = nil }
    }

    /// The system says the volume, the mute or the default device changed.
    func fireChange() {
        for observer in observers.values { observer() }
    }

    private final class Observation: VolumeObservation, @unchecked Sendable {
        let onStop: @Sendable () -> Void
        init(onStop: @escaping @Sendable () -> Void) { self.onStop = onStop }
        func stop() { onStop() }
    }
}

/// A hardware queue that runs nothing until a test says so, one job at a time, so a test can look between the steps.
nonisolated final class ManualVolumeQueue: VolumeQueue, @unchecked Sendable {
    private var jobs: [@Sendable () -> Void] = []

    var pendingCount: Int { jobs.count }

    func run<T: Sendable>(_ work: @escaping @Sendable () -> T, then completion: @escaping @MainActor (T) -> Void) {
        jobs.append {
            let result = work()
            MainActor.assumeIsolated { completion(result) }
        }
    }

    /// Runs the oldest waiting job and hands its result over; false when none waits.
    @discardableResult
    func step() -> Bool {
        guard !jobs.isEmpty else { return false }
        jobs.removeFirst()()
        return true
    }

    /// Runs jobs until none is left, including the ones they start.
    func drain() {
        while step() {}
    }
}

@Suite struct VolumeModelTests {
    let hardware = FakeVolumeHardware(level: 0.5)
    let queue = ManualVolumeQueue()

    func model(_ hardware: FakeVolumeHardware? = nil) -> VolumeModel {
        VolumeModel(hardware: hardware ?? self.hardware, queue: queue)
    }

    // MARK: reading

    @Test func theLevelIsWhatTheDeviceSaysOnceTheReadReturns() {
        let model = model()
        #expect(model.level == nil, "nothing is read before a view asks")
        model.refresh()
        queue.drain()
        #expect(model.level == 0.5)
        #expect(model.isAvailable)
        hardware.reading?.level = 0.8
        model.refresh()
        queue.drain()
        #expect(model.level == 0.8)
    }

    @Test func askingForTheLevelNeverWaitsForTheDevice() {
        let model = model()
        model.refresh()
        queue.drain()
        hardware.reading?.level = 0.9
        model.refresh()
        #expect(hardware.reads == 1, "the read is queued, not made")
        #expect(model.level == 0.5, "the cached level shows meanwhile")
        queue.drain()
        #expect(model.level == 0.9, "and the answer replaces it")
    }

    @Test func aDeviceWithoutAVolumeIsUnavailable() {
        let model = model(FakeVolumeHardware(level: nil))
        model.refresh()
        queue.drain()
        #expect(model.level == nil)
        #expect(!model.isAvailable)
        model.set(0.5)
        #expect(queue.pendingCount == 0)
    }

    @Test func percentIsTheLevelRoundedToAWholeNumber() {
        let model = model()
        model.refresh()
        queue.drain()
        for (level, percent) in [(Float(0.25), 25), (0.504, 50), (0.506, 51), (0, 0), (1, 100)] {
            hardware.reading?.level = level
            model.refresh()
            queue.drain()
            #expect(model.percent == percent, "\(level)")
        }
        #expect(VolumeModel(hardware: FakeVolumeHardware(level: nil), queue: queue).percent == nil)
    }

    // MARK: setting

    @Test func theSlidersPositionIsTheDevicesScalar() {
        let model = model()
        model.refresh()
        queue.drain()
        model.set(0.25)
        #expect(model.level == 0.25, "the slider does not wait for the device")
        queue.drain()
        #expect(hardware.levelWrites == [0.25])
        #expect(model.level == 0.25)
    }

    @Test func aPositionOutsideTheSliderIsClampedToSilenceAndFull() {
        let model = model()
        model.refresh()
        queue.drain()
        model.set(1.7)
        queue.drain()
        model.set(-0.2)
        queue.drain()
        #expect(hardware.levelWrites == [1, 0])
        #expect(model.level == 0)
    }

    @Test func notANumberIsNeverWritten() {
        let model = model()
        model.refresh()
        queue.drain()
        model.set(.nan)
        model.set(.infinity)
        #expect(queue.pendingCount == 0)
        #expect(model.level == 0.5)
    }

    @Test func theSameLevelIsNotWrittenAgain() {
        let model = model()
        model.refresh()
        queue.drain()
        model.set(0.5)
        #expect(queue.pendingCount == 0, "a drag reports the same position many times")
        model.set(0.6)
        model.set(0.6)
        queue.drain()
        #expect(hardware.levelWrites == [0.6])
    }

    @Test func dragSamplesAreCoalescedTheLatestWinsAndOneWriteIsInFlight() {
        let model = model()
        model.refresh()
        queue.drain()
        for sample in [Float(0.1), 0.2, 0.3, 0.4] {
            model.set(sample)
            #expect(queue.pendingCount <= 1, "never a second write waiting behind the first")
        }
        #expect(model.level == 0.4)
        #expect(hardware.levelWrites.isEmpty)
        queue.step()
        #expect(hardware.levelWrites == [0.1], "the write that was in flight")
        #expect(queue.pendingCount == 1, "and the latest sample (0.4) follows it")
        model.set(0.5)
        #expect(queue.pendingCount == 1, "the write of the latest sample is in flight, so 0.5 waits")
        queue.drain()
        #expect(hardware.levelWrites == [0.1, 0.4, 0.5], "0.2 and 0.3 were never written")
        #expect(model.level == 0.5)
    }

    @Test func aWriteTheDeviceRefusesIsReadBackSoTheSliderShowsTheTruth() {
        hardware.refusesLevelWrites = true
        let model = model()
        model.refresh()
        queue.drain()
        model.set(0.9)
        #expect(model.level == 0.9)
        queue.drain()
        #expect(hardware.levelWrites == [0.9])
        #expect(model.level == 0.5)
    }

    @Test func aReadTakenBeforeAWriteDoesNotUndoIt() {
        let model = model()
        model.refresh()
        queue.drain()
        model.refresh()
        model.set(0.9)
        queue.step()
        #expect(model.level == 0.9, "that read is older than the write that is in flight")
        queue.drain()
        #expect(model.level == 0.9)
    }

    // MARK: mute

    @Test func theMutedStateIsShownWithTheLevel() {
        let model = model(FakeVolumeHardware(level: 0.5, muted: true))
        #expect(!model.isMuted)
        model.refresh()
        queue.drain()
        #expect(model.isMuted)
        #expect(model.level == 0.5)
        #expect(model.symbol == "speaker.slash.fill")
        let loud = VolumeModel(hardware: FakeVolumeHardware(level: 0.5), queue: queue)
        loud.refresh()
        queue.drain()
        #expect(!loud.isMuted)
        #expect(loud.symbol == "speaker.wave.2.fill")
    }

    @Test func draggingWhileMutedUnmutesAsAVolumeKeyDoes() {
        let hardware = FakeVolumeHardware(level: 0.5, muted: true)
        let model = model(hardware)
        model.refresh()
        queue.drain()
        model.set(0.7)
        #expect(!model.isMuted, "shown at once")
        queue.drain()
        #expect(hardware.levelWrites == [0.7])
        #expect(hardware.muteWrites == [false])
        #expect(hardware.reading == VolumeReading(level: 0.7, isMuted: false))
        #expect(!model.isMuted)
    }

    @Test func aTapOnTheLevelItAlreadyHasStillUnmutes() {
        let hardware = FakeVolumeHardware(level: 0.5, muted: true)
        let model = model(hardware)
        model.refresh()
        queue.drain()
        model.set(0.5)
        queue.drain()
        #expect(hardware.muteWrites == [false])
        #expect(!model.isMuted)
    }

    @Test func dragEverythingDownToSilenceWhileMutedStaysMuted() {
        let hardware = FakeVolumeHardware(level: 0.5, muted: true)
        let model = model(hardware)
        model.refresh()
        queue.drain()
        model.set(0)
        queue.drain()
        #expect(hardware.muteWrites.isEmpty)
        #expect(model.isMuted)
        #expect(model.level == 0)
    }

    @Test func aLevelSetWhileNotMutedNeverTouchesTheMute() {
        let model = model()
        model.refresh()
        queue.drain()
        model.set(0.7)
        queue.drain()
        #expect(hardware.muteWrites.isEmpty)
    }

    @Test func aDeviceWithoutAMuteStaysAsItWas() {
        let hardware = FakeVolumeHardware(level: 0.5, muted: true)
        hardware.canMute = false
        let model = model(hardware)
        model.refresh()
        queue.drain()
        model.set(0.7)
        queue.drain()
        #expect(model.level == 0.7)
        #expect(model.isMuted, "the unmute did not take, and the model says what the device reads")
    }

    // MARK: watching

    @Test func whileWatchingTheLevelFollowsTheKeysAndTheDevice() {
        let model = model()
        model.startWatching()
        #expect(hardware.observerCount == 0, "the listener is added on the queue")
        queue.drain()
        #expect(hardware.observerCount == 1)
        #expect(model.level == 0.5, "and it reads once as it starts")
        hardware.reading?.level = 0.2
        hardware.fireChange()
        queue.drain()
        #expect(model.level == 0.2)
        hardware.reading?.isMuted = true
        hardware.fireChange()
        queue.drain()
        #expect(model.isMuted)
        hardware.reading = nil
        hardware.fireChange()
        queue.drain()
        #expect(!model.isAvailable, "the default output moved to a device without a volume")
    }

    @Test func stoppingRemovesTheListenerOnTheQueueAndNothingMoreIsHeard() {
        let model = model()
        model.startWatching()
        queue.drain()
        model.stopWatching()
        #expect(hardware.observerCount == 1, "removed on the queue, not at once")
        queue.drain()
        #expect(hardware.observerCount == 0)
        hardware.reading?.level = 0.9
        hardware.fireChange()
        queue.drain()
        #expect(model.level == 0.5)
    }

    @Test func watchingTwiceKeepsOneListenerAndStoppingTwiceIsHarmless() {
        let model = model()
        model.startWatching()
        model.startWatching()
        queue.drain()
        #expect(hardware.observerCount == 1)
        model.stopWatching()
        model.stopWatching()
        queue.drain()
        #expect(hardware.observerCount == 0)
        model.stopWatching()
        #expect(queue.pendingCount == 0)
    }

    @Test func stoppingBeforeTheListenerWasAddedLeavesNoneBehind() {
        let model = model()
        model.startWatching()
        model.stopWatching()
        queue.drain()
        #expect(hardware.observerCount == 0, "the stop is queued behind the start")
    }

    @Test func aModelThatIsDroppedRemovesItsListener() {
        var model: VolumeModel? = VolumeModel(hardware: hardware, queue: queue)
        model?.startWatching()
        queue.drain()
        #expect(hardware.observerCount == 1)
        model = nil
        queue.drain()
        #expect(hardware.observerCount == 0)
    }

    @Test func theInertHardwareTheTestsUseByDefaultHasNoVolume() {
        let model = VolumeModel(hardware: NoVolumeHardware(), queue: queue)
        model.refresh()
        model.startWatching()
        model.set(0.5)
        queue.drain()
        #expect(!model.isAvailable)
        model.stopWatching()
        queue.drain()
    }
}

@Suite struct SerialVolumeQueueTests {
    @Test func workRunsOffTheMainThreadAndTheResultComesBackOnIt() async {
        let queue = SerialVolumeQueue()
        let (workOnMain, completionOnMain) = await withCheckedContinuation { continuation in
            queue.run({ Thread.isMainThread }, then: { workOnMain in continuation.resume(returning: (workOnMain, Thread.isMainThread)) })
        }
        #expect(!workOnMain, "Core Audio can take a long time and the main thread must not wait for it")
        #expect(completionOnMain)
    }

    @Test func jobsRunOneAfterTheOtherInOrderAndTheirResultsComeBackInOrder() async {
        let queue = SerialVolumeQueue()
        let log = Log()
        let results: [Int] = await withCheckedContinuation { continuation in
            for index in 0..<20 {
                queue.run({
                    // A slow early job must not let a later one overtake it.
                    if index == 0 { Thread.sleep(forTimeInterval: 0.05) }
                    log.ran(index)
                    return index
                }, then: { index in
                    log.came(index)
                    if index == 19 { continuation.resume(returning: log.results) }
                })
            }
        }
        #expect(results == Array(0..<20))
        #expect(log.work == Array(0..<20))
    }

    /// What ran and what came back, appended from two threads.
    nonisolated final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var ranIndexes: [Int] = []
        private var cameIndexes: [Int] = []

        var work: [Int] { lock.withLock { ranIndexes } }
        var results: [Int] { lock.withLock { cameIndexes } }

        func ran(_ index: Int) { lock.withLock { ranIndexes.append(index) } }
        func came(_ index: Int) { lock.withLock { cameIndexes.append(index) } }
    }
}
