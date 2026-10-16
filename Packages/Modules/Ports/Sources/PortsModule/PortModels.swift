import Foundation

nonisolated enum PortProtocol: String, Hashable, Sendable, Comparable {
    case tcp, udp

    var title: String { rawValue.uppercased() }

    static func < (lhs: PortProtocol, rhs: PortProtocol) -> Bool { lhs == .tcp && rhs == .udp }
}

/// What libproc says about one socket, copied out of its C structs, so which sockets count as listeners and what address they are
/// bound to are plain rules that run on made-up values.
nonisolated struct RawSocket: Sendable {
    /// `TSI_S_LISTEN`.
    static let listenState: Int32 = 1

    var proto: PortProtocol
    /// `tcpsi_state`; not read for UDP.
    var tcpState: Int32 = 0
    var vflag: UInt8
    /// `insi_lport` as libproc gives it: network byte order in the low 16 bits.
    var localPort: Int32
    var foreignPort: Int32 = 0
    /// The 16 bytes of `insi_laddr`.
    var localAddress: [UInt8]
}

/// One socket that is waiting for others to connect: a listening TCP socket, or a UDP one that is bound and not connected.
nonisolated struct ListeningSocket: Hashable, Sendable {
    let pid: Int32
    let port: UInt16
    let proto: PortProtocol
    let address: PortAddress

    init(pid: Int32, port: UInt16, proto: PortProtocol, address: PortAddress) {
        self.pid = pid
        self.port = port
        self.proto = proto
        self.address = address
    }

    init?(raw: RawSocket, pid: Int32) {
        switch raw.proto {
        case .tcp: guard raw.tcpState == RawSocket.listenState else { return nil }
        case .udp: guard raw.foreignPort == 0 else { return nil }
        }
        let port = UInt16(bigEndian: UInt16(truncatingIfNeeded: raw.localPort))
        guard port != 0, let address = PortAddress(vflag: raw.vflag, bytes: raw.localAddress) else { return nil }
        self.init(pid: pid, port: port, proto: raw.proto, address: address)
    }
}

/// A process as it was when it was read. The start time is what tells it apart from a later process that got the same pid.
nonisolated struct ProcessIdentity: Hashable, Sendable {
    let pid: Int32
    let uid: UInt32
    let realUID: UInt32
    /// Microseconds since 1970.
    let startTime: UInt64
    /// The executable's path; nil when the system would not tell.
    let path: String?
}

nonisolated struct PortProcess: Hashable, Sendable {
    let identity: ProcessIdentity
    let name: String
    /// What the process was started with, for example `node server.js`; nil when it cannot be read.
    let commandLine: String?

    var pid: Int32 { identity.pid }
    var appBundlePath: String? { identity.path.flatMap(AppBundle.outermost(in:)) }
    var appName: String? { appBundlePath.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } }
    /// What the user knows it as: the app's name when it belongs to an app, the executable's otherwise.
    var displayName: String { appName ?? name }
    /// The executable and, when it is inside an app of another name, that app: "com.docker.backend của Docker". What a question
    /// before a signal says, since stopping a helper is not the same as stopping the app that is named after it.
    var fullName: String {
        guard let appName, appName != name else { return displayName }
        return "\(name) của \(appName)"
    }
}

nonisolated struct PortSnapshot: Sendable {
    var sockets: [ListeningSocket] = []
    var processes: [Int32: PortProcess] = [:]
}

/// One row: a port held by one process, with every address it is bound to.
nonisolated struct PortEntry: Identifiable, Hashable, Sendable {
    let port: UInt16
    let proto: PortProtocol
    let process: PortProcess
    /// IPv4 first, then IPv6, each once.
    let addresses: [PortAddress]

    var id: String { "\(proto.rawValue):\(port):\(process.pid)" }
    var pid: Int32 { process.pid }
    /// Reachable from the network as soon as one of the addresses is not a loopback one.
    var isLocalOnly: Bool { addresses.allSatisfy(\.isLocalOnly) }
    var addressText: String { addresses.map(\.text).joined(separator: ", ") }

    /// The sockets of one read as rows, by port. The same port on IPv4 and IPv6 held by one process is one row; sockets whose
    /// process could not be read (it exited in between, or is not the user's) are left out.
    static func entries(from snapshot: PortSnapshot) -> [PortEntry] {
        struct Key: Hashable { let port: UInt16; let proto: PortProtocol; let pid: Int32 }
        var grouped: [Key: [PortAddress]] = [:]
        for socket in snapshot.sockets {
            grouped[Key(port: socket.port, proto: socket.proto, pid: socket.pid), default: []].append(socket.address)
        }
        return grouped.compactMap { key, addresses -> PortEntry? in
            guard let process = snapshot.processes[key.pid] else { return nil }
            let unique = Set(addresses).sorted { ($0.isIPv6 ? 1 : 0, $0.text) < ($1.isIPv6 ? 1 : 0, $1.text) }
            return PortEntry(port: key.port, proto: key.proto, process: process, addresses: unique)
        }
        .sorted { ($0.port, $0.proto, $0.pid) < ($1.port, $1.proto, $1.pid) }
    }
}

/// The outermost `.app` a path is inside of: the app the user knows, not the helper app inside it.
nonisolated enum AppBundle {
    static func outermost(in path: String) -> String? {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard let index = components.dropLast().firstIndex(where: { $0.lowercased().hasSuffix(".app") }) else { return nil }
        return "/" + components[...index].joined(separator: "/")
    }
}
