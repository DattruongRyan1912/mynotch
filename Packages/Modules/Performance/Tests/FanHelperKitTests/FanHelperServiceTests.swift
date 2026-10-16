import Foundation
import Synchronization
import Testing
@testable import FanHelperKit

/// An in-memory SMC with this Mac's fan keys, as the TH0 probe read them.
struct FanKeysChannel: SMCChannel {
    var entries: [String: (type: String, bytes: [UInt8])]

    static let thisMac: [String: (type: String, bytes: [UInt8])] = [
        "FNum": ("ui8 ", [2]),
        "F0Ac": ("flt ", [0x9d, 0x71, 0xa3, 0x45]), "F0Mn": ("flt ", [0x00, 0x00, 0x96, 0x44]),
        "F0Mx": ("flt ", [0x00, 0x98, 0xb4, 0x45]), "F0Md": ("ui8 ", [0]), "F0Tg": ("flt ", [0x00, 0x98, 0xa3, 0x45]),
        "F1Ac": ("flt ", [0x95, 0xc1, 0xb0, 0x45]), "F1Mn": ("flt ", [0x00, 0x00, 0x96, 0x44]),
        "F1Mx": ("flt ", [0x00, 0x08, 0xc3, 0x45]), "F1Md": ("ui8 ", [0]), "F1Tg": ("flt ", [0x00, 0xa8, 0xb0, 0x45]),
    ]

    init(_ entries: [String: (type: String, bytes: [UInt8])] = Self.thisMac) { self.entries = entries }

    func keyName(at index: Int) -> String? { nil }
    func info(of key: String) -> SMCKeyInfo? { entries[key].map { SMCKeyInfo(size: $0.bytes.count, type: $0.type) } }
    func bytes(of key: String, info: SMCKeyInfo) -> [UInt8]? { entries[key]?.bytes }
}

@Suite struct FanHelperServiceTests {
    func service(_ channel: FanKeysChannel? = FanKeysChannel(), euid: Int32 = 0) -> FanHelperService {
        FanHelperService(version: "7", buildID: "abc123", euid: { euid }, pid: { 99 }, openChannel: { channel })
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

    final class Served: Sendable {
        private let names = Mutex<[String]>([])
        func record(_ name: String) { names.withLock { $0.append(name) } }
        var value: [String] { names.withLock { $0 } }
    }

    @Test func eachRequestThatIsServedIsReportedByName() async {
        let served = Served()
        let service = FanHelperService(buildID: "abc", openChannel: { FanKeysChannel() }, onRequest: { served.record($0) })
        let (proxy, close) = connect(to: service)
        defer { close() }
        _ = await withCheckedContinuation { continuation in proxy.ping { continuation.resume(returning: $0) } }
        _ = await withCheckedContinuation { (continuation: CheckedContinuation<([FanHelperFan], String?), Never>) in
            proxy.readFans { continuation.resume(returning: ($0, $1)) }
        }
        #expect(served.value == ["ping", "readFans"])
    }

    @Test func aPingAnswersWithTheVersionTheBuildTheUserAndTheProcess() async throws {
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

    @Test func readingTheFansReturnsEachFanWithItsLimitsModeAndTarget() async throws {
        let (proxy, close) = connect(to: service())
        defer { close() }
        let (fans, failure) = await withCheckedContinuation { (continuation: CheckedContinuation<([FanHelperFan], String?), Never>) in
            proxy.readFans { continuation.resume(returning: ($0, $1)) }
        }
        #expect(failure == nil)
        #expect(fans.map(\.index) == [0, 1])
        #expect(abs(fans[0].rpm - 5230.2017) < 0.001 && fans[0].minRPM == 1200 && fans[0].maxRPM == 5779)
        #expect(fans[0].mode == 0 && fans[0].target == 5235)
        #expect(abs(fans[1].rpm - 5656.1978) < 0.001 && fans[1].maxRPM == 6241 && fans[1].target == 5653)
    }

    @Test func anSMCThatCannotBeOpenedIsAFailureNotAnEmptyAnswer() async {
        let (proxy, close) = connect(to: service(nil))
        defer { close() }
        let (fans, failure) = await withCheckedContinuation { (continuation: CheckedContinuation<([FanHelperFan], String?), Never>) in
            proxy.readFans { continuation.resume(returning: ($0, $1)) }
        }
        #expect(fans.isEmpty)
        #expect(failure == "cannot open the SMC")
    }

    @Test func aMacWithNoFansIsAnEmptyAnswerWithoutAFailure() async {
        var entries = FanKeysChannel.thisMac
        entries["FNum"] = ("ui8 ", [0])
        let (proxy, close) = connect(to: service(FanKeysChannel(entries)))
        defer { close() }
        let (fans, failure) = await withCheckedContinuation { (continuation: CheckedContinuation<([FanHelperFan], String?), Never>) in
            proxy.readFans { continuation.resume(returning: ($0, $1)) }
        }
        #expect(fans.isEmpty && failure == nil)
    }
}
