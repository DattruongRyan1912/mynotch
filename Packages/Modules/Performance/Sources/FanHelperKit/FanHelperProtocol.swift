import Foundation

/// What the helper answers to a ping: enough for the app to know it is the helper it shipped, that it really runs as root, and
/// which build it is.
@objc(MyNotchFanHelperPing)
public final class FanHelperPing: NSObject, NSSecureCoding, @unchecked Sendable {
    public static let supportsSecureCoding = true

    public let version: String
    /// The code directory hash of the helper's running image, in hex.
    public let buildID: String
    /// The effective user id; 0 when the helper runs as root as it must.
    public let euid: Int32
    public let pid: Int32

    public init(version: String, buildID: String, euid: Int32, pid: Int32) {
        self.version = version
        self.buildID = buildID
        self.euid = euid
        self.pid = pid
    }

    public required init?(coder: NSCoder) {
        guard let version = coder.decodeObject(of: NSString.self, forKey: "version") as String?,
              let buildID = coder.decodeObject(of: NSString.self, forKey: "buildID") as String?,
              coder.containsValue(forKey: "euid"), coder.containsValue(forKey: "pid")
        else { return nil }
        self.version = version
        self.buildID = buildID
        euid = coder.decodeInt32(forKey: "euid")
        pid = coder.decodeInt32(forKey: "pid")
    }

    public func encode(with coder: NSCoder) {
        coder.encode(version as NSString, forKey: "version")
        coder.encode(buildID as NSString, forKey: "buildID")
        coder.encode(euid, forKey: "euid")
        coder.encode(pid, forKey: "pid")
    }
}

/// One fan as the SMC says it is. `mode` and `target` are -1 (`unknown`) when the SMC does not have them.
@objc(MyNotchFanHelperFan)
public final class FanHelperFan: NSObject, NSSecureCoding, @unchecked Sendable {
    public static let supportsSecureCoding = true
    public static let unknown = -1.0

    public let index: Int
    public let rpm: Double
    public let minRPM: Double
    public let maxRPM: Double
    /// The SMC's fan mode: 0 is automatic.
    public let mode: Double
    public let target: Double

    public init(index: Int, rpm: Double, minRPM: Double, maxRPM: Double, mode: Double = FanHelperFan.unknown, target: Double = FanHelperFan.unknown) {
        self.index = index
        self.rpm = rpm
        self.minRPM = minRPM
        self.maxRPM = maxRPM
        self.mode = mode
        self.target = target
    }

    public required init?(coder: NSCoder) {
        guard coder.containsValue(forKey: "index"), coder.containsValue(forKey: "rpm"), coder.containsValue(forKey: "minRPM"),
              coder.containsValue(forKey: "maxRPM")
        else { return nil }
        index = coder.decodeInteger(forKey: "index")
        rpm = coder.decodeDouble(forKey: "rpm")
        minRPM = coder.decodeDouble(forKey: "minRPM")
        maxRPM = coder.decodeDouble(forKey: "maxRPM")
        mode = coder.containsValue(forKey: "mode") ? coder.decodeDouble(forKey: "mode") : Self.unknown
        target = coder.containsValue(forKey: "target") ? coder.decodeDouble(forKey: "target") : Self.unknown
    }

    public func encode(with coder: NSCoder) {
        coder.encode(index, forKey: "index")
        coder.encode(rpm, forKey: "rpm")
        coder.encode(minRPM, forKey: "minRPM")
        coder.encode(maxRPM, forKey: "maxRPM")
        coder.encode(mode, forKey: "mode")
        coder.encode(target, forKey: "target")
    }
}

/// What the app may ask of the helper. For now two reads and nothing else: there is no operation that writes to the SMC, so no
/// connection, whoever makes it, can ask for one. A test pins this list.
@objc(MyNotchFanHelperProtocol)
public protocol FanHelperProtocol {
    /// Who the helper is: its version and build, and the user it runs as.
    func ping(reply: @escaping @Sendable (FanHelperPing) -> Void)
    /// The fans as the SMC reports them, to compare with what the app reads itself; the second value is a reason when the SMC could
    /// not be read, nil otherwise.
    func readFans(reply: @escaping @Sendable ([FanHelperFan], String?) -> Void)
}

/// The interface both ends of the connection use, with the classes each reply may carry named: without them the receiving side
/// refuses to decode the objects. Signing requirements are not set here; each end sets its own on the connection.
public enum FanHelperInterface {
    public static func make() -> NSXPCInterface {
        let interface = NSXPCInterface(with: FanHelperProtocol.self)
        interface.setClasses(allowed(FanHelperPing.self), for: #selector(FanHelperProtocol.ping(reply:)), argumentIndex: 0, ofReply: true)
        interface.setClasses(
            allowed(NSArray.self, FanHelperFan.self), for: #selector(FanHelperProtocol.readFans(reply:)), argumentIndex: 0, ofReply: true
        )
        return interface
    }

    private static func allowed(_ classes: AnyClass...) -> Set<AnyHashable> {
        NSSet(array: classes) as? Set<AnyHashable> ?? []
    }
}
