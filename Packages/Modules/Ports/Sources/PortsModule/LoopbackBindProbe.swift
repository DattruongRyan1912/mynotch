import Darwin

/// Tries to bind the port on 127.0.0.1 and lets go at once, never listening, so nothing can connect and no firewall prompt shows.
nonisolated struct LoopbackBindProbe: PortProbe {
    func probe(port: UInt16) -> PortProbeResult {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return .unknown }
        defer { close(descriptor) }
        // Connections left over from a server that was just stopped must not make the port look taken.
        var on: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = UInt32(0x7f00_0001).bigEndian
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        if result == 0 { return .free }
        return errno == EADDRINUSE ? .inUse : .unknown
    }
}
