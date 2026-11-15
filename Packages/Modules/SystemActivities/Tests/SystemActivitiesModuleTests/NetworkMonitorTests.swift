import MyNotchTestSupport
import Testing
@testable import SystemActivitiesModule

final class FakePathSource: PathSource {
    var onUpdate: (@MainActor (NetworkStatus) -> Void)?
    var stopCount = 0
    func start(_ onUpdate: @escaping @MainActor (NetworkStatus) -> Void) { self.onUpdate = onUpdate }
    func stop() { stopCount += 1; onUpdate = nil }
    func send(_ status: NetworkStatus) { onUpdate?(status) }
}

@Suite final class NetworkMonitorTests {
    static let wifi = NetworkStatus(isConnected: true, interface: .wifi, isExpensive: false)
    static let ethernet = NetworkStatus(isConnected: true, interface: .ethernet, isExpensive: false)
    static let offline = NetworkStatus(isConnected: false, interface: .none, isExpensive: false)

    let source = FakePathSource()
    let scheduler = ManualScheduler()
    var changes: [NetworkStatus] = []

    lazy var monitor: NetworkMonitor = {
        let monitor = NetworkMonitor(source: source, scheduler: scheduler)
        monitor.start { [unowned self] in changes.append($0) }
        return monitor
    }()

    @Test func skipsTheFirstUpdate() {
        _ = monitor
        source.send(Self.wifi)
        scheduler.advance(by: .seconds(2))
        #expect(changes.isEmpty)
    }

    @Test func emitsAfterTheDebounceWhenConnectivityChanges() {
        _ = monitor
        source.send(Self.wifi)
        source.send(Self.offline)
        scheduler.advance(by: .milliseconds(999))
        #expect(changes.isEmpty)
        scheduler.advance(by: .milliseconds(1))
        #expect(changes == [Self.offline])
    }

    @Test func emitsWhenTheInterfaceTypeChanges() {
        _ = monitor
        source.send(Self.wifi)
        source.send(Self.ethernet)
        scheduler.advance(by: .seconds(1))
        #expect(changes == [Self.ethernet])
    }

    @Test func ignoresAChangeOfOnlyTheExpensiveFlag() {
        _ = monitor
        source.send(Self.wifi)
        source.send(NetworkStatus(isConnected: true, interface: .wifi, isExpensive: true))
        scheduler.advance(by: .seconds(2))
        #expect(changes.isEmpty)
    }

    @Test func aFlapThatSettlesBackEmitsNothing() {
        _ = monitor
        source.send(Self.wifi)
        source.send(Self.offline)
        scheduler.advance(by: .milliseconds(400))
        source.send(Self.wifi)
        scheduler.advance(by: .seconds(2))
        #expect(changes.isEmpty)
    }

    @Test func aFlapEmitsOnlyTheSettledState() {
        _ = monitor
        source.send(Self.wifi)
        source.send(Self.offline)
        scheduler.advance(by: .milliseconds(400))
        source.send(Self.ethernet)
        scheduler.advance(by: .seconds(2))
        #expect(changes == [Self.ethernet])
    }

    @Test func stopStopsTheSourceAndPendingEmission() {
        _ = monitor
        source.send(Self.wifi)
        source.send(Self.offline)
        let stopsBefore = source.stopCount
        monitor.stop()
        scheduler.advance(by: .seconds(2))
        #expect(changes.isEmpty)
        #expect(source.stopCount == stopsBefore + 1)
    }
}
