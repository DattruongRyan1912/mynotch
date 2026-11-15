import Testing
@testable import PortsModule

@Suite struct PortAddressTests {
    @Test func anIPv4LoopbackIsLocalOnly() throws {
        let address = try #require(PortAddress(vflag: PortAddress.v4Flag, bytes: Bytes.v4(127, 0, 0, 1)))
        #expect(address.text == "127.0.0.1")
        #expect(address.scope == .loopback)
        #expect(address.isLocalOnly)
        #expect(!address.isIPv6)
    }

    @Test func theWholeOf127IsLoopback() throws {
        let address = try #require(PortAddress(vflag: PortAddress.v4Flag, bytes: Bytes.v4(127, 12, 0, 9)))
        #expect(address.scope == .loopback)
    }

    @Test func zeroZeroZeroZeroIsEveryInterface() throws {
        let address = try #require(PortAddress(vflag: PortAddress.v4Flag, bytes: Bytes.v4(0, 0, 0, 0)))
        #expect(address.text == "0.0.0.0")
        #expect(address.scope == .any)
        #expect(!address.isLocalOnly)
    }

    @Test func aLocalNetworkAddressIsReachableFromTheNetwork() throws {
        let address = try #require(PortAddress(vflag: PortAddress.v4Flag, bytes: Bytes.v4(192, 168, 1, 20)))
        #expect(address.text == "192.168.1.20")
        #expect(address.scope == .specific)
        #expect(!address.isLocalOnly)
    }

    @Test func anIPv6LoopbackIsLocalOnly() throws {
        let address = try #require(PortAddress(vflag: PortAddress.v6Flag, bytes: Bytes.v6Loopback))
        #expect(address.text == "::1")
        #expect(address.scope == .loopback)
        #expect(address.isIPv6)
    }

    @Test func theIPv6WildcardIsEveryInterface() throws {
        let address = try #require(PortAddress(vflag: PortAddress.v6Flag, bytes: Bytes.v6Any))
        #expect(address.text == "::")
        #expect(address.scope == .any)
    }

    @Test func aSpecificIPv6AddressIsReachableFromTheNetwork() throws {
        let address = try #require(PortAddress(vflag: PortAddress.v6Flag, bytes: Bytes.v6([0xfe80, 0, 0, 0, 0, 0, 0, 1])))
        #expect(address.text == "fe80::1")
        #expect(address.scope == .specific)
    }

    @Test func aDualStackSocketHasBothBitsAndItsAddressIsTheIPv6OneNotTheTrailingFourBytes() throws {
        // `::1` ends in the bytes 0, 0, 0, 1; read as IPv4 they would be 0.0.0.1, which is neither loopback nor wildcard.
        let loopback = try #require(PortAddress(vflag: PortAddress.v4Flag | PortAddress.v6Flag, bytes: Bytes.v6Loopback))
        #expect(loopback.text == "::1")
        #expect(loopback.scope == .loopback)
        let any = try #require(PortAddress(vflag: PortAddress.v4Flag | PortAddress.v6Flag, bytes: Bytes.v6Any))
        #expect(any.text == "::")
        #expect(any.scope == .any)
    }

    @Test func anIPv4MappedAddressTakesTheScopeOfTheIPv4OneInsideIt() throws {
        let mapped = Bytes.v6([0, 0, 0, 0, 0, 0xffff, 0x7f00, 0x0001])
        let loopback = try #require(PortAddress(vflag: PortAddress.v6Flag, bytes: mapped))
        #expect(loopback.text == "::ffff:127.0.0.1")
        #expect(loopback.scope == .loopback)
        let lan = try #require(PortAddress(vflag: PortAddress.v6Flag, bytes: Bytes.v6([0, 0, 0, 0, 0, 0xffff, 0xc0a8, 0x0114])))
        #expect(lan.scope == .specific)
    }

    @Test func noFamilyBitOrTheWrongLengthIsNoAddress() {
        #expect(PortAddress(vflag: 0, bytes: Bytes.v4(127, 0, 0, 1)) == nil)
        #expect(PortAddress(vflag: PortAddress.v4Flag, bytes: [127, 0, 0, 1]) == nil)
    }
}

@Suite struct ListeningSocketTests {
    func raw(
        _ proto: PortProtocol = .tcp, state: Int32 = RawSocket.listenState, port: UInt16 = 3000, foreign: Int32 = 0,
        vflag: UInt8 = PortAddress.v4Flag, address: [UInt8] = Bytes.v4(127, 0, 0, 1)
    ) -> RawSocket {
        // libproc stores the port in network byte order.
        RawSocket(
            proto: proto, tcpState: state, vflag: vflag, localPort: Int32(port.bigEndian), foreignPort: foreign, localAddress: address
        )
    }

    @Test func aListeningTCPSocketIsKeptWithItsPortInHostOrder() throws {
        let socket = try #require(ListeningSocket(raw: raw(port: 5173), pid: 77))
        #expect(socket.port == 5173)
        #expect(socket.pid == 77)
        #expect(socket.proto == .tcp)
        #expect(socket.address == .loopback4)
    }

    @Test func aPortWhoseByteOrderIsSwappedWouldNotBeTheSamePort() throws {
        // 3000 is 0x0BB8; the same two bytes the other way round are 47115, which is what a missing byte swap would show.
        let socket = try #require(ListeningSocket(raw: raw(port: 3000), pid: 1))
        #expect(socket.port != 0xB80B)
        #expect(socket.port == 3000)
    }

    @Test func aTCPSocketThatIsNotListeningIsNot() {
        for state: Int32 in [0, 2, 3, 4, 5, 6, 7, 8, 9, 10] {
            #expect(ListeningSocket(raw: raw(state: state), pid: 1) == nil, "state \(state)")
        }
    }

    @Test func aBoundUnconnectedUDPSocketIsKeptAndAConnectedOneIsNot() throws {
        let bound = try #require(ListeningSocket(raw: raw(.udp, state: 0, port: 5353), pid: 1))
        #expect(bound.proto == .udp)
        #expect(ListeningSocket(raw: raw(.udp, state: 0, port: 5353, foreign: Int32(UInt16(443).bigEndian)), pid: 1) == nil)
    }

    @Test func aSocketWithNoPortOrNoFamilyIsLeftOut() {
        #expect(ListeningSocket(raw: raw(port: 0), pid: 1) == nil)
        #expect(ListeningSocket(raw: raw(vflag: 0), pid: 1) == nil)
    }

    @Test func anIPv6SocketKeepsItsV6Address() throws {
        let socket = try #require(ListeningSocket(raw: raw(vflag: PortAddress.v6Flag, address: Bytes.v6Loopback), pid: 1))
        #expect(socket.address == .loopback6)
    }
}

@Suite struct PortEntryTests {
    func snapshot(_ sockets: [ListeningSocket], processes: [PortProcess]) -> PortSnapshot {
        PortSnapshot(sockets: sockets, processes: Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) }))
    }

    @Test func thePortHeldOnIPv4AndIPv6ByOneProcessIsOneRow() {
        let node = PortProcess.make(pid: 10)
        let entries = PortEntry.entries(from: snapshot([
            ListeningSocket(pid: 10, port: 3000, proto: .tcp, address: .loopback6),
            ListeningSocket(pid: 10, port: 3000, proto: .tcp, address: .loopback4),
            ListeningSocket(pid: 10, port: 3000, proto: .tcp, address: .loopback4),
        ], processes: [node]))
        #expect(entries.count == 1)
        #expect(entries[0].addresses == [.loopback4, .loopback6], "IPv4 first, each once")
        #expect(entries[0].addressText == "127.0.0.1, ::1")
    }

    @Test func theSamePortHeldByTwoProcessesIsTwoRowsAndTCPAndUDPAreApart() {
        let entries = PortEntry.entries(from: snapshot([
            ListeningSocket(pid: 10, port: 53, proto: .udp, address: .any4),
            ListeningSocket(pid: 11, port: 53, proto: .tcp, address: .any4),
            ListeningSocket(pid: 10, port: 53, proto: .tcp, address: .any4),
        ], processes: [.make(pid: 10), .make(pid: 11)]))
        #expect(entries.map(\.id) == ["tcp:53:10", "tcp:53:11", "udp:53:10"])
    }

    @Test func rowsAreSortedByPort() {
        let entries = PortEntry.entries(from: snapshot([
            ListeningSocket(pid: 10, port: 8080, proto: .tcp, address: .any4),
            ListeningSocket(pid: 11, port: 443, proto: .tcp, address: .any4),
            ListeningSocket(pid: 12, port: 3000, proto: .tcp, address: .any4),
        ], processes: [.make(pid: 10), .make(pid: 11), .make(pid: 12)]))
        #expect(entries.map(\.port) == [443, 3000, 8080])
    }

    @Test func aSocketWhoseProcessIsUnknownIsLeftOut() {
        let entries = PortEntry.entries(from: snapshot([
            ListeningSocket(pid: 10, port: 3000, proto: .tcp, address: .any4),
            ListeningSocket(pid: 99, port: 3001, proto: .tcp, address: .any4),
        ], processes: [.make(pid: 10)]))
        #expect(entries.map(\.port) == [3000])
    }

    @Test func aRowIsLocalOnlyOnlyWhenEveryAddressIs() {
        #expect(PortEntry.make(addresses: [.loopback4, .loopback6]).isLocalOnly)
        #expect(!PortEntry.make(addresses: [.loopback4, .any6]).isLocalOnly, "the wider reach wins")
        #expect(!PortEntry.make(addresses: [.any4]).isLocalOnly)
        #expect(!PortEntry.make(addresses: [.lan]).isLocalOnly)
    }
}

@Suite struct AppBundleTests {
    @Test func theAppIsTheOutermostOne() {
        let helper = "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper.app/Contents/MacOS/Code Helper"
        #expect(AppBundle.outermost(in: helper) == "/Applications/Visual Studio Code.app")
        #expect(AppBundle.outermost(in: "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter")
            == "/System/Library/CoreServices/ControlCenter.app")
    }

    @Test func aProcessOutsideAnyAppHasNone() {
        #expect(AppBundle.outermost(in: "/opt/homebrew/bin/node") == nil)
        #expect(AppBundle.outermost(in: "/usr/local/bin/tool.app") == nil, "the executable itself is not a bundle")
        #expect(AppBundle.outermost(in: "") == nil)
    }

    @Test func aProcessNamesItselfAfterItsAppWhenItHasOne() {
        let chrome = PortProcess.make(name: "Google Chrome Helper", path: "/Applications/Google Chrome.app/Contents/Frameworks/X/Google Chrome Helper")
        #expect(chrome.appName == "Google Chrome")
        #expect(chrome.displayName == "Google Chrome")
        #expect(PortProcess.make().displayName == "node")
    }
}

@Suite struct ProcArgumentsTests {
    /// `argc`, the path and its NUL padding, the arguments, then the environment, as the kernel returns them.
    func buffer(argc: Int32, path: String, arguments: [String], environment: [String]) -> [UInt8] {
        var bytes = withUnsafeBytes(of: argc) { Array($0) }
        bytes += Array(path.utf8) + [0, 0, 0]
        for argument in arguments { bytes += Array(argument.utf8) + [0] }
        for variable in environment { bytes += Array(variable.utf8) + [0] }
        return bytes
    }

    @Test func onlyTheArgumentsAreReadNeverTheEnvironment() {
        let bytes = buffer(
            argc: 3, path: "/opt/homebrew/bin/node", arguments: ["node", "/Users/me/app/server.js", "--port=3000"],
            environment: ["API_KEY=hunter2", "HOME=/Users/me"]
        )
        #expect(ProcArguments.parse(bytes) == ["node", "/Users/me/app/server.js", "--port=3000"])
        #expect(!ProcArguments.parse(bytes).joined().contains("hunter2"))
    }

    @Test func aTruncatedOrEmptyBufferGivesWhatIsThere() {
        #expect(ProcArguments.parse([]) == [])
        #expect(ProcArguments.parse([3, 0, 0]) == [])
        let cut = buffer(argc: 5, path: "/bin/x", arguments: ["x", "y"], environment: [])
        #expect(ProcArguments.parse(cut) == ["x", "y"])
    }

    @Test func theLineShowsTheProgramAndTheFirstFileByName() {
        #expect(ProcArguments.display(["node", "/Users/me/app/server.js", "--port=3000"]) == "node server.js --port=3000")
        #expect(ProcArguments.display(["/usr/bin/python3", "-m", "http.server", "8000"]) == "python3 -m http.server 8000")
        #expect(ProcArguments.display([]) == nil)
    }

    @Test func aLongLineIsCut() throws {
        let line = try #require(ProcArguments.display(["node", String(repeating: "a", count: 500)], limit: 50))
        #expect(line.count == 51)
        #expect(line.hasSuffix("…"))
    }
}
