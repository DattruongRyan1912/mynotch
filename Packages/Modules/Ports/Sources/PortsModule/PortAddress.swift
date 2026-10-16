import Foundation

/// The local address a socket is bound to, and whether that makes the port reachable from other machines.
nonisolated struct PortAddress: Hashable, Sendable {
    enum Scope: Sendable {
        /// 127.0.0.0/8 and ::1: only this Mac can connect.
        case loopback
        /// 0.0.0.0 and ::, which every interface answers on.
        case any
        /// One interface's address, such as the Mac's address on the local network.
        case specific
    }

    /// The `insi_vflag` bits libproc sets: a dual-stack socket on `::` can carry both.
    static let v4Flag: UInt8 = 0x1
    static let v6Flag: UInt8 = 0x2

    let text: String
    let scope: Scope

    var isLocalOnly: Bool { scope == .loopback }
    var isIPv6: Bool { text.contains(":") }

    /// `bytes` are the 16 bytes of libproc's address union: an IPv6 address as it is, an IPv4 one in the last four. The v6 bit is
    /// looked at first, because a dual-stack socket has both bits and its address is the v6 one. Nil when neither bit is set.
    init?(vflag: UInt8, bytes: [UInt8]) {
        guard bytes.count == 16 else { return nil }
        if vflag & Self.v6Flag != 0 {
            self.init(v6: bytes)
        } else if vflag & Self.v4Flag != 0 {
            self.init(v4: Array(bytes[12..<16]))
        } else {
            return nil
        }
    }

    private init(v4 octets: [UInt8]) {
        text = octets.map(String.init).joined(separator: ".")
        scope = Self.scope(ofV4: octets)
    }

    private init(v6 bytes: [UInt8]) {
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        let printed = bytes.withUnsafeBytes { inet_ntop(AF_INET6, $0.baseAddress, &buffer, socklen_t(buffer.count)) }
        text = printed == nil ? "?" : String(cChars: buffer)
        let isMapped = bytes[0..<10].allSatisfy { $0 == 0 } && bytes[10] == 0xff && bytes[11] == 0xff
        if bytes.allSatisfy({ $0 == 0 }) {
            scope = .any
        } else if bytes[0..<15].allSatisfy({ $0 == 0 }) && bytes[15] == 1 {
            scope = .loopback
        } else if isMapped {
            scope = Self.scope(ofV4: Array(bytes[12..<16]))
        } else {
            scope = .specific
        }
    }

    private static func scope(ofV4 octets: [UInt8]) -> Scope {
        if octets[0] == 127 { return .loopback }
        if octets.allSatisfy({ $0 == 0 }) { return .any }
        return .specific
    }
}

extension String {
    /// The text up to the first NUL of a C buffer.
    nonisolated init(cChars buffer: [CChar]) {
        self.init(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
