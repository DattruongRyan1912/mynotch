import CoreGraphics
import MyNotchTestSupport
import Testing
@testable import SystemActivitiesModule

@Suite final class CapsLockMonitorTests {
    let scheduler = ManualScheduler()
    var flags: CGEventFlags = []
    var changes: [Bool] = []

    lazy var monitor = CapsLockMonitor(flags: { [unowned self] in flags }, scheduler: scheduler)

    @Test func doesNotEmitTheInitialState() {
        flags = .maskAlphaShift
        monitor.start { [unowned self] in changes.append($0) }
        scheduler.advance(by: .seconds(1))
        #expect(changes.isEmpty)
    }

    @Test func emitsOnlyWhenTheStateChanges() {
        monitor.start { [unowned self] in changes.append($0) }
        scheduler.advance(by: .milliseconds(250))
        #expect(changes.isEmpty)
        flags = .maskAlphaShift
        scheduler.advance(by: .milliseconds(250))
        scheduler.advance(by: .milliseconds(250))
        #expect(changes == [true])
        flags = [.maskAlphaShift, .maskShift]
        scheduler.advance(by: .milliseconds(250))
        #expect(changes == [true])
        flags = .maskShift
        scheduler.advance(by: .milliseconds(250))
        #expect(changes == [true, false])
    }

    @Test func stopEndsPolling() {
        monitor.start { [unowned self] in changes.append($0) }
        monitor.stop()
        flags = .maskAlphaShift
        scheduler.advance(by: .seconds(1))
        #expect(changes.isEmpty)
        #expect(scheduler.pendingCount == 0)
    }
}
