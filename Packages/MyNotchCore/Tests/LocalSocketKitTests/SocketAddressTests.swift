import Foundation
import Testing
import LocalSocketKit

@Suite struct SocketAddressTests {
    @Test func aSunPathHoldsOneHundredAndThreeBytesAndItsTerminatingZero() {
        #expect(SocketAddress.maxPathLength == 103)
    }

    @Test func anAddressHoldsAPathUpToTheLimitAndRefusesOneByteMore() {
        let fits = String(repeating: "a", count: SocketAddress.maxPathLength)
        #expect(SocketAddress(path: fits) != nil)
        #expect(SocketAddress(path: fits + "a") == nil)
        #expect(SocketAddress(path: "/tmp/" + String(repeating: "a", count: 98)) != nil)
        #expect(SocketAddress(path: "/tmp/" + String(repeating: "a", count: 99)) == nil)
    }

    @Test func theLimitIsInBytesNotCharacters() {
        // "ê" is two bytes: 52 of them are 104 bytes.
        #expect(SocketAddress(path: String(repeating: "ê", count: 51)) != nil)
        #expect(SocketAddress(path: String(repeating: "ê", count: 52)) == nil)
    }

    @Test func anAddressIsAUnixSocketAddressHoldingThePathAndItsTerminatingZero() throws {
        let address = try #require(SocketAddress(path: "/tmp/mn-1/agent.sock"))
        var value = address.value
        #expect(value.sun_family == sa_family_t(AF_UNIX))
        let stored = withUnsafeBytes(of: &value.sun_path) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
        #expect(stored == "/tmp/mn-1/agent.sock")
    }

    @Test func aPathOfTheLimitIsStillTerminated() throws {
        let path = String(repeating: "a", count: SocketAddress.maxPathLength)
        var value = try #require(SocketAddress(path: path)).value
        let stored = withUnsafeBytes(of: &value.sun_path) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
        #expect(stored == path)
    }
}
