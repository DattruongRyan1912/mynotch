import FanHelperKit
import Foundation
import Synchronization
import Testing
@testable import FanHelperDaemon

@Suite struct FanHelperServiceTests {
    final class Served: Sendable {
        private let names = Mutex<[String]>([])
        func record(_ name: String) { names.withLock { $0.append(name) } }
        var value: [String] { names.withLock { $0 } }
    }

    func service(_ rig: Rig? = nil, euid: Int32 = 0, served: Served = Served()) -> FanHelperService {
        let smc = rig?.smc ?? FakeFanSMC()
        return FanHelperService(
            version: "7", buildID: "abc123", euid: { euid }, pid: { 99 }, openChannel: { smc },
            controller: rig?.controller, onRequest: { served.record($0) }
        )
    }

    /// A real NSXPC connection to an anonymous listener in this process: the messages are encoded and decoded as they are across
    /// the system's XPC, with nothing registered anywhere and no mach service. The signing requirements are not applied (the test
    /// process is not signed by the team); the helper's listener delegate and the app's client set them.
    func connect(to service: FanHelperService) -> (proxy: any FanHelperProtocol, close: () -> Void) {
        let listener = NSXPCListener.anonymous()
        let delegate = AcceptEverything(exporting: service)
        listener.delegate = delegate
        listener.resume()
        let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
        connection.remoteObjectInterface = FanHelperInterface.make()
        connection.resume()
        let proxy = connection.remoteObjectProxy as! any FanHelperProtocol
        return (proxy, { connection.invalidate(); listener.invalidate(); withExtendedLifetime(delegate) {} })
    }

    final class AcceptEverything: NSObject, NSXPCListenerDelegate {
        let service: FanHelperService
        init(exporting service: FanHelperService) { self.service = service }
        func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
            connection.exportedInterface = FanHelperInterface.make()
            connection.exportedObject = service
            connection.resume()
            return true
        }
    }

    func readFans(_ proxy: any FanHelperProtocol) async -> ([FanHelperFan], String?) {
        await withCheckedContinuation { continuation in proxy.readFans { continuation.resume(returning: ($0, $1)) } }
    }

    // MARK: The two reads

    @Test func aPingAnswersWithTheVersionTheBuildTheUserAndTheProcess() async {
        let (proxy, close) = connect(to: service())
        defer { close() }
        let ping = await withCheckedContinuation { continuation in proxy.ping { continuation.resume(returning: $0) } }
        #expect(ping.version == "7" && ping.buildID == "abc123")
        #expect(ping.euid == 0 && ping.pid == 99)
    }

    @Test func aPingSaysWhoTheHelperReallyRunsAs() async {
        let (proxy, close) = connect(to: service(euid: 501))
        defer { close() }
        let ping = await withCheckedContinuation { continuation in proxy.ping { continuation.resume(returning: $0) } }
        #expect(ping.euid == 501, "so the app can tell a helper that did not get root")
    }

    @Test func readingTheFansReturnsEachFanWithItsLimitsModeAndTarget() async {
        let (proxy, close) = connect(to: service())
        defer { close() }
        let (fans, failure) = await readFans(proxy)
        #expect(failure == nil)
        #expect(fans.map(\.index) == [0, 1])
        #expect(fans.map(\.minRPM) == [1200, 1200] && fans.map(\.maxRPM) == [5779, 6241])
        #expect(fans.map(\.mode) == [0, 0])
    }

    @Test func anSMCThatCannotBeOpenedIsAFailureNotAnEmptyAnswer() async {
        let unavailable = FanHelperService(buildID: "abc", openChannel: { nil })
        let (proxy, close) = connect(to: unavailable)
        defer { close() }
        let (fans, failure) = await readFans(proxy)
        #expect(fans.isEmpty && failure == "cannot open the SMC")
    }

    @Test func eachRequestThatIsServedIsReportedByName() async {
        let served = Served()
        let (proxy, close) = connect(to: service(Rig(), served: served))
        defer { close() }
        _ = await withCheckedContinuation { continuation in proxy.ping { continuation.resume(returning: $0) } }
        _ = await readFans(proxy)
        _ = await withCheckedContinuation { continuation in proxy.setAuto(fan: -1) { continuation.resume(returning: $0) } }
        #expect(served.value == ["ping", "readFans", "setAuto"])
    }

    // MARK: The three ways to set a fan, over XPC

    @Test func settingAFanTravelsAsAResultWithItsStateSpeedAndLease() async {
        let rig = Rig(actual: 2000)
        let (proxy, close) = connect(to: service(rig))
        defer { close() }
        let result = await withCheckedContinuation { continuation in proxy.setForced(fan: 0, rpm: 3200) { continuation.resume(returning: $0) } }
        #expect(result.ok && result.state == .forced)
        #expect(result.appliedRPM == 3200)
        #expect(result.leaseSeconds > 14 && result.leaseSeconds <= 15)
        #expect(rig.writes == [.mode(0, 1), .target(0, 3200)])
    }

    @Test func everyFanAtOnceTravelsAsOneCommandWithTheMeanSpeedAndHowLongTheModesTook() async {
        let rig = Rig(actual: 2000) { $0.applyModeOn(after: 0.1) }
        let (proxy, close) = connect(to: service(rig))
        defer { close() }
        let result = await withCheckedContinuation { continuation in
            proxy.setForced(fan: FanHelperResult.allFans, rpm: 6000) { continuation.resume(returning: $0) }
        }
        #expect(result.ok && result.state == .forced)
        #expect(result.appliedRPM == 5889.5, "each fan to its own range, and the mean of what was written")
        #expect(result.modeReadBackMS == 100)
        #expect(rig.writes == [.mode(0, 1), .mode(1, 1), .target(0, 5779), .target(1, 6000)])
        let back = await withCheckedContinuation { continuation in proxy.setAuto(fan: -1) { continuation.resume(returning: $0) } }
        #expect(back.ok && back.state == .automatic && back.modeReadBackMS == -1)
    }

    @Test func aFloorGoesToTheTargetKeyAloneAndAutoGivesTheFanBack() async {
        let rig = Rig(actual: 2000)
        let (proxy, close) = connect(to: service(rig))
        defer { close() }
        let floor = await withCheckedContinuation { continuation in proxy.setFloor(fan: 1, rpm: 3000) { continuation.resume(returning: $0) } }
        #expect(floor.ok && floor.state == .floor && floor.appliedRPM == 3000)
        #expect(rig.writes == [.target(1, 3000)], "the mode is not touched")
        let back = await withCheckedContinuation { continuation in proxy.setAuto(fan: 1) { continuation.resume(returning: $0) } }
        #expect(back.ok && back.state == .automatic && back.leaseSeconds == 0)
    }

    @Test func withoutAControllerTheSettingCommandsAnswerThatAndTheReadsStillWork() async {
        let (proxy, close) = connect(to: service(nil))
        defer { close() }
        for call in [
            { (reply: @escaping @Sendable (FanHelperResult) -> Void) in proxy.setForced(fan: 0, rpm: 3000, reply: reply) },
            { (reply: @escaping @Sendable (FanHelperResult) -> Void) in proxy.setFloor(fan: 0, rpm: 3000, reply: reply) },
            { (reply: @escaping @Sendable (FanHelperResult) -> Void) in proxy.setAuto(fan: 0, reply: reply) },
        ] {
            let result = await withCheckedContinuation { continuation in call { continuation.resume(returning: $0) } }
            #expect(result.ok == false && result.detail == "fan control is not available")
        }
        #expect(await readFans(proxy).1 == nil)
    }

    @Test func aRefusalTravelsWithItsReason() async {
        let rig = Rig()
        rig.otherTool.current = true
        let (proxy, close) = connect(to: service(rig))
        defer { close() }
        let result = await withCheckedContinuation { continuation in proxy.setForced(fan: 0, rpm: 3000) { continuation.resume(returning: $0) } }
        #expect(result.ok == false && result.detail == "Macs Fan Control is running")
        #expect(rig.writes.isEmpty)
    }
}
