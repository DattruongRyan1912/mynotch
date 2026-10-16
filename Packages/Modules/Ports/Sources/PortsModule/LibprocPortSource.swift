import Darwin
import Foundation

/// Where the list of ports comes from. A read is blocking system calls, so it is called off the main actor.
nonisolated protocol PortSource: Sendable {
    func read() -> PortSnapshot
}

/// The listening sockets of the user's own processes through libproc: pids, then each one's file descriptors, then each socket's
/// details. No `lsof`, no child process.
nonisolated struct LibprocPortSource: PortSource {
    let uid: uid_t

    init(uid: uid_t = getuid()) { self.uid = uid }

    func read() -> PortSnapshot {
        var snapshot = PortSnapshot()
        for pid in LibprocProcess.pids(ownedBy: uid) {
            snapshot.sockets += Self.listeningSockets(of: pid)
        }
        for pid in Set(snapshot.sockets.map(\.pid)) {
            guard let (identity, shortName) = LibprocProcess.info(of: pid), identity.uid == uid else { continue }
            let name = identity.path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? shortName
            snapshot.processes[pid] = PortProcess(identity: identity, name: name, commandLine: LibprocProcess.commandLine(of: pid))
        }
        return snapshot
    }

    static func listeningSockets(of pid: Int32) -> [ListeningSocket] {
        let bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bytes > 0 else { return [] }
        // The count can grow between the two calls; the extra room keeps a new descriptor from being cut off.
        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(bytes) / MemoryLayout<proc_fdinfo>.stride + 32)
        let written = descriptors.withUnsafeMutableBytes { proc_pidinfo(pid, PROC_PIDLISTFDS, 0, $0.baseAddress, Int32($0.count)) }
        guard written > 0 else { return [] }
        var sockets: [ListeningSocket] = []
        for descriptor in descriptors.prefix(Int(written) / MemoryLayout<proc_fdinfo>.stride)
        where descriptor.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
            guard let raw = rawSocket(pid: pid, descriptor: descriptor.proc_fd),
                  let socket = ListeningSocket(raw: raw, pid: pid) else { continue }
            sockets.append(socket)
        }
        return sockets
    }

    /// The Internet socket behind a descriptor; nil for any other kind, or when it closed in the meantime.
    private static func rawSocket(pid: Int32, descriptor: Int32) -> RawSocket? {
        var info = socket_fdinfo()
        let size = withUnsafeMutableBytes(of: &info) { proc_pidfdinfo(pid, descriptor, PROC_PIDFDSOCKETINFO, $0.baseAddress, Int32($0.count)) }
        guard size == Int32(MemoryLayout<socket_fdinfo>.size) else { return nil }
        let kind = info.psi.soi_kind
        if kind == Int32(SOCKINFO_TCP), info.psi.soi_protocol == IPPROTO_TCP {
            let tcp = info.psi.soi_proto.pri_tcp
            return raw(.tcp, tcp.tcpsi_ini, tcpState: tcp.tcpsi_state)
        }
        if kind == Int32(SOCKINFO_IN), info.psi.soi_protocol == IPPROTO_UDP {
            return raw(.udp, info.psi.soi_proto.pri_in, tcpState: 0)
        }
        return nil
    }

    private static func raw(_ proto: PortProtocol, _ socket: in_sockinfo, tcpState: Int32) -> RawSocket {
        RawSocket(
            proto: proto, tcpState: tcpState, vflag: socket.insi_vflag, localPort: socket.insi_lport, foreignPort: socket.insi_fport,
            localAddress: withUnsafeBytes(of: socket.insi_laddr) { Array($0.prefix(16)) }
        )
    }
}
