import Testing
@testable import FanHelperKit
@testable import PerformanceModule

/// The key names are the ones this Mac's SMC lists (TH0 report).
@Suite struct SMCSensorCatalogTests {
    static let performanceCores = [
        "Tp00", "Tp01", "Tp02", "Tp04", "Tp05", "Tp06", "Tp08", "Tp09", "Tp0A", "Tp0C", "Tp0D", "Tp0E", "Tp0G", "Tp0H", "Tp0I",
        "Tp0K", "Tp0L", "Tp0M", "Tp0O", "Tp0P", "Tp0Q", "Tp0S", "Tp0T", "Tp0U", "Tp0W", "Tp0X", "Tp0Y", "Tp0a", "Tp0b", "Tp0c",
    ]
    static let efficiencyKeys = ["Te00", "Te01", "Te02"]
    static let gpuKeys = ["Tg04", "Tg05", "Tg0C", "Tg0D"]
    /// Temperature-looking keys that are not die sensors: aggregates, regulators, PMU, board, battery, an `ioft` and the
    /// ones that read zero.
    static let others = [
        "TCMz", "TCMb", "TCDX", "TCHP", "TC10", "TVD0", "TVV0", "TVMD", "Ta00", "Ta05", "Ta06", "Tm02", "Tm06", "Th00", "Ts00",
        "Td00", "TPD0", "TRD0", "TDBP", "TB0T", "TW0P", "TG0H", "TG0B", "TS0P", "TaLP", "Tz11", "TA0P", "TC0P", "TG0P",
    ]

    @Test func performanceAndEfficiencyKeysAreTheCPU() {
        for key in Self.performanceCores + Self.efficiencyKeys { #expect(SMCSensorCatalog.role(of: key) == .cpu, "\(key)") }
    }

    @Test func gpuKeysAreTheGPU() {
        for key in Self.gpuKeys { #expect(SMCSensorCatalog.role(of: key) == .gpu, "\(key)") }
    }

    @Test func aggregatesPMUAndBoardKeysAreNeither() {
        for key in Self.others { #expect(SMCSensorCatalog.role(of: key) == nil, "\(key)") }
    }

    @Test func aKeyIsTheRightLengthToCount() {
        #expect(SMCSensorCatalog.role(of: "Tp") == nil)
        #expect(SMCSensorCatalog.role(of: "Tp0") == nil)
        #expect(SMCSensorCatalog.role(of: "Tp0000") == nil)
    }

    @Test func listingEveryKeySortsTheDieSensorsOutAndKeepsTheirOrder() {
        let all = Self.others + Self.gpuKeys + Self.performanceCores + Self.efficiencyKeys
        let found = SMCSensorCatalog.dieSensors(in: all)
        #expect(found.cpu == Self.performanceCores + Self.efficiencyKeys)
        #expect(found.gpu == Self.gpuKeys)
        #expect(found.cpu.count == 33)
    }

    @Test func aMacWithoutDieKeysFindsNone() {
        let found = SMCSensorCatalog.dieSensors(in: Self.others)
        #expect(found.cpu.isEmpty && found.gpu.isEmpty)
    }
}
