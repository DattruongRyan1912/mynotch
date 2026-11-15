import Foundation
import Testing
@testable import ClipboardModule

/// Which addresses may be opened to read a link's page: the table is the rule, one row per way a link might point somewhere private.
@Suite struct ClipboardLinkGuardTests {
    nonisolated static let allowed = [
        "https://example.com/", "http://example.com/path?q=1#fragment", "https://sub.example.co.uk:8443/a/b", "HTTPS://EXAMPLE.COM/",
        "https://example.com./", "https://xn--bcher-kva.de/",
        "https://93.184.216.34/", "https://1.1.1.1/", "https://8.8.8.8:8080/x",
        // The edges of the private ranges: the address just outside each is public.
        "http://172.15.255.255/", "http://172.32.0.1/", "http://192.167.255.255/", "http://192.169.0.1/", "http://11.0.0.1/",
        "http://9.255.255.255/", "http://100.63.255.255/", "http://100.128.0.1/", "http://169.253.0.1/", "http://126.255.255.255/",
        "http://128.0.0.1/",
        "https://[2606:4700:4700::1111]/", "https://[2a00:1450:4001:81b::200e]:443/",
    ]

    nonisolated static let refused = [
        // Not a web address at all.
        "file:///etc/passwd", "ftp://example.com/file", "mailto:someone@example.com", "javascript:alert(1)", "data:text/html,hello",
        "ssh://example.com", "http:///no-host",
        // This computer.
        "http://localhost/", "http://localhost:3000/admin", "http://LOCALHOST./", "http://foo.localhost/", "http://127.0.0.1/", "http://127.1/",
        "http://127.255.255.254/", "http://0.0.0.0/", "http://0/", "http://[::1]/", "http://[::]/",
        // The resolver's other spellings of an IPv4 address.
        "http://2130706433/", "http://0x7f000001/", "http://0x7f.0.0.1/", "http://0177.0.0.1/", "http://017700000001/", "http://127.0.1/",
        "http://3232235777/",
        // Private, shared, link-local (a cloud's metadata address), multicast and reserved.
        "http://10.0.0.1/", "http://10.255.255.255/", "http://172.16.0.1/", "http://172.31.255.255/", "http://192.168.0.1/",
        "http://192.168.255.255/", "http://169.254.169.254/latest/meta-data/", "http://100.64.0.1/", "http://100.127.255.255/",
        "http://224.0.0.1/", "http://239.255.255.250/", "http://240.0.0.1/", "http://255.255.255.255/", "http://198.18.0.1/",
        "http://192.0.0.1/", "http://192.0.2.1/", "http://198.51.100.1/", "http://203.0.113.1/",
        // IPv6: unique local, link-local (with and without a zone), site-local, multicast, documentation, and every way of hiding IPv4.
        "http://[fc00::1]/", "http://[fd12:3456:789a::1]/", "http://[fe80::1]/", "http://[fe80::1%25en0]/", "http://[fec0::1]/",
        "http://[ff02::1]/", "http://[2001:db8::1]/", "http://[::ffff:127.0.0.1]/", "http://[::ffff:7f00:1]/", "http://[::ffff:10.0.0.1]/",
        "http://[::127.0.0.1]/", "http://[64:ff9b::7f00:1]/", "http://[2002:7f00:1::]/", "http://[2001::1]/", "http://[::2]/",
        // Names that are never public.
        "http://router/", "http://intranet/", "http://printer.local/", "http://nas.lan/", "http://wiki.internal/", "http://host.home.arpa/",
        "http://foo.test/", "http://foo.example/", "http://foo.invalid/", "http://x.corp/", "http://x.intranet/", "http://x.localdomain/",
        "http://hidden.onion/", "http://1.2.3.4.5/", "http://256.1.1.1/", "http://example.123/",
        // A user name or a password.
        "https://user:pass@example.com/", "https://user@example.com/", "https://:pass@example.com/", "https://@example.com/",
        "https://example.com@evil.example/", "http://user:pass@127.0.0.1/",
    ]

    @Test(arguments: allowed)
    func publicAddressesAreAllowed(_ text: String) throws {
        let url = try #require(URL(string: text))
        #expect(ClipboardLinkGuard.allows(url), "\(text)")
    }

    /// Every row is a real URL: a row that cannot be made into one would pass without testing anything, so it fails instead.
    @Test(arguments: refused)
    func everythingElseIsRefused(_ text: String) throws {
        // `example.com@evil.example` has the user name "example.com": credentials, whatever the host.
        let url = try #require(URL(string: text), "\(text) is not an address")
        #expect(!ClipboardLinkGuard.allows(url), "\(text)")
    }

    @Test func theTablesAreBigEnough() {
        #expect(Self.refused.count >= 20)
        #expect(Self.allowed.count >= 10)
    }

    @Test func aHostIsReadTheWayAResolverReadsIt() throws {
        #expect(ClipboardLinkGuard.host(of: try #require(URL(string: "https://Example.COM./x"))) == "example.com")
        #expect(ClipboardLinkGuard.host(of: try #require(URL(string: "http://[::1]:8080/"))) == "::1")
        #expect(ClipboardLinkGuard.host(of: try #require(URL(string: "http://%6C%6F%63%61%6C%68%6F%73%74/"))) == "localhost")
        #expect(ClipboardLinkGuard.host(of: try #require(URL(string: "mailto:a@b.com"))) == nil)
    }

    /// A percent-encoded host is decoded before the check, so "%6C%6F%63%61%6C%68%6F%73%74" is not a way past it.
    @Test func anEncodedHostIsStillLocalhost() throws {
        guard let url = URL(string: "http://%6C%6F%63%61%6C%68%6F%73%74/") else { return }
        #expect(!ClipboardLinkGuard.allows(url))
    }

    // MARK: Addresses a lookup returns

    @Test(arguments: [
        ("93.184.216.34", false), ("8.8.8.8", false), ("2606:4700:4700::1111", false), ("2a00:1450:4001:81b::200e", false),
        ("127.0.0.1", true), ("10.1.2.3", true), ("192.168.1.10", true), ("169.254.169.254", true), ("0.0.0.0", true),
        ("::1", true), ("::", true), ("fe80::1", true), ("fe80::1%en0", true), ("fd00::1", true), ("::ffff:10.0.0.1", true),
        ("not an address", true), ("", true), ("example.com", true),
    ])
    func addressesFromALookup(_ address: String, _ isForbidden: Bool) {
        #expect(ClipboardLinkGuard.isForbidden(address: address) == isForbidden, "\(address)")
    }

    @Test func aLiteralAddressNeedsNoLookup() {
        #expect(ClipboardLinkGuard.isLiteralAddress("93.184.216.34"))
        #expect(ClipboardLinkGuard.isLiteralAddress("2130706433"))
        #expect(ClipboardLinkGuard.isLiteralAddress("2606:4700:4700::1111"))
        #expect(!ClipboardLinkGuard.isLiteralAddress("example.com"))
        #expect(!ClipboardLinkGuard.isLiteralAddress("127.0.0.1.nip.io"))
    }
}
