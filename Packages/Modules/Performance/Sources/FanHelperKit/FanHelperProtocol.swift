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

/// What the helper answers to a command that sets fans: whether it did what was asked, what state the fan is in now, the speed it
/// actually asked the SMC for after clamping, why it did something else if it did, and how long the lease on the command has left.
@objc(MyNotchFanHelperResult)
public final class FanHelperResult: NSObject, NSSecureCoding, @unchecked Sendable {
    public static let supportsSecureCoding = true

    /// Where a fan is after the command.
    public enum State: Int, Sendable {
        /// Apple's automatic control, which is also the answer when the helper went back to it.
        case automatic = 0
        /// Automatic, with a minimum asked for through the target key.
        case floor = 1
        /// Manual, at the speed asked for.
        case forced = 2
    }

    /// The fan index that means "every fan" for `setAuto`.
    public static let allFans = -1

    public let ok: Bool
    public let stateValue: Int
    /// What the helper wrote as the target, in rpm, or -1 when it wrote none.
    public let appliedRPM: Double
    /// A short diagnostic in English: why a request was clamped, refused or turned into automatic.
    public let detail: String
    /// Seconds left of the lease; 0 when the fan is automatic.
    public let leaseSeconds: Double

    public var state: State? { State(rawValue: stateValue) }

    public init(ok: Bool, state: State, appliedRPM: Double = -1, detail: String = "", leaseSeconds: Double = 0) {
        self.ok = ok
        stateValue = state.rawValue
        self.appliedRPM = appliedRPM
        self.detail = detail
        self.leaseSeconds = leaseSeconds
    }

    public required init?(coder: NSCoder) {
        guard coder.containsValue(forKey: "ok"), coder.containsValue(forKey: "state"),
              let detail = coder.decodeObject(of: NSString.self, forKey: "detail") as String?
        else { return nil }
        ok = coder.decodeBool(forKey: "ok")
        stateValue = coder.decodeInteger(forKey: "state")
        appliedRPM = coder.decodeDouble(forKey: "appliedRPM")
        self.detail = detail
        leaseSeconds = coder.decodeDouble(forKey: "leaseSeconds")
    }

    public func encode(with coder: NSCoder) {
        coder.encode(ok, forKey: "ok")
        coder.encode(stateValue, forKey: "state")
        coder.encode(appliedRPM, forKey: "appliedRPM")
        coder.encode(detail as NSString, forKey: "detail")
        coder.encode(leaseSeconds, forKey: "leaseSeconds")
    }
}

/// What the app may ask of the helper: two reads and three ways to set a fan, and nothing else. No operation writes an SMC key
/// by name or takes a value other than a fan and a speed, and the helper clamps every speed to the fan's own range, so no
/// connection, whoever makes it, can ask for more. A test pins this list.
///
/// Every setting is a lease: it lasts 15 seconds unless the same command is sent again, after which the helper puts the fan back to
/// Apple's automatic control by itself.
@objc(MyNotchFanHelperProtocol)
public protocol FanHelperProtocol {
    /// Who the helper is: its version and build, and the user it runs as.
    func ping(reply: @escaping @Sendable (FanHelperPing) -> Void)
    /// The fans as the SMC reports them, to compare with what the app reads itself; the second value is a reason when the SMC could
    /// not be read, nil otherwise.
    func readFans(reply: @escaping @Sendable ([FanHelperFan], String?) -> Void)
    /// Asks for at least `rpm` on one fan while Apple's automatic control stays on: the speed goes to the fan's target key and the
    /// mode is left alone. Whether the firmware honours it is for the probe to find out.
    func setFloor(fan: Int, rpm: Double, reply: @escaping @Sendable (FanHelperResult) -> Void)
    /// Takes one fan to a manual `rpm`, unless Apple's own speed is higher, in which case the fan stays automatic.
    func setForced(fan: Int, rpm: Double, reply: @escaping @Sendable (FanHelperResult) -> Void)
    /// Gives one fan, or with `FanHelperResult.allFans` every fan, back to Apple's automatic control.
    func setAuto(fan: Int, reply: @escaping @Sendable (FanHelperResult) -> Void)
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
        for selector in [
            #selector(FanHelperProtocol.setFloor(fan:rpm:reply:)), #selector(FanHelperProtocol.setForced(fan:rpm:reply:)),
            #selector(FanHelperProtocol.setAuto(fan:reply:)),
        ] {
            interface.setClasses(allowed(FanHelperResult.self), for: selector, argumentIndex: 0, ofReply: true)
        }
        return interface
    }

    private static func allowed(_ classes: AnyClass...) -> Set<AnyHashable> {
        NSSet(array: classes) as? Set<AnyHashable> ?? []
    }
}
