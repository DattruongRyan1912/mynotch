import Foundation

/// What the helper does for a connection. Everything it needs from the system is passed in, so a test can run it over a real
/// XPC connection to an anonymous listener with a fake SMC.
public final class FanHelperService: NSObject, FanHelperProtocol, @unchecked Sendable {
    private let version: String
    private let buildID: String
    private let euid: @Sendable () -> Int32
    private let pid: @Sendable () -> Int32
    private let openChannel: @Sendable () -> (any SMCChannel)?

    public init(
        version: String = FanHelperIdentity.version,
        buildID: String,
        euid: @escaping @Sendable () -> Int32 = { Int32(bitPattern: geteuid()) },
        pid: @escaping @Sendable () -> Int32 = { getpid() },
        openChannel: @escaping @Sendable () -> (any SMCChannel)? = { AppleSMCChannel() }
    ) {
        self.version = version
        self.buildID = buildID
        self.euid = euid
        self.pid = pid
        self.openChannel = openChannel
    }

    public func ping(reply: @escaping @Sendable (FanHelperPing) -> Void) {
        reply(FanHelperPing(version: version, buildID: buildID, euid: euid(), pid: pid()))
    }

    /// A connection of its own for each read: the helper is idle between calls, and opening the SMC is cheap.
    public func readFans(reply: @escaping @Sendable ([FanHelperFan], String?) -> Void) {
        guard let channel = openChannel() else {
            reply([], "cannot open the SMC")
            return
        }
        reply(FanSMC.readFans(on: channel), nil)
    }
}
