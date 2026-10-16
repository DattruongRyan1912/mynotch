import Darwin
import Foundation
import Testing
@testable import PerformanceModule

/// These read this Mac for real (nothing is written, nothing leaves the machine): what is checked is what must be true on any Mac.
@Suite struct SystemMemoryReaderTests {
    @Test func readsTheMemoryOfThisMac() async throws {
        let snapshot = await SystemMemoryReader().read(topProcesses: 0)
        let usage = try #require(snapshot.usage)
        #expect(usage.total == ProcessInfo.processInfo.physicalMemory)
        #expect(usage.used > 0 && usage.used <= usage.total)
        #expect(usage.compressed <= usage.used)
        #expect(usage.pressure != nil, "the pressure level is one of the three")
        #expect(snapshot.processes.isEmpty, "none were asked for")
    }

    @Test func listsTheHeaviestProcessesHeaviestFirst() async {
        let snapshot = await SystemMemoryReader().read(topProcesses: 5)
        #expect(snapshot.processes.count == 5)
        #expect(snapshot.processes.map(\.footprint) == snapshot.processes.map(\.footprint).sorted(by: >))
        #expect(snapshot.processes.allSatisfy { $0.footprint > 0 && !$0.name.isEmpty && $0.pid > 0 })
        #expect(Set(snapshot.processes.map(\.pid)).count == 5)
    }

    @Test func canReadItsOwnFootprintAndFindItsOwnProcess() {
        let pid = getpid()
        #expect(ProcessSource.live.pids().contains(pid))
        #expect((ProcessSource.live.footprint(pid) ?? 0) > 1_000_000, "a test process holds more than a megabyte")
        #expect(ProcessSource.live.name(pid)?.isEmpty == false)
        #expect(ProcessSource.live.path(pid)?.hasPrefix("/") == true)
    }

    @Test func aProcessThatDoesNotExistCannotBeRead() {
        #expect(ProcessSource.live.footprint(Int32.max) == nil)
        #expect(ProcessSource.live.name(Int32.max) == nil)
        #expect(ProcessSource.live.path(Int32.max) == nil)
    }
}
