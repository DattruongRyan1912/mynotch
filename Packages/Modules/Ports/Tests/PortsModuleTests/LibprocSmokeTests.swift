import Darwin
import Foundation
import Testing
@testable import PortsModule

/// A socket this test process owns, bound to a loopback address (never a wildcard, which could raise the firewall's prompt) and
/// closed when the value goes out of scope.
nonisolated final class LoopbackSocket {
    let descriptor: Int32
    let port: UInt16

    /// A listening TCP socket (or a bound UDP one) on 127.0.0.1 or ::1. Port 0 asks the system for a free one.
    init?(v6: Bool = false, udp: Bool = false, port requested: UInt16 = 0, reuse: Bool = false) {
        let fd = socket(v6 ? AF_INET6 : AF_INET, udp ? SOCK_DGRAM : SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        if reuse {
            var on: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
        }
        guard let assigned = Self.bindLoopback(fd, v6: v6, port: requested), assigned != 0, udp || listen(fd, 4) == 0 else {
            close(fd)
            return nil
        }
        descriptor = fd
        port = assigned
    }

    deinit { close(descriptor) }

    /// Binds and returns the port the system gave, in host order.
    private static func bindLoopback(_ fd: Int32, v6: Bool, port: UInt16) -> UInt16? {
        if v6 {
            var address = sockaddr_in6()
            address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            address.sin6_family = sa_family_t(AF_INET6)
            address.sin6_port = port.bigEndian
            address.sin6_addr = in6addr_loopback
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) }
            }
            var length = socklen_t(MemoryLayout<sockaddr_in6>.size)
            let named = withUnsafeMutablePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
            }
            return bound == 0 && named == 0 ? UInt16(bigEndian: address.sin6_port) : nil
        }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = UInt32(0x7f00_0001).bigEndian
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        return bound == 0 && named == 0 ? UInt16(bigEndian: address.sin_port) : nil
    }
}

/// The real libproc, on sockets this process opens itself.
@Suite struct LibprocSmokeTests {
    func entries() -> [PortEntry] { PortEntry.entries(from: LibprocPortSource().read()) }
    func mine(_ port: UInt16, _ proto: PortProtocol = .tcp) -> PortEntry? {
        entries().first { $0.pid == getpid() && $0.port == port && $0.proto == proto }
    }

    @Test func aListeningSocketOnAnEphemeralPortIsFoundWithItsOwnerAndGoneOnceClosed() throws {
        var socket = try #require(LoopbackSocket())
        let port = socket.port
        let found = try #require(mine(port), "the listening socket is listed")
        #expect(found.proto == .tcp)
        #expect(found.addressText == "127.0.0.1")
        #expect(found.isLocalOnly)
        #expect(!found.process.name.isEmpty)
        #expect(found.process.identity.uid == getuid())
        #expect(found.process.identity.path != nil)
        #expect(found.process.identity.startTime > 0)
        #expect(found.process.commandLine?.isEmpty == false, "the command line of our own process is readable")

        socket = try #require(LoopbackSocket(port: 0))   // replaces the first one, which closes
        #expect(mine(port) == nil, "closed, so not listed")
        _ = socket
    }

    @Test func theSamePortOnIPv4AndIPv6OfOneProcessIsOneRow() throws {
        var pair: (LoopbackSocket, LoopbackSocket)?
        for _ in 0..<20 where pair == nil {
            guard let v4 = LoopbackSocket() else { continue }
            if let v6 = LoopbackSocket(v6: true, port: v4.port) { pair = (v4, v6) }
        }
        let (v4, _) = try #require(pair, "a port that is free on both families")
        let matches = entries().filter { $0.pid == getpid() && $0.port == v4.port }
        #expect(matches.count == 1)
        #expect(matches.first?.addressText == "127.0.0.1, ::1")
    }

    @Test func anIPv6OnlyLoopbackListenerIsReadWithItsAddressFamily() throws {
        let socket = try #require(LoopbackSocket(v6: true))
        let found = try #require(mine(socket.port))
        #expect(found.addressText == "::1")
        #expect(found.isLocalOnly)
    }

    @Test func aBoundUDPSocketIsListedAsUDP() throws {
        let socket = try #require(LoopbackSocket(udp: true))
        let found = try #require(mine(socket.port, .udp))
        #expect(found.addressText == "127.0.0.1")
        #expect(mine(socket.port, .tcp) == nil)
    }

    @Test func theReadSkipsTheProcessesOfOtherUsers() {
        let snapshot = LibprocPortSource().read()
        #expect(snapshot.processes.values.allSatisfy { $0.identity.uid == getuid() })
        // launchd listens for others on a few sockets; it belongs to root, so it must not show up.
        #expect(snapshot.processes[1] == nil)
    }

    @Test func aSourceForAnotherUserSeesNoneOfOurSockets() throws {
        let socket = try #require(LoopbackSocket())
        let others = PortEntry.entries(from: LibprocPortSource(uid: getuid() &+ 12345).read())
        #expect(!others.contains { $0.port == socket.port })
    }
}

@Suite struct LoopbackBindProbeTests {
    let probe = LoopbackBindProbe()

    @Test func aPortNobodyHoldsIsFree() throws {
        // The socket closes when the closure returns, so the port is free again.
        let port = try #require({ LoopbackSocket()?.port }())
        #expect(probe.probe(port: port) == .free)
    }

    @Test func aListeningPortIsInUseEvenWhenTheServerSetReuseAddressLikeMostDo() throws {
        let plain = try #require(LoopbackSocket())
        #expect(probe.probe(port: plain.port) == .inUse)
        let reusing = try #require(LoopbackSocket(reuse: true))
        #expect(probe.probe(port: reusing.port) == .inUse)
    }

    @Test func aPrivilegedPortTheUserCannotBindIsUnknownNotFree() throws {
        try #require(getuid() != 0)
        // Binding below 1024 is refused before anyone's use of it is looked at.
        let result = probe.probe(port: 1)
        #expect(result == .unknown || result == .inUse)
        #expect(result != .free)
    }
}
