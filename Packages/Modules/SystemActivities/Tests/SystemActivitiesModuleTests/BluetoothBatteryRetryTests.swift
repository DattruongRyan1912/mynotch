import MyNotchTestSupport
import Testing
@testable import SystemActivitiesModule

@Suite final class BluetoothBatteryRetryTests {
    let scheduler = ManualScheduler()
    lazy var retry = BluetoothBatteryRetry(scheduler: scheduler)
    var battery: BluetoothBattery?
    var delivered: [BluetoothBattery] = []

    func start(key: String = "aa") {
        retry.start(key: key, read: { [unowned self] in battery }, deliver: { [unowned self] in delivered.append($0) })
    }

    @Test func theFirstReadComesBeforeTheShortestVisibleWindowEnds() throws {
        let first = try #require(BluetoothBatteryRetry.readTimes.first)
        #expect(first < .seconds(SystemActivitiesKeys.durationRange.lowerBound))
        #expect(BluetoothBatteryRetry.readTimes == BluetoothBatteryRetry.readTimes.sorted())
    }

    @Test func deliversTheBatteryOnceItBecomesReadableAndStops() {
        start()
        scheduler.advance(by: .milliseconds(1_200))
        #expect(delivered.isEmpty)
        battery = .single(60)
        scheduler.advance(by: .seconds(10))
        #expect(delivered == [.single(60)])
        #expect(scheduler.pendingCount == 0)
    }

    @Test func aBatteryReadableAtTheFirstReadIsDeliveredThere() throws {
        let first = try #require(BluetoothBatteryRetry.readTimes.first)
        battery = .single(80)
        start()
        scheduler.advance(by: first - .milliseconds(1))
        #expect(delivered.isEmpty)
        scheduler.advance(by: .milliseconds(1))
        #expect(delivered == [.single(80)])
    }

    @Test func givesUpAfterTheLastRead() {
        start()
        scheduler.advance(by: .seconds(10))
        #expect(delivered.isEmpty)
        #expect(scheduler.pendingCount == 0)
    }

    @Test func startingAgainForTheSameDeviceReplacesThePendingReads() {
        start()
        let readsOfOneStart = scheduler.pendingCount
        start()
        #expect(scheduler.pendingCount == readsOfOneStart)
        battery = .single(50)
        scheduler.advance(by: .seconds(10))
        #expect(delivered == [.single(50)])
    }

    @Test func cancellingStopsOneDeviceAndCancellingAllStopsEverything() {
        start(key: "aa")
        start(key: "bb")
        retry.cancel(key: "aa")
        #expect(scheduler.pendingCount == BluetoothBatteryRetry.readTimes.count)
        retry.cancelAll()
        #expect(scheduler.pendingCount == 0)
    }
}
