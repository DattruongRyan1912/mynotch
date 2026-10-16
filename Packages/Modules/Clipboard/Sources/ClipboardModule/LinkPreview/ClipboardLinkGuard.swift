import Darwin
import Foundation

/// Which addresses MyNotch may open to read a link's page: only public web pages. Everything else is refused before a byte is sent,
/// because a link is whatever someone put on the clipboard and a request to a router, a printer or a cloud's metadata address is
/// something the user did not ask for. Pure, so every rule is a table row in the tests.
nonisolated enum ClipboardLinkGuard {
    /// Names that are never on the public internet. A name with no dot at all is refused as well (`http://router/`).
    private static let privateSuffixes: Set<String> = [
        "local", "localhost", "localdomain", "internal", "intranet", "lan", "home", "corp", "private", "test", "example", "invalid",
        "onion", "home.arpa",
    ]

    /// An http or https address with a host, no user name or password, and a host that is a public name or a public IP address.
    static func allows(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil, components.password == nil,
              let host = host(of: url) else { return false }
        return !isForbidden(host: host)
    }

    /// The host as a resolver would see it: percent-decoded, lower case, no brackets and no trailing dot. nil when there is none.
    static func host(of url: URL) -> String? {
        guard var host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        while host.hasSuffix(".") { host.removeLast() }
        return host.isEmpty ? nil : host
    }

    /// Whether the host, as `host(of:)` gives it, is one MyNotch will not open.
    static func isForbidden(host: String) -> Bool {
        guard !host.isEmpty, host.unicodeScalars.allSatisfy({ $0.value > 0x20 && $0.value != 0x7F && !$0.properties.isWhitespace }) else {
            return true
        }
        // An IPv6 address, with or without a zone (`fe80::1%en0`, never public).
        if host.contains(":") || host.contains("%") { return isForbidden(address: host) }
        // Every spelling of an IPv4 address that the resolver accepts: `2130706433`, `0x7f.1`, `127.1`, `0177.0.0.1`.
        if let v4 = ipv4(host) { return isForbidden(ipv4: v4) }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }), let last = labels.last else { return true }
        // A name whose last part is only digits is not a name (`1.2.3.4.5`, `256.1.1.1`).
        if last.allSatisfy(\.isNumber) { return true }
        if privateSuffixes.contains(String(last)) { return true }
        return host.hasSuffix(".home.arpa")
    }

    /// Whether the host is an IP address and not a name, which needs no lookup.
    static func isLiteralAddress(_ host: String) -> Bool {
        host.contains(":") || host.contains("%") || ipv4(host) != nil
    }

    /// Whether an address written out as the resolver or the system gives it (`93.184.216.34`, `::1`, `fe80::1%en0`) is one MyNotch
    /// will not connect to. Text that is not an address is refused.
    static func isForbidden(address: String) -> Bool {
        if address.contains(":") || address.contains("%") {
            guard !address.contains("%"), let bytes = ipv6(address) else { return true }
            return isForbidden(ipv6: bytes)
        }
        guard let v4 = ipv4(address) else { return true }
        return isForbidden(ipv4: v4)
    }

    // MARK: IPv4

    static func ipv4(_ text: String) -> UInt32? {
        var address = in_addr()
        guard inet_aton(text, &address) != 0 else { return nil }
        return UInt32(bigEndian: address.s_addr)
    }

    /// Anything that is not a public unicast address: this network, private, shared, loopback, link-local, protocol assignments,
    /// documentation, benchmarking, multicast and reserved.
    private static let reservedIPv4: [(base: UInt32, bits: Int)] = [
        (0x0000_0000, 8), (0x0A00_0000, 8), (0x6440_0000, 10), (0x7F00_0000, 8), (0xA9FE_0000, 16), (0xAC10_0000, 12),
        (0xC000_0000, 24), (0xC000_0200, 24), (0xC058_6300, 24), (0xC0A8_0000, 16), (0xC612_0000, 15), (0xC633_6400, 24),
        (0xCB00_7100, 24), (0xE000_0000, 4), (0xF000_0000, 4),
    ]

    private static func isForbidden(ipv4 address: UInt32) -> Bool {
        reservedIPv4.contains { range in
            let mask: UInt32 = range.bits == 0 ? 0 : UInt32.max << UInt32(32 - range.bits)
            return address & mask == range.base & mask
        }
    }

    // MARK: IPv6

    static func ipv6(_ text: String) -> [UInt8]? {
        var address = in6_addr()
        guard inet_pton(AF_INET6, text, &address) == 1 else { return nil }
        return withUnsafeBytes(of: &address) { Array($0) }
    }

    /// Only global unicast (2000::/3) is allowed, less what it holds that is not public: protocol assignments and Teredo (2001::/23),
    /// documentation (2001:db8::/32 and 3fff::/20), and 6to4 (2002::/16), whose address hides an IPv4 one. That leaves out the
    /// loopback, the unspecified address, mapped and compatible IPv4 addresses, NAT64, unique local (fc00::/7), link-local, site-local
    /// and multicast, without a line for each.
    private static func isForbidden(ipv6 bytes: [UInt8]) -> Bool {
        guard bytes.count == 16, bytes[0] & 0xE0 == 0x20 else { return true }
        let first = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        let second = UInt16(bytes[2]) << 8 | UInt16(bytes[3])
        if first == 0x2001, second < 0x0200 { return true }
        if first == 0x2001, second == 0x0DB8 { return true }
        if first == 0x2002 { return true }
        if first == 0x3FFF, second & 0xF000 == 0 { return true }
        return false
    }
}
