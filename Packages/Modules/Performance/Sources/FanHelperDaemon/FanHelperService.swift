import FanHelperKit
import Foundation

/// What the helper does for a connection. Everything it needs from the system is passed in, so a test can run it over a real
/// XPC connection to an anonymous listener with a fake SMC, and nothing here can reach the real one.
public final class FanHelperService: NSObject, FanHelperProtocol, @unchecked Sendable {
    private let version: String
    private let buildID: String
    private let euid: @Sendable () -> Int32
    private let pid: @Sendable () -> Int32
    private let openChannel: @Sendable () -> (any SMCChannel)?
    private let controller: FanController?
    private let onRequest: @Sendable (String) -> Void

    /// `controller` is nil where fan control is not available (the writer could not be made): the three setting commands then
    /// answer that, and the two reads work as ever.
    public init(
        version: String = FanHelperIdentity.version,
        buildID: String,
        euid: @escaping @Sendable () -> Int32 = { Int32(bitPattern: geteuid()) },
        pid: @escaping @Sendable () -> Int32 = { getpid() },
        openChannel: @escaping @Sendable () -> (any SMCChannel)? = { AppleSMCChannel() },
        controller: FanController? = nil,
        onRequest: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.version = version
        self.buildID = buildID
        self.euid = euid
        self.pid = pid
        self.openChannel = openChannel
        self.controller = controller
        self.onRequest = onRequest
    }

    /// `onRequest` hears the name of each request that is served: a connection that the system turned away never gets this far,
    /// which is how the log shows the difference between a peer that was received and one that was served.
    public func ping(reply: @escaping @Sendable (FanHelperPing) -> Void) {
        onRequest("ping")
        reply(FanHelperPing(version: version, buildID: buildID, euid: euid(), pid: pid()))
    }

    /// A connection of its own for each read: the helper is idle between calls, and opening the SMC is cheap.
    public func readFans(reply: @escaping @Sendable ([FanHelperFan], String?) -> Void) {
        onRequest("readFans")
        guard let channel = openChannel() else {
            reply([], "cannot open the SMC")
            return
        }
        reply(FanSMC.readFans(on: channel), nil)
    }

    public func setFloor(fan: Int, rpm: Double, reply: @escaping @Sendable (FanHelperResult) -> Void) {
        onRequest("setFloor")
        reply(controller?.setFloor(fan: fan, rpm: rpm) ?? Self.unavailable)
    }

    public func setForced(fan: Int, rpm: Double, reply: @escaping @Sendable (FanHelperResult) -> Void) {
        onRequest("setForced")
        reply(controller?.setForced(fan: fan, rpm: rpm) ?? Self.unavailable)
    }

    public func setAuto(fan: Int, reply: @escaping @Sendable (FanHelperResult) -> Void) {
        onRequest("setAuto")
        reply(controller?.setAuto(fan: fan) ?? Self.unavailable)
    }

    private static var unavailable: FanHelperResult {
        FanHelperResult(ok: false, state: .automatic, detail: "fan control is not available")
    }
}
