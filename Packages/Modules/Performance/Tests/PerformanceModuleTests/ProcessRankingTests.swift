import Foundation
import Synchronization
import Testing
@testable import PerformanceModule

@Suite struct ProcessRankingTests {
    /// How often a source was asked for each thing.
    nonisolated final class Asked: Sendable {
        private let counts = Mutex((footprints: 0, names: 0, paths: 0))
        var footprints: Int { counts.withLock { $0.footprints } }
        var names: Int { counts.withLock { $0.names } }
        var paths: Int { counts.withLock { $0.paths } }
        func footprint() { counts.withLock { $0.footprints += 1 } }
        func name() { counts.withLock { $0.names += 1 } }
        func path() { counts.withLock { $0.paths += 1 } }
    }

    struct Entry {
        var footprint: UInt64?
        var name: String? = nil
        var path: String? = nil
    }

    func source(_ table: [Int32: Entry], asked: Asked = Asked()) -> ProcessSource {
        ProcessSource(
            pids: { table.keys.sorted() },
            footprint: { asked.footprint(); return table[$0]?.footprint },
            name: { asked.name(); return table[$0]?.name },
            path: { asked.path(); return table[$0]?.path }
        )
    }

    @Test func theHeaviestComeFirst() {
        let top = ProcessRanking.top(3, from: source([
            10: Entry(footprint: 300, name: "c"), 11: Entry(footprint: 900, name: "a"), 12: Entry(footprint: 100, name: "d"),
            13: Entry(footprint: 500, name: "b"),
        ]))
        #expect(top.map(\.name) == ["a", "b", "c"])
        #expect(top.map(\.footprint) == [900, 500, 300])
        #expect(top.map(\.pid) == [11, 13, 10])
    }

    @Test func equalFootprintsGoByProcessNumber() {
        let top = ProcessRanking.top(5, from: source([30: Entry(footprint: 5), 20: Entry(footprint: 5), 25: Entry(footprint: 5)]))
        #expect(top.map(\.pid) == [20, 25, 30])
    }

    @Test func processesThatCannotBeReadAreSkipped() {
        let top = ProcessRanking.top(3, from: source([
            1: Entry(footprint: nil, name: "launchd"), 2: Entry(footprint: 700, name: "x"), 3: Entry(footprint: nil, name: "kernel helper"),
            4: Entry(footprint: 200, name: "y"),
        ]))
        #expect(top.map(\.pid) == [2, 4])
    }

    @Test func theKernelsOwnNumberAndNegativeOnesAreSkipped() {
        let top = ProcessRanking.top(5, from: source([0: Entry(footprint: 999_999), -1: Entry(footprint: 999_999), 7: Entry(footprint: 10)]))
        #expect(top.map(\.pid) == [7])
    }

    @Test func aProcessHoldingNothingIsSkipped() {
        let top = ProcessRanking.top(5, from: source([7: Entry(footprint: 0), 8: Entry(footprint: 10)]))
        #expect(top.map(\.pid) == [8])
    }

    @Test func fewerProcessesThanTheLimitAreAllReturned() {
        #expect(ProcessRanking.top(5, from: source([7: Entry(footprint: 1), 8: Entry(footprint: 2)])).count == 2)
        #expect(ProcessRanking.top(5, from: source([:])).isEmpty)
    }

    @Test func aLimitOfZeroDoesNotLookAtAnyProcess() {
        let asked = Asked()
        #expect(ProcessRanking.top(0, from: source([7: Entry(footprint: 1)], asked: asked)).isEmpty)
        #expect(asked.footprints == 0)
    }

    @Test func namesAndPathsAreLookedUpForTheWinnersOnly() {
        let asked = Asked()
        let table = Dictionary(uniqueKeysWithValues: (1...100).map { (Int32($0), Entry(footprint: UInt64($0), name: "p\($0)", path: "/bin/p\($0)")) })
        let top = ProcessRanking.top(5, from: source(table, asked: asked))
        #expect(top.count == 5)
        #expect(asked.footprints == 100)
        #expect(asked.names <= 5 && asked.paths == 5)
    }

    @Test func theNameIsTheExecutablesFileNameWhenThereIsAPathBecauseTheKernelCutsItsOwnShort() {
        let top = ProcessRanking.top(1, from: source([
            9: Entry(footprint: 5, name: "com.apple.Virtualization.Virtua", path: "/System/Library/X.xpc/Contents/MacOS/com.apple.Virtualization.VirtualMachine"),
        ]))
        #expect(top.first?.name == "com.apple.Virtualization.VirtualMachine")
        #expect(top.first?.path == "/System/Library/X.xpc/Contents/MacOS/com.apple.Virtualization.VirtualMachine")
    }

    @Test func withoutAPathTheKernelsNameIsUsedAndWithoutEitherTheNumber() {
        let top = ProcessRanking.top(2, from: source([9: Entry(footprint: 5, name: "python3.11"), 8: Entry(footprint: 4)]))
        #expect(top.map(\.name) == ["python3.11", "Tiến trình 8"])
        #expect(top.allSatisfy { $0.path == nil })
    }

    @Test func anAppsHelperIsFoundInsideItsApp() {
        let helper = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/155/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
        #expect(ProcessRanking.appBundlePath(of: helper) == "/Applications/Google Chrome.app")
        #expect(ProcessRanking.appBundlePath(of: "/Applications/Docker.app/Contents/MacOS/com.docker.backend") == "/Applications/Docker.app")
    }

    @Test func anExecutableOutsideAnyAppHasNoApp() {
        #expect(ProcessRanking.appBundlePath(of: "/usr/libexec/rapportd") == nil)
        #expect(ProcessRanking.appBundlePath(of: "/Users/me/.local/bin/python3.11") == nil)
        #expect(ProcessRanking.appBundlePath(of: "/Users/me/My.application/bin/x") == nil)
    }
}
