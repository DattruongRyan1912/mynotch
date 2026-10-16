import Darwin
import Testing
@testable import PerformanceModule

@Suite struct MemoryUsageTests {
    /// Page counts this Mac reported while the probe ran: 16 KB pages.
    let counters = VMCounters(internalPages: 861_111, purgeablePages: 3_304, wiredPages: 222_459, compressedPages: 563_873)
    let pageSize: UInt64 = 16_384

    @Test func theMemoryUsedIsAppPlusWiredPlusCompressedLikeActivityMonitor() {
        let usage = MemoryUsage(total: 34_359_738_368, counters: counters, pageSize: pageSize, swapUsed: 0, pressure: .normal)
        #expect(usage.used == (861_111 - 3_304 + 222_459 + 563_873) * 16_384)
        #expect(usage.compressed == 563_873 * 16_384)
    }

    @Test func purgeableMemoryIsNotCountedAsUsed() {
        let usage = MemoryUsage(
            total: 1 << 33, counters: VMCounters(internalPages: 1_000, purgeablePages: 400, wiredPages: 100, compressedPages: 50),
            pageSize: 4_096, swapUsed: 0, pressure: nil
        )
        #expect(usage.used == (600 + 100 + 50) * 4_096)
    }

    @Test func moreCachedThanInternalPagesDoesNotUnderflow() {
        let usage = MemoryUsage(
            total: 1 << 33, counters: VMCounters(internalPages: 100, purgeablePages: 400, wiredPages: 10, compressedPages: 5),
            pageSize: 4_096, swapUsed: 0, pressure: nil
        )
        #expect(usage.used == 15 * 4_096)
    }

    @Test func theCountersComeFromTheSystemsStatisticsStruct() {
        var statistics = vm_statistics64()
        statistics.internal_page_count = 861_111
        statistics.purgeable_count = 3_304
        statistics.wire_count = 222_459
        statistics.compressor_page_count = 563_873
        #expect(VMCounters(statistics) == counters)
    }

    @Test func theShareInUseIsAFractionOfTheTotal() {
        let usage = MemoryUsage(total: 32 << 30, used: 8 << 30, compressed: 0, swapUsed: 0, pressure: nil)
        #expect(usage.fraction == 0.25)
    }

    @Test func theShareNeverPassesOne() {
        #expect(MemoryUsage(total: 8 << 30, used: 9 << 30, compressed: 0, swapUsed: 0, pressure: nil).fraction == 1)
    }

    @Test func aMacThatSaysItHasNoMemoryHasNoShare() {
        #expect(MemoryUsage(total: 0, used: 5, compressed: 0, swapUsed: 0, pressure: nil).fraction == 0)
    }

    @Test func thePressureLevelsTheSystemReportsMapToTheThreeStates() {
        #expect(MemoryPressure(level: 1) == .normal)
        #expect(MemoryPressure(level: 2) == .warning)
        #expect(MemoryPressure(level: 4) == .critical)
    }

    @Test func aPressureLevelItDoesNotKnowIsNotGuessed() {
        for level in [0, 3, 5, 8, 16, -1] { #expect(MemoryPressure(level: level) == nil, "\(level)") }
    }

    @Test func eachPressureHasItsTone() {
        #expect(Tone(.normal) == .normal)
        #expect(Tone(.warning) == .caution)
        #expect(Tone(.critical) == .critical)
    }
}
