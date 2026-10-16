import Testing
@testable import PerformanceModule

@Suite struct MemoryPresentationTests {
    static let gigabyte: UInt64 = 1 << 30
    static let megabyte: UInt64 = 1 << 20

    @Test func sizesOfAGigabyteOrMoreHaveOneDecimalAndACommaWithoutAZeroDecimal() {
        #expect(MemoryFormat.bytes(32 * Self.gigabyte) == "32 GB")
        #expect(MemoryFormat.bytes(Self.gigabyte * 251 / 10) == "25,1 GB")
        #expect(MemoryFormat.bytes(Self.gigabyte * 3 / 2) == "1,5 GB")
        #expect(MemoryFormat.bytes(Self.gigabyte) == "1 GB")
        #expect(MemoryFormat.bytes(Self.gigabyte + Self.megabyte) == "1 GB")
    }

    @Test func sizesUnderAGigabyteAreWholeMegabytes() {
        #expect(MemoryFormat.bytes(512 * Self.megabyte) == "512 MB")
        #expect(MemoryFormat.bytes(Self.gigabyte - 1) == "1024 MB")
        #expect(MemoryFormat.bytes(Self.megabyte) == "1 MB")
    }

    @Test func sizesUnderAMegabyteAreKilobytes() {
        #expect(MemoryFormat.bytes(100 * 1024) == "100 KB")
        #expect(MemoryFormat.bytes(0) == "0 KB")
    }

    @Test func percentIsAWholeNumber() {
        #expect(MemoryFormat.percent(0.784) == "78%")
        #expect(MemoryFormat.percent(0.785) == "79%")
        #expect(MemoryFormat.percent(1) == "100%")
        #expect(MemoryFormat.percent(0) == "0%")
    }

    @Test func eachPressureHasAVietnameseName() {
        #expect(MemoryFormat.pressure(.normal) == "Bình thường")
        #expect(MemoryFormat.pressure(.warning) == "Cảnh báo")
        #expect(MemoryFormat.pressure(.critical) == "Nghiêm trọng")
        #expect(MemoryFormat.pressure(nil) == "—")
    }

    @Test func thisMacsMemoryIsSaidInWordsAndNumbers() {
        let usage = MemoryUsage(
            total: 32 * Self.gigabyte, used: Self.gigabyte * 251 / 10, compressed: Self.gigabyte * 86 / 10,
            swapUsed: Self.gigabyte * 52 / 10, pressure: .warning
        )
        let presentation = MemoryPresentation(usage)
        #expect(presentation.used == "25,1 GB")
        #expect(presentation.total == "32 GB")
        #expect(presentation.percent == "78%")
        #expect(abs(presentation.fraction - 25.1 / 32) < 1e-6)
        #expect(presentation.pressure == "Cảnh báo")
        #expect(presentation.tone == .caution)
        #expect(presentation.swap == "5,2 GB")
        #expect(presentation.compressed == "8,6 GB")
        #expect(presentation.accessibilityLabel == "Bộ nhớ đã dùng 25,1 GB trên 32 GB, 78%. Áp lực Cảnh báo. Swap 5,2 GB. Bộ nhớ nén 8,6 GB")
    }

    @Test func aPressureTheSystemWouldNotSayHasNoToneButTheNumbersStay() {
        let presentation = MemoryPresentation(MemoryUsage(total: 8 * Self.gigabyte, used: 4 * Self.gigabyte, compressed: 0, swapUsed: 0, pressure: nil))
        #expect(presentation.tone == nil)
        #expect(presentation.percent == "50%")
        #expect(presentation.pressure == "—")
    }

    @Test func nothingReadYetShowsDashes() {
        let presentation = MemoryPresentation(nil)
        #expect([presentation.used, presentation.total, presentation.percent, presentation.pressure, presentation.swap, presentation.compressed].allSatisfy { $0 == "—" })
        #expect(presentation.fraction == 0 && presentation.tone == nil)
        #expect(presentation.accessibilityLabel == "Chưa đọc được bộ nhớ")
    }
}
