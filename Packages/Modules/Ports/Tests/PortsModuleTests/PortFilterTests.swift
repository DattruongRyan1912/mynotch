import Testing
@testable import PortsModule

@Suite struct PortFilterTests {
    let node = PortEntry.make(port: 3000, process: .make(pid: 10, name: "node", command: "node server.js --watch"))
    let vite = PortEntry.make(port: 5173, process: .make(pid: 11, name: "node", command: "node vite.js"))
    let postgres = PortEntry.make(
        port: 5432, process: .make(pid: 12, name: "postgres", command: nil, path: "/Applications/Postgres.app/Contents/Versions/16/bin/postgres")
    )
    let http = PortEntry.make(port: 8080, process: .make(pid: 13, name: "Python", command: "python3 -m http.server 8080"))
    let mdns = PortEntry.make(port: 5353, proto: .udp, process: .make(pid: 14, name: "Chrome", command: nil))

    var all: [PortEntry] { [node, vite, postgres, http, mdns] }

    @Test func anEmptyFilterKeepsEveryTCPRowAndUDPOnlyOnRequest() {
        #expect(PortFilter.apply(all, query: "", showUDP: false).map(\.port) == [3000, 5173, 5432, 8080])
        #expect(PortFilter.apply(all, query: "  ", showUDP: true).map(\.port) == [3000, 5173, 5432, 8080, 5353])
    }

    @Test func aNumberMatchesTheStartOfAPort() {
        #expect(PortFilter.apply(all, query: "5", showUDP: true).map(\.port) == [5173, 5432, 5353])
        #expect(PortFilter.apply(all, query: "543", showUDP: true).map(\.port) == [5432])
        #expect(PortFilter.apply(all, query: "5432", showUDP: false).map(\.port) == [5432])
        #expect(PortFilter.apply(all, query: ":3000", showUDP: false).map(\.port) == [3000])
        #expect(PortFilter.apply(all, query: "000", showUDP: false).isEmpty, "the middle of a port is not a match")
    }

    @Test func aNumberDoesNotMatchANameOrACommand() {
        #expect(PortFilter.apply(all, query: "3", showUDP: false).map(\.port) == [3000], "the 3 in nothing but the port")
    }

    @Test func aNameMatchesTheProcessTheAppTheCommandAndTheHintIgnoringCaseAndAccents() {
        #expect(PortFilter.apply(all, query: "NODE", showUDP: false).map(\.port) == [3000, 5173])
        #expect(PortFilter.apply(all, query: "http.server", showUDP: false).map(\.port) == [8080])
        #expect(PortFilter.apply(all, query: "postgres", showUDP: false).map(\.port) == [5432], "its name and its app, once")
        #expect(PortFilter.apply(all, query: "vite", showUDP: false).map(\.port) == [5173], "the hint of 5173")
        #expect(PortFilter.apply(all, query: "pythön", showUDP: false).map(\.port) == [8080])
        #expect(PortFilter.apply(all, query: "mongo", showUDP: false).isEmpty)
    }
}

@Suite struct DevPortLabelTests {
    @Test func theWellKnownDevelopmentPortsHaveALabel() {
        let ports: [UInt16] = [3000, 3001, 4200, 5000, 5173, 5432, 6379, 8000, 8080, 8888, 9000, 27017]
        for port in ports {
            #expect(DevPortLabel.label(for: port) != nil, "\(port)")
        }
        #expect(DevPortLabel.names.count == ports.count)
    }

    @Test func otherPortsHaveNone() {
        #expect(DevPortLabel.label(for: 22) == nil)
        #expect(DevPortLabel.label(for: 49152) == nil)
    }
}

@Suite struct PortQuickCheckTests {
    let node = PortEntry.make(port: 3000, process: .make(pid: 10, name: "node"))

    @Test func aPortIsReadFromWhatWasTyped() {
        #expect(PortQuickCheck.port(from: "3000") == 3000)
        #expect(PortQuickCheck.port(from: " :3000 ") == 3000)
        #expect(PortQuickCheck.port(from: "65535") == 65535)
        #expect(PortQuickCheck.port(from: "0") == nil)
        #expect(PortQuickCheck.port(from: "65536") == nil)
        #expect(PortQuickCheck.port(from: "-1") == nil)
        #expect(PortQuickCheck.port(from: "30a0") == nil)
        #expect(PortQuickCheck.port(from: "") == nil)
        #expect(PortQuickCheck.port(from: "٣٠٠٠") == nil, "digits of another script are no port")
    }

    @Test func aHeldPortNamesItsOwner() {
        let answer = PortQuickCheck.answer(query: "3000", entries: [node], probe: nil)
        #expect(answer == .owner(node, others: 0))
        #expect(answer.message == "Cổng 3000: node · PID 10")
    }

    @Test func severalHoldersAreCountedAndTCPComesFirst() {
        let udp = PortEntry.make(port: 3000, proto: .udp, process: .make(pid: 5, name: "udpd"))
        let worker = PortEntry.make(port: 3000, process: .make(pid: 11, name: "node"))
        let answer = PortQuickCheck.answer(query: "3000", entries: [udp, worker, node], probe: nil)
        #expect(answer == .owner(node, others: 2))
        #expect(answer.message == "Cổng 3000: node · PID 10 và 2 nữa")
    }

    @Test func aPortNobodyOfTheUsersHoldsIsOnlyFreeWhenTheSystemAgrees() {
        #expect(PortQuickCheck.answer(query: "3001", entries: [node], probe: nil) == .checking(3001))
        #expect(PortQuickCheck.answer(query: "3001", entries: [node], probe: PortProbeOutcome(port: 3001, result: .free)).message == "Cổng 3001 trống")
        let busy = PortQuickCheck.answer(query: "5432", entries: [node], probe: PortProbeOutcome(port: 5432, result: .inUse))
        #expect(busy == .busyUnseen(5432))
        #expect(busy.message?.contains("đang bị chiếm") == true)
        #expect(busy.message?.contains("trống") == false)
        let unknown = PortQuickCheck.answer(query: "80", entries: [], probe: PortProbeOutcome(port: 80, result: .unknown))
        #expect(unknown == .unseen(80))
        #expect(unknown.message?.contains("trống") == false)
    }

    @Test func anAnswerForAnotherPortIsNotUsed() {
        let stale = PortProbeOutcome(port: 300, result: .free)
        #expect(PortQuickCheck.answer(query: "3000", entries: [], probe: stale) == .checking(3000))
    }

    @Test func nothingTypedAndNonsenseTypedAreTold() {
        #expect(PortQuickCheck.answer(query: "", entries: [node], probe: nil) == .empty)
        #expect(PortQuickCheck.answer(query: "  ", entries: [node], probe: nil).message == nil)
        #expect(PortQuickCheck.answer(query: "abc", entries: [node], probe: nil) == .invalid)
        #expect(PortQuickCheck.answer(query: "70000", entries: [node], probe: nil).message == "Nhập số cổng từ 1 đến 65535")
    }
}
